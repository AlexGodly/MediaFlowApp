// Runs the website's ratings engine for one title ("Refresh ratings", v555
// `mf467RefreshRatings`) or for every title missing ratings ("Refresh all
// missing ratings", v555 bulk), and saves the result as a normal account edit.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../logic/ratings_engine.dart';
import '../util/js.dart';
import 'account_controller.dart';
import 'rating_sources.dart';

class RatingsRefresh extends ChangeNotifier {
  RatingsRefresh._();
  static final RatingsRefresh instance = RatingsRefresh._();

  /// The title being refreshed ('' when idle) and what is happening.
  String titleId = '';
  String note = '';
  bool? success;
  StopToken? _stop;

  // Bulk refresh.
  bool bulkRunning = false;
  int bulkDone = 0, bulkTotal = 0, bulkRatings = 0, bulkIds = 0;
  String bulkCurrent = '', bulkNote = '';
  StopToken? _bulkStop;

  bool get working => titleId.isNotEmpty;

  static TitleKind kindFor(AccountController account, Map<String, dynamic> item) {
    final cat = account.view?.category(jsStr(item['categoryId']));
    return TitleKind(unit: jsStr(cat?.raw['unit']), type: jsStr(cat?.raw['type']));
  }

  static Map<String, dynamic>? _item(AccountController account, String id) {
    for (final raw in asList(account.view?.state['library'])) {
      final m = asMap(raw);
      if (m != null && jsStr(m['id']) == id) return m;
    }
    return null;
  }

  /// The rating sources for a title (empty when none is ready).
  static Future<List<String>> sourcesFor(AccountController account, Map<String, dynamic> item) async {
    final ready = await RatingSources.instance.gatewayReady();
    return ratingSourcesFor(item, asMap(account.view?.state['settings']), kindFor(account, item), ready);
  }

  void stop() {
    _stop?.stop();
  }

  /// Refreshes one title. Returns a short result for a message.
  Future<({bool ok, String note, int ratings, int ids, List<(String, String)> failures})> refresh(
    AccountController account,
    String id, {
    StopToken? stop,
  }) async {
    final found = _item(account, id);
    if (found == null || !account.hasData) {
      return (ok: false, note: 'Save the title and finish loading MediaFlow first.', ratings: 0, ids: 0, failures: const <(String, String)>[]);
    }
    if (working) {
      return (ok: false, note: 'Another ratings refresh is already running.', ratings: 0, ids: 0, failures: const <(String, String)>[]);
    }
    final item = jsonClone(found) as Map<String, dynamic>;
    final token = stop ?? StopToken();
    _stop = token;
    titleId = id;
    note = 'Checking saved IDs…';
    success = null;
    notifyListeners();
    try {
      final providers = await sourcesFor(account, item);
      if (providers.isEmpty) {
        throw Exception('No ready rating sources. Enable/configure them in Provider Management.');
      }
      final result = await ratingsForTitle(
        item,
        providers: providers,
        kind: kindFor(account, item),
        lookup: (p, q) => RatingSources.instance.lookup(p, q, stop: token),
        wikidata: (ids) => RatingSources.instance.wikidata(ids, stop: token),
        stop: token,
        progress: (n) {
          note = n;
          notifyListeners();
        },
      );
      token.check();
      // Written onto the current copy of the title, like the website's save.
      var written = const RatingsWritten(0, 0);
      await account.edit((s, now) {
        for (final raw in asList(s['library'])) {
          final m = asMap(raw);
          if (m != null && jsStr(m['id']) == id) {
            written = applyRatings(m, result, now);
            return;
          }
        }
      }, label: 'Refresh ratings', undoable: false);
      final parts = [
        if (written.ratings > 0) '${written.ratings} rating${written.ratings == 1 ? '' : 's'}',
        if (written.ids > 0) '${written.ids} ID${written.ids == 1 ? '' : 's'}',
      ];
      note = parts.isNotEmpty
          ? '${parts.join(' and ')} saved.'
          : result.accepted.isNotEmpty
              ? 'Ratings already up to date.'
              : 'No verified match found.${result.failures.isNotEmpty ? ' Some sources were unavailable.' : ''}';
      success = true;
      return (ok: true, note: note, ratings: written.ratings, ids: written.ids, failures: result.failures);
    } catch (e) {
      note = e is RatingsStopped ? 'Stopped' : '$e'.replaceFirst('Exception: ', '');
      if (note.length > 160) note = note.substring(0, 160);
      success = false;
      return (ok: false, note: note, ratings: 0, ids: 0, failures: const <(String, String)>[]);
    } finally {
      titleId = '';
      _stop = null;
      notifyListeners();
    }
  }

