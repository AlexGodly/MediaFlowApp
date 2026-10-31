// History actions, ported from the website: edit a log (saveSessionModal +
// v137 start dates), delete logs (deleteSession / v253 bulk delete, undoable,
// recorded in Library History), Undo last entry, restoring deleted titles from
// Library History (v191) and the XP History journal (v348).

import 'dart:convert';
import 'dart:math' as math;

import '../state/models.dart';
import '../util/js.dart';
import 'activity.dart';
import 'leveling.dart';
import 'library_hooks.dart';
import 'log_engine.dart' show reconcileStarts;
import 'recommend.dart';
import 'resume.dart' show clearLoggingDraft;

List<Map<String, dynamic>> _sessions(Map<String, dynamic> state) =>
    asList(state['sessions']).map(asMap).whereType<Map<String, dynamic>>().toList();

/// `App.saveSessionModal` (+ the v137 start-date wrapper). Returns false if the log is gone.
bool editSession(
  Map<String, dynamic> state,
  String id,
  int now, {
  required String categoryId,
  required String date,
  required String status,
  required double targetAmount,
  required double actualAmount,
  required double minutes,
  required String note,
}) {
  final list = asList(state['sessions']);
  final idx = list.indexWhere((s) => jsStr(asMap(s)?['id']) == id);
  if (idx < 0) return false;
  final orig = asMap(list[idx])!;
  final beforeCopy = Map<String, dynamic>.from(orig)
    ..['titles'] = [for (final t in asList(orig['titles'])) Map<String, dynamic>.from(asMap(t) ?? const {})];
  final view = AccountView(state);
  final cat = view.category(categoryId);
  final health = categoryStatus(cat, list, now);
  final updated = Map<String, dynamic>.from(orig)
    ..['categoryId'] = categoryId
    ..['date'] = date.trim().isEmpty ? orig['date'] : date.trim()
    ..['status'] = status
    ..['targetAmount'] = jsOut(math.max(0.0, targetAmount))
    ..['actualAmount'] = jsOut(math.max(0.0, actualAmount))
    ..['minutes'] = jsOut(math.max(0.0, minutes))
    ..['note'] = note.trim();
  updated['unit'] = cat.unit;
  updated['healthStatus'] = health;
  updated['xp'] = jsOut(Leveling(state).consumptionXP(cat, jsNum(updated['actualAmount']), jsNum(updated['minutes']), health));
  final mutable = List<dynamic>.of(list);
  mutable[idx] = updated;
  state['sessions'] = mutable;
  // v137: the edited day may be earlier evidence of when a title was started.
  final tracker = LibraryTracker(state);
  final before = jsonEncode(state['library']);
  reconcileStarts(state, [beforeCopy, updated], now);
  if (jsonEncode(state['library']) != before) {
    var n = 0;
    tracker.save(state, Leveling(state), now, () => mediaFlowUid(now + n++));
  }
  annotateStreakXP(state, Leveling(state));
  return true;
}

/// `App.deleteSession` / `v253ConfirmHistoryDelete`: one undoable change with a
/// Library History entry. Returns how many logs were removed.
int deleteSessions(Map<String, dynamic> state, Set<String> ids, int now) {
  final list = _sessions(state);
  final doomed = list.where((s) => ids.contains(jsStr(s['id']))).toList();
  if (doomed.isEmpty) return 0;
  final before = coreSnapshot(state);
  state['sessions'] = [for (final s in asList(state['sessions'])) if (!ids.contains(jsStr(asMap(s)?['id']))) s];
  final count = doomed.length;
  final detail = ids.length == 1 && count == 1
      ? AccountView(state).category(jsStr(doomed.first['categoryId'])).name
      : '$count ${count == 1 ? 'entry' : 'entries'}';
  annotateStreakXP(state, Leveling(state));
  recordActivity(state, before: before, id: mediaFlowUid(now), timestamp: now, action: 'Delete history', detail: detail);
  return count;
}

