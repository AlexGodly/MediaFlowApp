// The website's shared "resume" record (v285): `state.resumeStateV285.logging`
// holds the open logging form — task, draft and entry draft — so a log started
// on one device continues on another. The newer section wins; two per-unit
// drafts of the same session are merged unit by unit (v369).

import 'dart:convert';
import 'dart:math' as math;

import '../util/js.dart';

const String kResumeFormat = 'MediaFlow_Resume_v285';

T _clone<T>(T v) => jsonDecode(jsonEncode(v)) as T;

int _ms(Object? v) {
  final n = jsNum(v);
  return n.isFinite && n > 0 ? n.toInt() : 0;
}

/// `v285NormalizeLoggingUi`.
Map<String, dynamic> normalizeLoggingUi(Object? raw) {
  final x = asMap(raw) ?? const {};
  final page = jsNum(x['page']);
  return {
    'libraryOpen': x['libraryOpen'] == true,
    'page': page.isFinite && page > 0 ? page.floor() : 0,
    'categories': x['categories'] is List ? asList(x['categories']).map(jsStr).toList() : <String>[],
    'status': jsTruthy(x['status']) ? jsStr(x['status']) : 'all',
    'priority': jsTruthy(x['priority']) ? jsStr(x['priority']) : 'all',
    'sort': jsStr(x['sort']),
    'sortBase': jsStr(x['sortBase']),
    'sortDir': jsStr(x['sortDir']),
  };
}

/// `v285NormalizeLogging`.
Map<String, dynamic> normalizeLogging(Object? raw) {
  final x = asMap(raw) ?? const {};
  return {
    'active': x['active'] == true,
    'currentTask': asMap(x['currentTask']) != null ? _clone(asMap(x['currentTask'])) : null,
    'logDraft': asMap(x['logDraft']) != null ? _clone(asMap(x['logDraft'])) : <String, dynamic>{},
    'entryDraft': asMap(x['entryDraft']) != null ? _clone(asMap(x['entryDraft'])) : <String, dynamic>{},
    'ui': normalizeLoggingUi(x['ui']),
    'modifiedAt': _ms(x['modifiedAt']),
  };
}

Map<String, dynamic> _normalizeDashboard(Object? raw) {
  final x = asMap(raw) ?? const {};
  return {
    'stopwatchCollapsed': x['stopwatchCollapsed'] == true,
    'runtimeCalculatorCollapsed': x['runtimeCalculatorCollapsed'] == true,
    'modifiedAt': _ms(x['modifiedAt']),
  };
}

/// The logging section stored in the account (normalized), or null if none.
Map<String, dynamic>? readLogging(Map<String, dynamic> state) {
  final resume = asMap(state['resumeStateV285']);
  if (resume == null || asMap(resume['logging']) == null) return null;
  return normalizeLogging(resume['logging']);
}

/// Writes [logging] as the account's logging section.
void _store(Map<String, dynamic> state, Map<String, dynamic> logging) {
  final old = asMap(state['resumeStateV285']) ?? const <String, dynamic>{};
  final dashboard = _normalizeDashboard(old['dashboard']);
  state['resumeStateV285'] = {
    ...old,
    'format': kResumeFormat,
    'dashboard': dashboard,
    'logging': logging,
    'modifiedAt': math.max(_ms(dashboard['modifiedAt']), _ms(logging['modifiedAt'])),
  };
}

/// A logging section for an open form.
Map<String, dynamic> activeLogging({
  required Map<String, dynamic> task,
  required Map<String, dynamic> logDraft,
  required Map<String, dynamic> entryDraft,
  required int modifiedAt,
  Object? ui,
}) =>
    {
      'active': true,
      'currentTask': _clone(task),
      'logDraft': _clone(logDraft),
      'entryDraft': _clone(entryDraft),
      'ui': normalizeLoggingUi(ui),
      'modifiedAt': modifiedAt,
    };

/// A closed form (the website writes this when logging ends).
Map<String, dynamic> inactiveLogging(int modifiedAt) => {
      'active': false,
      'currentTask': null,
      'logDraft': <String, dynamic>{},
      'entryDraft': <String, dynamic>{},
      'ui': normalizeLoggingUi(const {}),
      'modifiedAt': modifiedAt,
    };

/// Applies a draft change made on this device: the newer section wins, and two
/// per-unit drafts of the same session keep every unit (v369MergeLogging).
/// Returns true when the account changed.
bool applyLoggingSection(Map<String, dynamic> state, Map<String, dynamic> incoming) {
  final mine = normalizeLogging(incoming);
  final current = readLogging(state);
  if (current == null) {
    _store(state, mine);
    return true;
  }
  final merged = mergeLogging(current, mine);
  if (merged != null) {
    final normalized = normalizeLogging(merged);
    if (jsonEncode(normalized) == jsonEncode(current)) return false;
    _store(state, normalized);
    return true;
  }
  if (_ms(mine['modifiedAt']) <= _ms(current['modifiedAt'])) return false;
  _store(state, mine);
  return true;
}

/// After a log is saved the form closes. A newer, different draft saved
/// elsewhere in the meantime is kept.
void clearLoggingDraft(Map<String, dynamic> state, int now, {String submittedCommitId = '', int? submittedAt}) {
  final current = readLogging(state);
  if (current != null && current['active'] == true && _ms(current['modifiedAt']) > (submittedAt ?? now)) {
    final commit = jsStr(asMap(current['logDraft'])?['v369CommitId']);
    if (commit.isNotEmpty && commit != submittedCommitId) return;
  }
  _store(state, inactiveLogging(math.max(now, current == null ? 0 : _ms(current['modifiedAt']))));
}

