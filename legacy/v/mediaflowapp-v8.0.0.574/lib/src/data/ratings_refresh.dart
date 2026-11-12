// Runs the website's ratings engine for one title ("Refresh ratings", v555
// `mf467RefreshRatings`) or for every title missing ratings ("Refresh all
// missing ratings", v555 bulk), and saves the result as a normal account edit.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../logic/ratings_engine.dart';
import '../util/js.dart';
import 'account_controller.dart';
import 'app_prefs.dart';
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

/// Automatic rating catch-up (website v547 `v547ExternalRatingRefresh`, v555
/// limits): while the app is open, titles still missing ratings are refreshed
/// one at a time — at most one every 20 seconds, 60 an hour and 500 a day on
/// this device — and a title is not retried for 24 hours.
extension RatingsAutoCatchUp on RatingsRefresh {
  static Timer? _timer;
  static AccountController? _account;
  static int _cursor = 0;
  static bool _busy = false;
  static String autoNote = 'Waiting for eligible titles';

  static const intervals = [24, 72, 168, 720];

  /// `mf547Prefs`.
  static Map<String, dynamic> prefs(Map<String, dynamic>? settings) {
    final raw = asMap(settings?['v547ExternalRatingRefresh']) ?? const <String, dynamic>{};
    final h = jsNum(raw['intervalHours']);
    return {
      'enabled': raw['enabled'] != false,
      'intervalHours': intervals.contains(h) ? h.toInt() : 168,
      'refreshExisting': raw['refreshExisting'] == true,
    };
  }

  /// `App.mf547Set('enabled', on)`.
  static Future<void> setEnabled(AccountController account, bool on) {
    final p = prefs(asMap(account.view?.state['settings']));
    p['enabled'] = on;
    return account.setSetting(['v547ExternalRatingRefresh'], p);
  }

  void startAuto(AccountController account) {
    _account = account;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_tick()));
  }

  void stopAuto() {
    _timer?.cancel();
    _timer = null;
    _account = null;
  }

  static bool _foreground() {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
  }

  static Map<String, int> _tried() {
    try {
      final m = jsonDecode(AppPrefs.instance.get<String>('ratingAutoTried', '{}')) as Map;
      return {for (final e in m.entries) '${e.key}': (e.value as num).toInt()};
    } catch (_) {
      return {};
    }
  }

  static bool _withinLimits(DateTime now) {
    final hour = '${now.year}-${now.month}-${now.day}-${now.hour}', day = '${now.year}-${now.month}-${now.day}';
    final h = AppPrefs.instance.get<String>('ratingAutoHour', '').split('|'), d = AppPrefs.instance.get<String>('ratingAutoDay', '').split('|');
    final hc = h.length == 2 && h[0] == hour ? int.tryParse(h[1]) ?? 0 : 0, dc = d.length == 2 && d[0] == day ? int.tryParse(d[1]) ?? 0 : 0;
    return hc < 60 && dc < 500;
  }

  static Future<void> _count(DateTime now) async {
    final hour = '${now.year}-${now.month}-${now.day}-${now.hour}', day = '${now.year}-${now.month}-${now.day}';
    final h = AppPrefs.instance.get<String>('ratingAutoHour', '').split('|'), d = AppPrefs.instance.get<String>('ratingAutoDay', '').split('|');
    final hc = h.length == 2 && h[0] == hour ? int.tryParse(h[1]) ?? 0 : 0, dc = d.length == 2 && d[0] == day ? int.tryParse(d[1]) ?? 0 : 0;
    await AppPrefs.instance.set('ratingAutoHour', '$hour|${hc + 1}');
    await AppPrefs.instance.set('ratingAutoDay', '$day|${dc + 1}');
  }

  Future<void> _tick() async {
    final account = _account;
    if (_busy || account == null || !account.hasData || working || bulkRunning || !_foreground()) return;
    final settings = asMap(account.view?.state['settings']);
    if (prefs(settings)['enabled'] != true) {
      autoNote = 'Automatic rating refresh paused.';
      return;
    }
    final now = DateTime.now();
    if (!_withinLimits(now)) {
      autoNote = 'Hourly / daily safety limit reached; continuing later.';
      return;
    }
    _busy = true;
    try {
      final ready = await RatingSources.instance.gatewayReady();
      final lib = asList(account.view?.state['library']);
      if (lib.isEmpty) return;
      final tried = _tried();
      final cutoff = now.millisecondsSinceEpoch - const Duration(hours: 24).inMilliseconds;
      tried.removeWhere((_, at) => at < cutoff);
      String? next;
      for (var n = 0; n < 600 && n < lib.length; n++) {
        final item = asMap(lib[(_cursor + n) % lib.length]);
        final id = jsStr(item?['id']);
        if (item == null || id.isEmpty || tried.containsKey(id)) continue;
        final providers = ratingSourcesFor(item, settings, RatingsRefresh.kindFor(account, item), ready);
        if (providers.isNotEmpty && missingRating(item, providers)) {
          next = id;
          _cursor = (_cursor + n + 1) % lib.length;
          break;
        }
      }
      if (next == null) {
        _cursor = (_cursor + 600) % lib.length;
        autoNote = 'No missing ratings due right now.';
        return;
      }
      tried[next] = now.millisecondsSinceEpoch;
      final keep = tried.entries.toList()..sort((a, b) => b.value - a.value);
      await AppPrefs.instance.set('ratingAutoTried', jsonEncode(Map.fromEntries(keep.take(3000))));
      await _count(now);
      final r = await refresh(account, next);
      autoNote = 'Last automatic refresh: ${r.note}';
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}

/// Keeps a background job alive without awaiting it.
void fireAndForget(Future<void> f) => unawaited(f);