/// `App.undoLastEntry`: removes the newest log and gives it back as the current task.
Map<String, dynamic>? undoLastEntry(Map<String, dynamic> state, int now) {
  final list = _sessions(state);
  if (list.isEmpty) return null;
  final latest = list.reduce((a, b) => jsNum(a['timestamp']) > jsNum(b['timestamp']) ? a : b);
  state['sessions'] = [for (final s in asList(state['sessions'])) if (!identical(asMap(s), latest) && jsStr(asMap(s)?['id']) != jsStr(latest['id'])) s];
  final r = Recommender(state, now: now);
  final cat = r.getCategory(jsStr(latest['categoryId']));
  final amount = r.suggestedAmount(cat);
  final target = jsNum(latest['targetAmount']);
  state['currentTask'] = {
    'id': mediaFlowUid(now),
    'categoryId': cat['id'],
    'low': amount.low,
    'high': amount.high,
    'targetMid': target != 0 ? latest['targetAmount'] : cat['target'],
    'unit': cat['unit'],
    'createdAt': now,
    'reasons': ['Restored from undo'],
  };
  state['sessionActive'] = true;
  clearLoggingDraft(state, now);
  annotateStreakXP(state, Leveling(state));
  return latest;
}

/// `v191RestoreDeletedTitle` / `v191RestoreDeletedGroup`. Returns restored titles.
List<String> restoreDeleted(Map<String, dynamic> state, String activityId, int now, {String? itemId}) {
  final entry = asList(state['activityLog']).map(asMap).where((e) => jsStr(e?['id']) == activityId).firstOrNull;
  if (entry == null) return const [];
  // The newest deletion of each title is the one that can restore it.
  final latest = <String, String>{};
  for (final e in asList(state['activityLog'])) {
    for (final item in asList(asMap(e)?['deletedItems'])) {
      final id = jsStr(asMap(item)?['id']);
      if (id.isNotEmpty) latest.putIfAbsent(id, () => jsStr(asMap(e)?['id']));
    }
  }
  final library = asList(state['library']);
  bool exists(String id) => library.any((i) => jsStr(asMap(i)?['id']) == id);
  final snaps = [
    for (final raw in asList(entry['deletedItems']))
      if (asMap(raw) != null &&
          (itemId == null ? latest[jsStr(asMap(raw)!['id'])] == activityId : jsStr(asMap(raw)!['id']) == itemId) &&
          !exists(jsStr(asMap(raw)!['id'])))
        Map<String, dynamic>.from(asMap(raw)!),
  ];
  if (snaps.isEmpty) return const [];
  final before = coreSnapshot(state);
  final cats = asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().toList();
  final restored = <String>[];
  final lib = List<dynamic>.of(library);
  final timeline = List<dynamic>.of(asList(state['completionTimeline']));
  for (final item in snaps) {
    if (!cats.any((c) => jsStr(c['id']) == jsStr(item['categoryId']))) {
      final fallback = cats.where((c) => c['enabled'] != false).firstOrNull ?? cats.firstOrNull;
      if (fallback != null) item['categoryId'] = fallback['id'];
    }
    lib.add(item);
    if (item['status'] == 'completed' && !timeline.any((x) => jsStr(asMap(x)?['libraryId']) == jsStr(item['id']))) {
      timeline.add({
        'libraryId': item['id'],
        'title': cleanTitle(item['title']),
        'categoryId': item['categoryId'],
        'completedAt': jsTruthy(item['completedAt']) ? item['completedAt'] : now,
      });
    }
    restored.add(cleanTitle(item['title']));
  }
  state['library'] = lib;
  state['completionTimeline'] = timeline;
  final single = itemId != null;
  recordActivity(state,
      before: before,
      id: mediaFlowUid(now),
      timestamp: now,
      action: single ? 'Restore title' : 'Restore deleted titles',
      detail: single ? (restored.first.isEmpty ? 'Deleted title' : restored.first) : '${restored.length} titles');
  // persistLibrary after a restore.
  return restored;
}