/// `v369LatestTombstones`.
Map<String, dynamic> latestTombstones(List<Object?> sets) {
  final out = <String, dynamic>{};
  for (final set in sets) {
    for (final e in (asMap(set) ?? const {}).entries) {
      out[e.key] = jsOut(math.max(jsNum(out[e.key]), jsNum(e.value)));
    }
  }
  return out;
}

int _stamp(Map<String, dynamic>? x) {
  final u = jsNum(x?['v369UpdatedAt']);
  return (u != 0 && u.isFinite ? u : jsNum(x?['loggedAt'])).toInt();
}

/// `v369MergeUnits`.
List<Map<String, dynamic>> mergeUnits(List<dynamic> left, List<dynamic> right, Map<String, dynamic> deletions) {
  final units = <String, Map<String, dynamic>>{};
  for (final raw in [...left, ...right]) {
    final item = asMap(raw);
    if (item == null || !jsTruthy(item['id'])) continue;
    final key = jsStr(item['id']);
    final old = units[key];
    if (old == null || _stamp(item) >= _stamp(old)) units[key] = _clone(item);
  }
  final out = units.values.where((u) => jsNum(deletions[jsStr(u['id'])]) < _stamp(u)).toList();
  out.sort((a, b) {
    final d = jsNum(a['loggedAt']) - jsNum(b['loggedAt']);
    if (d != 0) return d < 0 ? -1 : 1;
    return jsStr(a['id']).compareTo(jsStr(b['id']));
  });
  return out;
}

double _unitSeconds(Map<String, dynamic> u) {
  final d = jsNumFromKey(u, 'durationSeconds');
  if (d != null) return math.max(0, d.floorToDouble());
  return math.max(0, jsRound(jsNum(u['minutes']) * 60));
}

/// `v369MergeLogging`: null unless both sides are open per-unit drafts.
Map<String, dynamic>? mergeLogging(Map<String, dynamic> left, Map<String, dynamic> right) {
  final ad = asMap(left['logDraft']) ?? const {}, bd = asMap(right['logDraft']) ?? const {};
  if (left['active'] != true || right['active'] != true || ad['v369Interface'] != 'itemized' || bd['v369Interface'] != 'itemized') {
    return null;
  }
  final ida = jsStr(ad['v369CommitId']), idb = jsStr(bd['v369CommitId']);
  if (ida.isEmpty || idb.isEmpty) return null;
  final newer = _ms(left['modifiedAt']) >= _ms(right['modifiedAt']) ? left : right;
  final older = identical(newer, left) ? right : left;
  final chosen = _clone(newer);
  final draft = asMap(chosen['logDraft']) ?? <String, dynamic>{};
  chosen['logDraft'] = draft;
  if (ida != idb) {
    final olderDraft = asMap(older['logDraft']) ?? const {};
    final conflicts = [...asList(asMap(newer['logDraft'])?['v369Conflicts']), ...asList(olderDraft['v369Conflicts'])];
    final existing = conflicts.map((x) => jsStr(asMap(x)?['commitId'])).toSet();
    if (!existing.contains(jsStr(olderDraft['v369CommitId']))) {
      conflicts.add({
        'commitId': jsStr(olderDraft['v369CommitId']),
        'capturedAt': _ms(older['modifiedAt']),
        'draft': _clone(olderDraft),
        'currentTask': older['currentTask'],
      });
    }
    draft['v369Conflicts'] = conflicts.length > 12 ? conflicts.sublist(conflicts.length - 12) : conflicts;
    return chosen;
  }
  final deletedTitles = latestTombstones([ad['v369DeletedTitles'], bd['v369DeletedTitles']]);
  final byId = <String, Map<String, dynamic>>{};
  for (final raw in [...asList(ad['entries']), ...asList(bd['entries'])]) {
    final entry = asMap(raw);
    final id = jsStr(entry?['libraryId']);
    if (entry == null || id.isEmpty) continue;
    final old = byId[id];
    if (old == null) {
      byId[id] = _clone(entry);
      continue;
    }
    final later = _stamp(old) >= _stamp(entry) ? old : entry;
    final updated = _clone(later);
    final tomb = latestTombstones([old['v369DeletedUnits'], entry['v369DeletedUnits']]);
    updated['v369DeletedUnits'] = tomb;
    updated['v369Units'] = mergeUnits(asList(old['v369Units']), asList(entry['v369Units']), tomb);
    updated['qty'] = asList(updated['v369Units']).length;
    updated['v369UpdatedAt'] = jsOut(math.max(jsNum(old['v369UpdatedAt']), jsNum(entry['v369UpdatedAt'])));
    byId[id] = updated;
  }
  draft['v369DeletedTitles'] = deletedTitles;
  final entries = byId.values.where((e) => jsNum(deletedTitles[jsStr(e['libraryId'])]) < _stamp(e)).toList();
  draft['entries'] = entries;
  final seconds = entries.fold<double>(
      0, (sum, e) => sum + asList(e['v369Units']).map(asMap).whereType<Map<String, dynamic>>().fold<double>(0, (n, u) => n + _unitSeconds(u)));
  draft['v369DurationSeconds'] = jsOut(seconds);
  draft['minutes'] = jsOut(seconds / 60);
  draft['amount'] = entries.fold<int>(0, (sum, e) => sum + asList(e['v369Units']).length);
  return chosen;
}
