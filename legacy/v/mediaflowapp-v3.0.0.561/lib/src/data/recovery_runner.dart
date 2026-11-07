// Runs the Recovery Workspace jobs (website v445): Cover Recovery and
// Metadata Recovery over a set of titles, one title at a time, with Stop.
// Confident results are saved as normal account edits; the rest wait for
// review in the workspace.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/ratings_engine.dart';
import '../logic/recovery.dart';
import '../logic/library_logic.dart' show findTitle;
import '../util/js.dart';
import 'account_controller.dart';
import 'metadata_search.dart';
import 'rating_sources.dart';

/// A title waiting for a cover choice.
class CoverReview {
  CoverReview(this.id, this.title, this.expectedModifiedAt, this.candidates);
  final String id, title;
  final int expectedModifiedAt;
  final List<CoverCandidate> candidates;
}

class RecoveryJob {
  RecoveryJob(this.kind, this.ids, this.label);
  final String kind; // cover | metadata
  final List<String> ids;
  final String label;
  int done = 0, applied = 0, noMatch = 0, fieldsFilled = 0, xp = 0;
  String current = '';
  bool running = true, stopped = false;
  final List<String> errors = [];
  final List<CoverReview> coverReviews = [];
  final List<MetadataPreview> metadataReviews = [];
}

class RecoveryRunner extends ChangeNotifier {
  RecoveryRunner._();
  static final RecoveryRunner instance = RecoveryRunner._();

  RecoveryJob? cover, metadata;
  StopToken? _coverStop, _metaStop;

  Map<String, dynamic>? _item(AccountController a, String id) {
    final m = findTitle(a.view?.state ?? const {}, id);
    return m;
  }

  // ---------- Cover Recovery ----------