// ---- XP History (v348) -------------------------------------------------------------

const Map<String, String> kXpSourceLabels = {
  'collectionAddTitleXP': 'Collection · added titles',
  'collectionReorderTitleXP': 'Collection · reordered titles',
  'orderAddTitleXP': 'Personal Order · added titles',
  'orderAddCollectionXP': 'Personal Order · assigned Collection',
  'orderReorderTitleXP': 'Personal Order · reordered titles',
  'orderReorderCollectionXP': 'Personal Order · reordered Collections',
  'batchLogXP': 'Batch Log bonus',
  'libraryAdditions': 'Library · new title',
  'libraryEdits': 'Library · edited title',
  'manualCovers': 'Library · manual cover',
  'ratings': 'Rating reward',
  'v334StartedTitles': 'First title start',
  'v335FirstEpisodeRewards': 'First episode',
  'v334CollectionCreates': 'Collection created',
  'v334CollectionEdits': 'Collection edited',
  'logCompletions': 'Log completion bonus',
};

class XpEntry {
  XpEntry({required this.id, required this.kind, required this.source, required this.xp, this.title = '', this.details = '',
      this.timestamp = 0, this.baseXP, this.multiplier, this.streak, this.legacy = false});
  final String id, kind, source, title, details;
  final double xp;
  final double timestamp;
  final double? baseXP, multiplier, streak;
  final bool legacy;
}