  /// "Refresh all missing ratings": titles with no ratings first.
  Future<void> refreshAllMissing(AccountController account) async {
    if (bulkRunning || !account.hasData) return;
    final token = StopToken();
    _bulkStop = token;
    bulkRunning = true;
    bulkDone = bulkTotal = bulkRatings = bulkIds = 0;
    bulkCurrent = 'Finding titles with missing ratings…';
    bulkNote = '';
    notifyListeners();
    var quotaStreak = 0;
    try {
      final ready = await RatingSources.instance.gatewayReady();
      final settings = asMap(account.view?.state['settings']);
      final empty = <String>[], partial = <String>[];
      final lib = List<dynamic>.of(asList(account.view?.state['library']));
      for (var i = 0; i < lib.length; i++) {
        final item = asMap(lib[i]);
        if (item != null && item['id'] != null) {
          final providers = ratingSourcesFor(item, settings, kindFor(account, item), ready);
          if (providers.isNotEmpty && missingRating(item, providers)) {
            (hasNoRatings(item) ? empty : partial).add(jsStr(item['id']));
          }
        }
        if (i % 400 == 399) {
          await Future<void>.delayed(Duration.zero);
          token.check();
        }
      }
      final queue = [...empty, ...partial];
      bulkTotal = queue.length;
      if (queue.isEmpty) {
        bulkNote = 'Every title already has the ratings its sources can provide.';
        return;
      }
      for (final id in queue) {
        if (token.stopped) break;
        final item = _item(account, id);
        if (item == null) {
          bulkDone++;
          continue;
        }
        bulkCurrent = cleanTitle(item['title']).isEmpty ? 'Untitled' : cleanTitle(item['title']);
        notifyListeners();
        for (var w = 0; w < 60 && working; w++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          token.check();
        }
        final r = await refresh(account, id, stop: token);
        bulkDone++;
        bulkRatings += r.ratings;
        bulkIds += r.ids;
        final quota = r.failures.where((f) => RegExp(r'quota|limit reached', caseSensitive: false).hasMatch(f.$2)).length;
        quotaStreak = quota > 0 && quota >= r.failures.length && r.ratings == 0 ? quotaStreak + 1 : 0;
        if (quotaStreak >= 5) {
          bulkNote = 'Paused: the rating sources’ daily limit was reached. Try again tomorrow.';
          break;
        }
        notifyListeners();
      }
      if (bulkNote.isEmpty) {
        bulkNote = token.stopped
            ? 'Stopped. $bulkDone of $bulkTotal titles checked.'
            : 'Done. $bulkDone titles checked, $bulkRatings ratings and $bulkIds IDs saved.';
      }
    } catch (e) {
      bulkNote = e is RatingsStopped ? 'Stopped.' : 'Stopped: $e';
    } finally {
      bulkRunning = false;
      bulkCurrent = '';
      _bulkStop = null;
      notifyListeners();
    }
  }

  void stopAll() {
    _bulkStop?.stop();
    _stop?.stop();
  }

  /// Refreshes the ratings of several titles one after another (On This Day).
  Future<String> refreshMany(AccountController account, List<String> ids) async {
    var ratings = 0, idsSaved = 0, done = 0;
    for (final id in ids) {
      final r = await refresh(account, id);
      if (!r.ok && r.note == 'Stopped') break;
      done++;
      ratings += r.ratings;
      idsSaved += r.ids;
    }
    return '$done title${done == 1 ? '' : 's'} checked · $ratings rating${ratings == 1 ? '' : 's'} and $idsSaved ID${idsSaved == 1 ? '' : 's'} saved.';
  }
}

/// Keeps a background job alive without awaiting it.
void fireAndForget(Future<void> f) => unawaited(f);
