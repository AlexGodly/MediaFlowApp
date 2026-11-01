// What the website does every time it saves the Library (persistLibrary):
//   v335 first-episode reward → v334 first-start reward → original save
//   → v348 award multiplier on those rewards + award-time completion bonus.
// The website remembers each title's state as of the last save; [LibraryTracker]
// does the same so rewards are given once, on the first transition.

import '../util/js.dart';
import 'leveling.dart';

class LibraryTracker {
  LibraryTracker(Map<String, dynamic> state) {
    for (final raw in asList(state['library'])) {
      final item = asMap(raw);
      final id = jsStr(item?['id']);
      if (item == null || id.isEmpty) continue;
      _started.putIfAbsent(id, () => isStarted(item));
      _completed.putIfAbsent(id, () => isCompletedItem(item));
      _progress.putIfAbsent(id, () => _progressOf(item));
    }
  }

  final Map<String, bool> _started = {};
  final Map<String, bool> _completed = {};
  final Map<String, double> _progress = {};

  bool wasCompleted(String id) => _completed[id] ?? false;
  bool knows(String id) => _completed.containsKey(id);

  static double _progressOf(Map<String, dynamic> item) {
    final p = jsNum(item['progress']);
    return p < 0 ? 0 : p;
  }

  /// Runs the website's persistLibrary reward hooks. Returns XP awarded (for display).
  double save(Map<String, dynamic> state, Leveling l, int now, String Function() uid) {
    final ledger = ledgerOf(state);
    // v334Ledger / v348Ledger make sure their maps exist on every save.
    for (final key in const ['v334ActiveTimeDays', 'v334StartedTitles', 'v334CollectionCreates', 'v334CollectionEdits']) {
      mapIn(ledger, key);
    }
    if (l.enabled) {
      for (final key in const ['v348ActionEvents', 'v348LibraryAdditionBonus', 'v348LibraryCompletionBonus']) {
        mapIn(ledger, key);
      }
    }
    final meta = mapIn(ledger, 'v348EventMeta');
    final before = {
      'v334StartedTitles': Map<String, dynamic>.from(mapIn(ledger, 'v334StartedTitles')),
      'v335FirstEpisodeRewards': Map<String, dynamic>.from(mapIn(ledger, 'v335FirstEpisodeRewards')),
    };
    final categories = <String, String>{};
    for (final c in asList(state['categories'])) {
      final m = asMap(c);
      if (m != null) categories.putIfAbsent(jsStr(m['id']), () => jsStr(m['unit']).toLowerCase());
    }
    final lev = asMap(asMap(state['settings'])?['leveling']) ?? const {};
    final disabled = lev['enabled'] == false;
    var xp = 0.0;

    final library = asList(state['library']).map(asMap).whereType<Map<String, dynamic>>().toList();
    // v335: first episode of an episode-based title.
    final firstEpisode = mapIn(ledger, 'v335FirstEpisodeRewards');
    for (final item in library) {
      final id = jsStr(item['id']);
      if (id.isEmpty) continue;
      final after = _progressOf(item);
      if (_progress[id] == 0 && after > 0 && categories[jsStr(item['categoryId'])] == 'episodes' &&
          !firstEpisode.containsKey(id)) {
        final raw = lev['firstEpisodeXP'] ?? 20;
        final amount = jsNumOrNull(raw) ?? 20;
        firstEpisode[id] = disabled ? 0 : jsOut(jsRound(amount.clamp(0, 100000).toDouble()));
      }
      _progress[id] = after;
    }
    // v334: first time a title becomes started.
    final started = mapIn(ledger, 'v334StartedTitles');
    for (final item in library) {
      final id = jsStr(item['id']);
      if (id.isEmpty) continue;
      final now0 = isStarted(item);
      if (_started[id] == false && now0 && !started.containsKey(id)) {
        started[id] = disabled ? 0 : jsOut(jsRound(l.reward('firstTitleStartXP')));
      }
      _started[id] = now0;
    }
    if (l.enabled) {
      final multiplier = awardMultiplier(l, asList(state['sessions']), now);
      // v348RaiseNewRewards
      for (final key in before.keys) {
        final after = mapIn(ledger, key);
        for (final e in after.entries.toList()) {
          final added = jsNum(e.value) - jsNum(before[key]![e.key]);
          if (added > 0) {
            final award = jsRound(added * multiplier);
            final inc = award - added;
            if (inc > 0) after[e.key] = jsOut(jsNum(e.value) + inc);
            meta['$key:${e.key}:$now:${uid()}'] = {
              'kind': key, 'baseXP': jsOut(added), 'multiplier': jsOut(multiplier), 'xp': jsOut(award),
              'timestamp': now, 'source': key == 'v334StartedTitles' ? 'First title start' : 'First episode',
              'subjectId': e.key,
            };
            xp += award;
          }
        }
      }
      // v348: award-time streak bonus over base completion XP.
      final completionBonus = mapIn(ledger, 'v348LibraryCompletionBonus');
      for (final item in library) {
        final id = jsStr(item['id']);
        if (id.isEmpty || !_completed.containsKey(id)) continue;
        if (_completed[id] == false && isCompletedItem(item) && !completionBonus.containsKey(id)) {
          final amount = l.completionXP;
          final award = jsRound(amount * multiplier);
          completionBonus[id] = jsOut(award - amount < 0 ? 0.0 : award - amount);
          meta['library-complete:$id'] = {
            'kind': 'completedLibrary', 'baseXP': jsOut(amount), 'multiplier': jsOut(multiplier), 'xp': jsOut(award),
            'timestamp': now, 'source': 'Library · title completed', 'subjectId': id,
          };
          xp += award;
        }
      }
    }
    for (final item in library) {
      final id = jsStr(item['id']);
      if (id.isNotEmpty) _completed[id] = isCompletedItem(item);
    }
    return xp;
  }
}

bool isStarted(Map<String, dynamic> item) =>
    item['status'] == 'active' || jsNum(item['progress']) > 0 || jsNum(item['startedAt']) > 0;

/// `v120IsCompleted`.
bool isCompletedItem(Map<String, dynamic> item) {
  if (item['status'] == 'completed') return true;
  final total = jsNumOrNull(item['total']);
  return item['total'] != null && total != null && total > 0 && jsNum(item['progress']) >= total;
}

Map<String, dynamic> ledgerOf(Map<String, dynamic> state) => mapIn(state, 'xpLedger');

/// Map stored under [key], created (or made mutable/typed) if needed.
Map<String, dynamic> mapIn(Map<String, dynamic> parent, String key) {
  final v = parent[key];
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    final cast = Map<String, dynamic>.from(v);
    parent[key] = cast;
    return cast;
  }
  final created = <String, dynamic>{};
  parent[key] = created;
  return created;
}

List<dynamic> listIn(Map<String, dynamic> parent, String key) {
  final v = parent[key];
  if (v is List) return v;
  final created = <dynamic>[];
  parent[key] = created;
  return created;
}