/// `v348HistoryEntries`.
List<XpEntry> xpHistory(Map<String, dynamic> state) {
  final l = asMap(state['xpLedger']) ?? const <String, dynamic>{};
  final meta = asMap(l['v348EventMeta']) ?? const <String, dynamic>{};
  final names = {
    for (final i in asList(state['library']).map(asMap).whereType<Map<String, dynamic>>())
      if (jsTruthy(i['id'])) jsStr(i['id']): jsStr(i['title']),
  };
  final seen = <String, double>{};
  final out = <XpEntry>[];
  for (final e in meta.entries) {
    final row = asMap(e.value);
    if (row == null || jsNumOrNull(row['xp']) == null) continue;
    final kind = jsStr(row['kind']).isEmpty ? 'other' : jsStr(row['kind']);
    final subject = jsStr(row['subjectId']);
    final xp = math.max(0.0, jsNum(row['xp']));
    if (subject.isNotEmpty) seen['$kind\u0000$subject'] = (seen['$kind\u0000$subject'] ?? 0) + xp;
    out.add(XpEntry(
      id: 'event:${e.key}',
      kind: kind,
      source: jsStr(row['source']).isEmpty ? (kXpSourceLabels[kind] ?? kind) : jsStr(row['source']),
      title: names[subject] ?? '',
      timestamp: jsNum(row['timestamp']),
      baseXP: math.max(0, jsNum(row['baseXP'])),
      multiplier: jsNum(row['multiplier']) == 0 ? 1 : jsNum(row['multiplier']),
      xp: xp,
      details: jsStr(row['details']),
    ));
  }
  for (final e in (asMap(l['v348ActionEvents']) ?? const <String, dynamic>{}).entries) {
    if (meta.containsKey(e.key)) continue;
    final kind = e.key.split(':').first;
    out.add(XpEntry(id: 'action:${e.key}', kind: kind, source: kXpSourceLabels[kind] ?? kind, xp: jsNum(e.value), legacy: true));
  }
  for (final s in _sessions(state)) {
    if (s['status'] == 'skipped') continue;
    final xp = math.max(0.0, jsRound(jsNum(s['xpWithStreak'] ?? s['xp'])));
    if (xp == 0) continue;
    final titles = asList(s['titles'])
        .map((t) => jsStr(asMap(t)?['title']).isNotEmpty ? jsStr(asMap(t)?['title']) : (names[jsStr(asMap(t)?['libraryId'])] ?? ''))
        .where((t) => t.isNotEmpty)
        .take(3)
        .join(', ');
    out.add(XpEntry(
      id: 'log:${s['id'] ?? s['timestamp']}',
      kind: 'consumption',
      source: s['source'] == 'batch' ? 'Batch Log · consumption' : 'Consumption log',
      timestamp: jsNum(s['timestamp']),
      title: titles,
      details: jsStr(s['note']),
      xp: xp,
      baseXP: jsNum(s['streakBaseXP'] ?? s['xp']),
      multiplier: jsNum(s['streakMultiplier']) == 0 ? 1 : jsNum(s['streakMultiplier']),
      streak: jsNum(s['streakAtLog']),
    ));
  }
  for (final e in (asMap(l['v334ActiveTimeDays']) ?? const <String, dynamic>{}).entries) {
    final row = asMap(e.value);
    final xp = math.max(0.0, jsNum(row?['xp']));
    if (xp == 0) continue;
    final mult = jsNum(row?['multiplier']) == 0 ? 1.0 : jsNum(row?['multiplier']);
    final minutes = (jsNum(row?['ms']) / 60000).round();
    out.add(XpEntry(
      id: 'time:${e.key}',
      kind: 'activeTime',
      source: 'Active app time',
      timestamp: isIsoDay(e.key) ? DateTime.parse('${e.key}T12:00:00').millisecondsSinceEpoch.toDouble() : 0,
      details: '${minutes ~/ 60 > 0 ? '${minutes ~/ 60}h ' : ''}${minutes % 60}m active',
      xp: xp,
      baseXP: xp / mult,
      multiplier: mult,
    ));
  }
  const legacy = [
    ('libraryEdits', 'Library · edited title'), ('manualCovers', 'Library · manual cover'), ('ratings', 'Rating reward'),
    ('v334StartedTitles', 'First title start'), ('v335FirstEpisodeRewards', 'First episode'),
    ('v334CollectionCreates', 'Collection created'), ('v334CollectionEdits', 'Collection edited'),
    ('logCompletions', 'Log completion bonus'), ('libraryAdditions', 'Library · added title'),
  ];
  for (final (key, label) in legacy) {
    for (final e in (asMap(l[key]) ?? const <String, dynamic>{}).entries) {
      final xp = math.max(0.0, jsNum(e.value));
      final residual = math.max(0.0, xp - (seen['$key\u0000${e.key}'] ?? 0));
      if (residual == 0) continue;
      out.add(XpEntry(id: 'legacy:$key:${e.key}', kind: key, source: label, title: names[e.key] ?? '', xp: residual, legacy: true));
    }
  }
  out.sort((a, b) {
    final t = b.timestamp.compareTo(a.timestamp);
    return t != 0 ? t : a.id.compareTo(b.id);
  });
  return out;
}

/// `App.v348ExportXPHistory('csv')`.
String xpHistoryCsv(List<XpEntry> rows) {
  String q(Object? x) => '"${'${x ?? ''}'.replaceAll('"', '""')}"';
  String n(double? v) => v == null ? '' : (v == v.truncateToDouble() ? v.toInt().toString() : v.toString());
  final header = ['timestamp', 'source', 'kind', 'title', 'base_xp', 'streak_multiplier', 'streak_days', 'xp', 'details', 'legacy'];
  final lines = [
    header.join(','),
    for (final x in rows)
      [
        x.timestamp > 0 ? DateTime.fromMillisecondsSinceEpoch(x.timestamp.toInt(), isUtc: true).toIso8601String() : '',
        x.source,
        x.kind,
        x.title,
        n(x.baseXP),
        n(x.multiplier),
        n(x.streak),
        n(x.xp),
        x.details,
        x.legacy,
      ].map(q).join(','),
  ];
  return '﻿${lines.join('\r\n')}';
}
