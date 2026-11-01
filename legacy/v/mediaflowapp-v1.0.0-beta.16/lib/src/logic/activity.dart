// Library History (the website's `activityLog`): what `mfBegin`/`mfCommit` record
// for a change — the v43 field diff of Library titles, the XP the change earned
// (v50SnapshotXP), exact title ids and, for deletions, full v191 snapshots so a
// deleted title can be restored later.

import 'dart:convert';
import 'dart:math' as math;

import '../state/lazy_copy.dart';
import '../util/js.dart';
import 'stats.dart' show xpMetrics;

T _clone<T>(T v) => jsonClone(v) as T;

/// `mfCoreSnapshot`. On a [LazyStateCopy], parts the edit has not touched yet
/// are taken from the original account as they are (an edit never changes the
/// original), so nothing is copied for them.
Map<String, dynamic> coreSnapshot(Map<String, dynamic> state) {
  final lazy = state is LazyStateCopy ? state : null;
  Object? part(String k, Object fallback) =>
      lazy != null && !lazy.isTouched(k) ? (lazy.original[k] ?? fallback) : _clone(state[k] ?? fallback);
  return {
    'library': asList(part('library', const [])),
    'sessions': asList(part('sessions', const [])),
    'completionTimeline': asList(part('completionTimeline', const [])),
    'xpLedger': asMap(part('xpLedger', const {'libraryAdditions': {}})) ?? const {'libraryAdditions': {}},
  };
}

/// The same parts as they are now, for reading only (no copies).
Map<String, dynamic> _currentCore(Map<String, dynamic> state) => {
      'library': asList(readOnlyPart(state, 'library')),
      'sessions': asList(readOnlyPart(state, 'sessions')),
      'completionTimeline': asList(readOnlyPart(state, 'completionTimeline')),
      'xpLedger': asMap(readOnlyPart(state, 'xpLedger')) ?? const {'libraryAdditions': {}},
    };

String _show(Object? v) => v == null ? '—' : (v is num && v == v.truncateToDouble() ? v.toInt().toString() : '$v');

/// `v43DiffSnapshot`.
List<Map<String, dynamic>> diffSnapshot(Map<String, dynamic> before, Map<String, dynamic> after) {
  Map<String, Map<String, dynamic>> index(Object? list) {
    final out = <String, Map<String, dynamic>>{};
    for (final raw in asList(list)) {
      final m = asMap(raw);
      if (m != null) out[jsStr(m['id'])] = m;
    }
    return out;
  }

  final b = index(before['library']), a = index(after['library']);
  final ids = <String>{...b.keys, ...a.keys};
  final changes = <Map<String, dynamic>>[];
  for (final id in ids) {
    final x = b[id], y = a[id];
    if (x == null && y != null) {
      changes.add({'id': id, 'title': cleanTitle(y['title']), 'kind': 'added'});
    } else if (x != null && y == null) {
      changes.add({'id': id, 'title': cleanTitle(x['title']), 'kind': 'deleted'});
    } else if (x != null && y != null) {
      final fields = <String>[];
      for (final k in const ['title', 'categoryId', 'status', 'priority', 'progress', 'total', 'rating']) {
        if (jsonEncode(x[k]) != jsonEncode(y[k])) fields.add('$k: ${_show(x[k])} → ${_show(y[k])}');
      }
      if (fields.isNotEmpty) changes.add({'id': id, 'title': cleanTitle(y['title']), 'kind': 'changed', 'fields': fields});
    }
    if (changes.length >= 25) break;
  }
  return changes;
}

double _v348Extra(Object? ledger) {
  double sum(Object? m) => (asMap(m) ?? const {}).values.fold<double>(0, (a, v) => a + math.max(0, jsNum(v)));
  final l = asMap(ledger);
  return sum(l?['v348ActionEvents']) + sum(l?['v348LibraryAdditionBonus']) + sum(l?['v348LibraryCompletionBonus']);
}

/// `v50SnapshotXP` (current website definition).
double snapshotXP(Map<String, dynamic> settingsState, Map<String, dynamic> snap) {
  final s = {...readOnlyView(settingsState), 'sessions': snap['sessions'], 'library': snap['library'], 'xpLedger': snap['xpLedger']};
  return xpMetrics(s).total + _v348Extra(snap['xpLedger']);
}

/// `mfActivity` (v43 + v191): records one Library History entry at the top.
Map<String, dynamic> recordActivity(
  Map<String, dynamic> state, {
  required Map<String, dynamic> before,
  required String id,
  required int timestamp,
  required String action,
  String detail = '',
}) {
  final after = _currentCore(state);
  final changes = diffSnapshot(before, after);
  final xp = math.max(0.0, jsRound(snapshotXP(state, after) - snapshotXP(state, before)));
  final exactIds = <String>[];
  for (final c in changes) {
    final cid = jsStr(c['id']);
    if (cid.isNotEmpty && !exactIds.contains(cid)) exactIds.add(cid);
  }
  String titleSnapshot = '';
  if (exactIds.length == 1) {
    final item = asList(after['library']).map(asMap).where((i) => jsStr(i?['id']) == exactIds.first).firstOrNull;
    titleSnapshot = cleanTitle(item?['title'] ?? (changes.isNotEmpty ? changes.first['title'] : null) ?? detail);
  }
  final afterIds = asList(after['library']).map((i) => jsStr(asMap(i)?['id'])).toSet();
  final deleted = [
    for (final raw in asList(before['library']))
      if (asMap(raw) != null && jsStr(asMap(raw)!['id']).isNotEmpty && !afterIds.contains(jsStr(asMap(raw)!['id']))) _clone(raw),
  ];
  final entry = <String, dynamic>{
    'id': id,
    'timestamp': timestamp,
    'action': action.isEmpty ? 'Change' : action,
    'detail': detail,
    'changes': changes,
    'titleIds': exactIds,
    'titleSnapshot': titleSnapshot,
    'xpEarned': jsOut(xp),
    if (deleted.isNotEmpty) 'deletedItems': deleted,
    if (deleted.isNotEmpty) 'restoreVersion': 191,
  };
  final log = List<dynamic>.of(asList(readOnlyPart(state, 'activityLog')))..insert(0, entry);
  if (log.length > 1000) log.removeRange(1000, log.length);
  state['activityLog'] = log;
  return entry;
}
