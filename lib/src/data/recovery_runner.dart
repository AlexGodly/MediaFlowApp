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

  /// Paused by the person (notification, tray, workspace) or by the system
  /// (iOS while MediaFlow is in the background).
  bool paused = false, pausedBySystem = false;
  final List<String> errors = [];
  final List<CoverReview> coverReviews = [];

  /// Titles nothing was found for (for "Search manually").
  final List<String> noMatchIds = [];
  final List<MetadataPreview> metadataReviews = [];

  int get total => ids.length;
  bool get finished => !running && !stopped && done >= ids.length;

  /// What is saved so an interrupted job continues next time.
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'ids': ids,
        'label': label,
        'done': done,
        'applied': applied,
        'noMatch': noMatch,
        'noMatchIds': noMatchIds,
        'fieldsFilled': fieldsFilled,
        'xp': xp,
        'paused': paused && !pausedBySystem,
      };

  static RecoveryJob? fromJson(Object? raw) {
    final m = asMap(raw);
    if (m == null || (m['kind'] != 'cover' && m['kind'] != 'metadata')) return null;
    final ids = [for (final x in (m['ids'] as List? ?? const [])) if (x is String) x];
    final job = RecoveryJob(m['kind'] as String, ids, jsStr(m['label']))
      ..done = jsNum(m['done']).toInt().clamp(0, ids.length).toInt()
      ..applied = jsNum(m['applied']).toInt()
      ..noMatch = jsNum(m['noMatch']).toInt()
      ..noMatchIds.addAll(asList(m['noMatchIds']).map(jsStr))
      ..fieldsFilled = jsNum(m['fieldsFilled']).toInt()
      ..xp = jsNum(m['xp']).toInt()
      ..paused = m['paused'] == true;
    return job.done < ids.length ? job : null;
  }
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

  Future<void> startCover(AccountController account, List<String> ids, String label, {RecoveryJob? resume}) async {
    if (cover?.running == true) return;
    final job = resume ?? RecoveryJob('cover', ids, label);
    job.running = true;
    cover = job;
    final stop = StopToken();
    _coverStop = stop;
    notifyListeners();
    try {
      while (job.done < job.ids.length) {
        await _waitWhilePaused(job, stop);
        if (stop.stopped) break;
        final id = job.ids[job.done];
        final item = _item(account, id);
        if (item == null || !coverMissing(item)) {
          job.done++;
          continue;
        }
        job.current = cleanTitle(item['title']);
        notifyListeners();
        final candidates = await coverCandidates(account, item);
        if (stop.stopped) break;
        // mf424Process: only a verified saved ID plus a matching title is
        // saved by itself; everything else waits for the owner's choice.
        final best = candidates.firstOrNull;
        if (best != null && best.idMatch && best.confidence >= 0.95) {
          final ok = await _applyCover(account, id, best, jsNum(item['modifiedAt']).toInt(), job);
          if (!ok) job.coverReviews.add(CoverReview(id, job.current, jsNum(item['modifiedAt']).toInt(), candidates));
        } else if (candidates.isNotEmpty) {
          job.coverReviews.add(CoverReview(id, job.current, jsNum(item['modifiedAt']).toInt(), candidates));
        } else {
          job.noMatch++;
          job.noMatchIds.add(id);
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

  void stopCover() {
    cover?.paused = false;
    _coverStop?.stop();
  }

  // ---------- Pause / resume (notification, tray, iOS background) ----------

  Future<void> _waitWhilePaused(RecoveryJob job, StopToken stop) async {
    if (!job.paused) return;
    notifyListeners();
    while (job.paused && !stop.stopped) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Iterable<RecoveryJob> get _active => [cover, metadata].whereType<RecoveryJob>().where((j) => j.running);

  bool get anyRunning => _active.isNotEmpty || combinedRunning;
  bool get allPaused => _active.isNotEmpty && _active.every((j) => j.paused);

  void pauseAll({bool bySystem = false}) {
    for (final j in _active) {
      if (j.paused) continue;
      j.paused = true;
      j.pausedBySystem = bySystem;
    }
    notifyListeners();
  }

  void resumeAll({bool onlySystem = false}) {
    for (final j in _active) {
      if (onlySystem && !j.pausedBySystem) continue;
      j.paused = false;
      j.pausedBySystem = false;
    }
    notifyListeners();
  }

  void stopAll() {
    _combinedStopped = true;
    stopCover();
    stopMetadata();
  }

  bool _combinedStopped = false;

  /// `mf424Candidates`: saved External IDs get the first chance, then a name
  /// search; every name a record carries is compared with the title
  /// (`mf424Match`). Up to 24 covers of 65% confidence or more, best first.
  Future<List<CoverCandidate>> coverCandidates(AccountController account, Map<String, dynamic> item, {String? query, bool manual = false}) async {
    final cat = account.view!.category(jsStr(item['categoryId']));
    final unit = jsStr(cat.raw['unit']).isEmpty ? cat.unit : jsStr(cat.raw['unit']);
    final ids = asMap(item['externalIds']);
    final found = <String, CoverCandidate>{};
    void take(MetadataResult r) {
      final url = r.coverUrl.trim();
      if (!url.startsWith('https://') || found.containsKey(url) || found.length >= 24) return;
      final isbn = r.idMatch && r.externalIdKey == 'isbn';
      final m = isbn ? (confidence: 1.0, reason: 'Exact ISBN edition') : coverMatch(item, r.matchRecord, r.idMatch);
      if (!manual && m.confidence < 0.65) return;
      final provider = coverProviderId(r.source);
      var recordId = (r.externalId ?? '').trim();
      if (provider == 'openlibrary') recordId = recordId.replaceFirst(RegExp(r'^/works/'), '');
      found[url] = CoverCandidate(
        url: url,
        provider: provider,
        title: r.title.isEmpty ? cleanTitle(item['title']) : r.title,
        altTitles: r.altTitles,
        year: r.recordYear ?? r.year,
        format: r.subtitle,
        confidence: m.confidence,
        reason: m.reason,
        recordId: isbn ? '' : recordId,
        externalIdKey: isbn ? '' : (r.externalIdKey.isNotEmpty ? r.externalIdKey : coverExternalIdKey(provider)),
        reportedIds: r.linkedIds,
        idMatch: r.idMatch,
      );
    }

    if (query == null) {
      try {
        for (final r in await lookupByIds(ids, unit: unit)) {
          take(r);
        }
      } catch (_) {}
    }
    final names = query != null ? [query] : titleVariants(item).take(3).toList();
    for (final name in names) {
      List<MetadataResult> results;
      try {
        results = await searchMetadata(
          name,
          unit: unit,
          type: jsStr(cat.raw['type']),
          kind: tmdbKind(categoryId: cat.id, categoryName: cat.name, externalIds: ids),
          externalIds: ids,
        );
      } catch (_) {
        continue;
      }
      for (final r in results) {
        take(r);
      }
      // The title's own name found something: the other names are only a fallback.
      if (found.isNotEmpty) break;
    }
    final list = found.values.toList();
    mergeSortBy(list, (a, b) => a.confidence == b.confidence ? 0 : (b.confidence > a.confidence ? 1 : -1));
    return list;
  }

  Future<bool> _applyCover(AccountController account, String id, CoverCandidate c, int expected, RecoveryJob? job,
      {bool manual = false, bool linkIds = true}) async {
    double? xp;
    await account.edit((s, now) {
      var k = 0;
      xp = applyRecoveredCover(s, id, c, expected, now, () => mediaFlowUid(now + k++), manual: manual, linkIds: linkIds);
    }, label: 'Cover Recovery');
    if (xp == null) return false;
    if (job != null) {
      job.applied++;
      job.xp += xp!.round();
    }
    return true;
  }

  /// A cover picked in the review list.
  Future<bool> chooseCover(AccountController account, CoverReview review, CoverCandidate c, {bool linkIds = true}) async {
    final ok = await _applyCover(account, review.id, c, review.expectedModifiedAt, cover, manual: true, linkIds: linkIds);
    cover?.coverReviews.remove(review); // also when the title changed meanwhile
    notifyListeners();
    return ok;
  }

  /// A cover picked through "Search manually" for a title nothing was found for.
  Future<bool> chooseManualCover(AccountController account, String id, CoverCandidate c) async {
    final item = _item(account, id);
    if (item == null) return false;
    final ok = await _applyCover(account, id, c, jsNum(item['modifiedAt']).toInt(), cover, manual: true);
    cover?.noMatchIds.remove(id);
    cover?.coverReviews.removeWhere((r) => r.id == id);
    notifyListeners();
    return ok;
  }

  void skipCover(CoverReview review) {
    cover?.coverReviews.remove(review);
    notifyListeners();
  }

  // ---------- Combined Recovery (website v447 "both") ----------

  bool combinedRunning = false;

  /// Covers for the titles missing one, then details for those missing them.
  Future<void> startCombined(AccountController account, List<String> ids, String label) async {
    if (combinedRunning) return;
    combinedRunning = true;
    _combinedStopped = false;
    notifyListeners();
    try {
      final covers = [for (final id in ids) if (coverMissing(_item(account, id))) id];
      if (covers.isNotEmpty) await startCover(account, covers, label);
      if (cover?.stopped == true || _combinedStopped) return;
      final details = [
        for (final id in ids)
          if (_item(account, id) case final m? when !hasValue(m['synopsis']) || !hasValue(m['genres']) || !hasValue(m['year']) || !hasValue(m['mediaFormat'])) id,
      ];
      final max = jsNum(metadataPreferences(asMap(account.view?.state['settings']))['maxBatch']).toInt();
      if (details.isNotEmpty) await startMetadata(account, details.length > max ? details.sublist(0, max) : details, label);
    } finally {
      combinedRunning = false;
      notifyListeners();
    }
  }

  // ---------- Metadata Recovery ----------

  Future<void> startMetadata(AccountController account, List<String> ids, String label, {RecoveryJob? resume}) async {
    if (metadata?.running == true) return;
    final job = resume ?? RecoveryJob('metadata', ids, label);
    job.running = true;
    metadata = job;
    final stop = StopToken();
    _metaStop = stop;
    notifyListeners();
    try {
      final ready = await RatingSources.instance.gatewayReady();
      final settings = asMap(account.view?.state['settings']);
      final minConf = jsNum(metadataPreferences(settings)['minimumConfidence']);
      while (job.done < job.ids.length) {
        await _waitWhilePaused(job, stop);
        if (stop.stopped) break;
        final id = job.ids[job.done];
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

  void stopMetadata() {
    metadata?.paused = false;
    _metaStop?.stop();
  }

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