  Future<void> startCover(AccountController account, List<String> ids, String label) async {
    if (cover?.running == true) return;
    final job = RecoveryJob('cover', ids, label);
    cover = job;
    final stop = StopToken();
    _coverStop = stop;
    notifyListeners();
    try {
      for (final id in ids) {
        if (stop.stopped) break;
        final item = _item(account, id);
        if (item == null || !coverMissing(item)) {
          job.done++;
          continue;
        }
        job.current = cleanTitle(item['title']);
        notifyListeners();
        final candidates = await _coverCandidates(account, item);
        if (stop.stopped) break;
        final confident = candidates.where((c) => c.confidence >= 0.94).toList();
        if (confident.length == 1 || (confident.isNotEmpty && confident.every((c) => c.url == confident.first.url))) {
          final ok = await _applyCover(account, id, confident.first, jsNum(item['modifiedAt']).toInt(), job);
          if (!ok) job.coverReviews.add(CoverReview(id, job.current, jsNum(item['modifiedAt']).toInt(), candidates));
        } else if (candidates.isNotEmpty) {
          job.coverReviews.add(CoverReview(id, job.current, jsNum(item['modifiedAt']).toInt(), candidates.take(8).toList()));
        } else {
          job.noMatch++;
        }
        job.done++;
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    } catch (e) {
      job.errors.add('$e');
    } finally {
      job.running = false;
      job.stopped = stop.stopped;
      job.current = '';
      notifyListeners();
    }
  }

  void stopCover() => _coverStop?.stop();

  Future<List<CoverCandidate>> _coverCandidates(AccountController account, Map<String, dynamic> item) async {
    final cat = account.view!.category(jsStr(item['categoryId']));
    final found = <String, CoverCandidate>{};
    final names = titleVariants(item).take(3).toList();
    for (final name in names) {
      List<MetadataResult> results;
      try {
        results = await searchMetadata(
          name,
          unit: jsStr(cat.raw['unit']).isEmpty ? cat.unit : jsStr(cat.raw['unit']),
          type: jsStr(cat.raw['type']),
          kind: tmdbKind(categoryId: cat.id, categoryName: cat.name, externalIds: asMap(item['externalIds'])),
          externalIds: asMap(item['externalIds']),
        );
      } catch (_) {
        continue;
      }
      for (final r in results) {
        final url = r.coverUrl.trim();
        if (!url.startsWith('https://') || found.containsKey(url)) continue;
        final ev = coverEvidence(item, r.title, r.year);
        if (ev.confidence < 0.65) continue;
        found[url] = CoverCandidate(url: url, provider: r.source.toLowerCase(), title: r.title, year: r.year, confidence: ev.confidence, reason: ev.reason);
      }
      if (found.values.any((c) => c.confidence >= 0.94)) break;
    }
    final list = found.values.toList();
    mergeSortBy(list, (a, b) => a.confidence == b.confidence ? 0 : (b.confidence > a.confidence ? 1 : -1));
    return list;
  }

  Future<bool> _applyCover(AccountController account, String id, CoverCandidate c, int expected, RecoveryJob? job) async {
    double? xp;
    await account.edit((s, now) {
      var k = 0;
      xp = applyRecoveredCover(s, id, c, expected, now, () => mediaFlowUid(now + k++));
    }, label: 'Cover Recovery');
    if (xp == null) return false;
    if (job != null) {
      job.applied++;
      job.xp += xp!.round();
    }
    return true;
  }

  /// A cover picked in the review list.
  Future<bool> chooseCover(AccountController account, CoverReview review, CoverCandidate c) async {
    final ok = await _applyCover(account, review.id, c, review.expectedModifiedAt, cover);
    cover?.coverReviews.remove(review); // also when the title changed meanwhile
    notifyListeners();
    return ok;
  }

  void skipCover(CoverReview review) {
    cover?.coverReviews.remove(review);
    notifyListeners();
  }

  // ---------- Metadata Recovery ----------

  Future<void> startMetadata(AccountController account, List<String> ids, String label) async {
    if (metadata?.running == true) return;
    final job = RecoveryJob('metadata', ids, label);
    metadata = job;
    final stop = StopToken();
    _metaStop = stop;
    notifyListeners();
    try {
      final ready = await RatingSources.instance.gatewayReady();
      final settings = asMap(account.view?.state['settings']);
      final minConf = jsNum(metadataPreferences(settings)['minimumConfidence']);
      for (final id in ids) {
        if (stop.stopped) break;
        final item = _item(account, id);
        if (item == null) {
          job.done++;
          continue;
        }
        job.current = cleanTitle(item['title']);
        notifyListeners();
        final snapshot = jsonClone(item) as Map<String, dynamic>;
        final sources = metadataSourcesFor(snapshot, settings, ready);
        if (sources.isEmpty) {
          job.errors.add('${job.current}: no metadata sources are on for this category');
          job.done++;
          continue;
        }
        final found = await discoverMetadata(snapshot, sources, (p, q) => RatingSources.instance.lookup(p, q, stop: stop),
            minimumConfidence: minConf, stop: stop);
        if (stop.stopped) break;
        final preview = metadataProposals(snapshot, found.results, minimumConfidence: minConf);
        var changed = 0;
        if (preview.ready > 0) {
          await account.edit((s, now) {
            final m = findTitle(s, id);
            if (m != null) changed = applyMetadata(m, preview, now, automatic: true, minimumConfidence: minConf).changed;
          }, label: 'Metadata Recovery');
        }
        if (changed > 0) {
          job.applied++;
          job.fieldsFilled += changed;
        }
        // Fields that need a person: conflicts and exact-title-only matches.
        final open = preview.proposals.where((p) => !p.hasOriginal && !p.isProtected && !p.same && (p.status == 'review' || p.status == 'conflict'));
        if (open.isNotEmpty) {
          for (final p in preview.proposals) {
            p.selected = false;
          }
          job.metadataReviews.add(preview);
        } else if (changed == 0) {
          job.noMatch++;
        }
        job.done++;
        notifyListeners();
      }
    } catch (e) {
      if (e is! RatingsStopped) job.errors.add('$e');
    } finally {
      job.running = false;
      job.stopped = stop.stopped;
      job.current = '';
      notifyListeners();
    }
  }

  void stopMetadata() => _metaStop?.stop();

  /// Saves the fields chosen in a review (never replacing existing values).
  Future<int> applyReview(AccountController account, MetadataPreview preview) async {
    var changed = 0;
    await account.edit((s, now) {
      final m = findTitle(s, preview.titleId);
      if (m != null) changed = applyMetadata(m, preview, now).changed;
    }, label: 'Metadata Recovery');
    metadata?.metadataReviews.remove(preview);
    if (changed > 0 && metadata != null) metadata!.fieldsFilled += changed;
    notifyListeners();
    return changed;
  }

  void skipReview(MetadataPreview preview) {
    metadata?.metadataReviews.remove(preview);
    notifyListeners();
  }
}
