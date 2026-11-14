// Logs keep the time you actually consumed (website v566, 418-v566-log-times.js).
//
// A log kept open for days used to be dated when it was saved, so the days in
// between looked empty to streaks, History and Statistics. Every session a
// log writes is now dated by when you consumed:
//   settings.mf566LogTime  'unit'  (default) each unit at the time it was logged
//                                  (itemized: each unit's own time; other
//                                  methods: the time the title was added)
//                          'added' each title at the time it was added to the log
// When the times fall on more than one day the session is split, one per day.
// Amount, minutes and XP are divided between the days (totals unchanged); the
// latest day keeps the session's id and its recommendation outcome, earlier
// days are "logged". Each part carries mf566Split {group, part, of}. Days are
// UTC ISO dates, like everywhere else in MediaFlow.
//
// The app gives earlier days fixed ids ('<session id>_d<part>') so a replayed
// log always makes the same sessions.

import 'dart:math' as math;

import '../util/js.dart';
import 'log_draft.dart' show LogDraftEditor;

const List<String> kLogTimeModes = ['unit', 'added'];

String logTimeMode(Map<String, dynamic>? settings) {
  final v = jsStr(settings?['mf566LogTime']);
  return kLogTimeModes.contains(v) ? v : 'unit';
}

String _titleKey(Map<String, dynamic> t) =>
    jsTruthy(t['libraryId']) ? 'id:${jsStr(t['libraryId'])}' : 't:${cleanTitle(t['title']).toLowerCase()}';

/// When each title was added to the log (from the draft, before saving).
Map<String, int> addedTimes(Map<String, dynamic>? logDraft) {
  final out = <String, int>{};
  for (final raw in asList(logDraft?['entries'])) {
    final e = asMap(raw);
    if (e == null) continue;
    out[_titleKey(e)] = _stamp(e['loggedAt'], 0);
  }
  return out;
}

int _stamp(Object? v, int now) {
  final n = jsNum(v);
  // Like the website: from 2000 up to five minutes ahead of now (or any when now is 0).
  if (!n.isFinite || n < 946684800000) return 0;
  if (now > 0 && n > now + 300000) return 0;
  return n.toInt();
}

double _round(double v, [int d = 4]) {
  final f = math.pow(10, d).toDouble();
  return (v * f).roundToDouble() / f;
}

typedef _Point = ({int ti, int ui, int time, double qty, double seconds});

/// The sessions that replace [session] (one per day, oldest first).
List<Map<String, dynamic>> redateSession(Map<String, dynamic> session, Map<String, int> added, String mode, int now) {
  final titles = [for (final t in asList(session['titles'])) asMap(t)].whereType<Map<String, dynamic>>().toList();
  if (session['status'] == 'skipped' || titles.isEmpty) return [session];
  final fallback = _stamp(session['timestamp'], now) > 0 ? _stamp(session['timestamp'], now) : now;
  final points = <_Point>[];
  for (var ti = 0; ti < titles.length; ti++) {
    final t = titles[ti];
    final a = added[_titleKey(t)] ?? 0;
    final titleAt = a > 0 ? a : (_stamp(t['loggedAt'], now) > 0 ? _stamp(t['loggedAt'], now) : fallback);
    final units = [for (final u in asList(t['v369Units'])) asMap(u)].whereType<Map<String, dynamic>>().toList();
    final qty = math.max(0.0, jsNum(t['qty']));
    if (units.isNotEmpty) {
      for (var ui = 0; ui < units.length; ui++) {
        final u = units[ui];
        final own = _stamp(u['loggedAt'], now);
        points.add((ti: ti, ui: ui, time: mode == 'added' ? titleAt : (own > 0 ? own : titleAt), qty: qty / units.length, seconds: LogDraftEditor.unitSeconds(u)));
      }
    } else {
      final own = _stamp(t['loggedAt'], now);
      points.add((ti: ti, ui: -1, time: mode == 'added' ? titleAt : (own > 0 ? own : titleAt), qty: qty, seconds: 0));
    }
  }
  final days = <String, List<_Point>>{};
  for (final p in points) {
    days.putIfAbsent(isoDateUtc(p.time), () => []).add(p);
  }
  if (days.isEmpty) return [session];
  final keys = days.keys.toList()..sort();
  if (keys.length == 1) {
    final key = keys.first;
    final last = days[key]!.map((p) => p.time).reduce(math.max);
    // Website v567: a log that's all on its own save day keeps its save time.
    if (jsStr(session['date']) != key) {
      session['mf566SavedAt'] = jsOut(jsNum(session['timestamp']) > 0 ? jsNum(session['timestamp']) : now.toDouble());
      session['date'] = key;
      session['timestamp'] = last;
    }
    return [session];
  }
  final totalQty = points.fold<double>(0, (n, p) => n + p.qty);
  final itemized = points.any((p) => p.ui >= 0 && p.seconds > 0);
  final totalSeconds = points.fold<double>(0, (n, p) => n + p.seconds);
  final savedAt = jsNum(session['timestamp']) > 0 ? jsNum(session['timestamp']) : now.toDouble();
  final xpTotal = jsNum(session['xp']).roundToDouble();
  final amountTotal = jsNum(session['actualAmount']), minutesTotal = jsNum(session['minutes']);
  var xpLeft = xpTotal, amountLeft = amountTotal, minutesLeft = minutesTotal;
  final id = jsStr(session['id']);
  final out = <Map<String, dynamic>>[];
  for (var index = 0; index < keys.length; index++) {
    final key = keys[index], pts = days[key]!, isLast = index == keys.length - 1;
    final share = totalQty > 0 ? pts.fold<double>(0, (n, p) => n + p.qty) / totalQty : pts.length / points.length;
    final byTitle = <int, List<_Point>>{};
    for (final p in pts) {
      byTitle.putIfAbsent(p.ti, () => []).add(p);
    }
    final rows = <Map<String, dynamic>>[];
    for (final ti in byTitle.keys.toList()..sort()) {
      final list = byTitle[ti]!, t = titles[ti];
      final row = <String, dynamic>{...t};
      final units = asList(t['v369Units']);
      if (units.isNotEmpty) {
        row['v369Units'] = [for (final p in list) if (p.ui >= 0) {...asMap(units[p.ui])!}];
        row['v369DurationSeconds'] = jsOut(list.fold<double>(0, (n, p) => n + p.seconds));
      }
      row['qty'] = jsOut(_round(list.fold<double>(0, (n, p) => n + p.qty)));
      row['loggedAt'] = list.map((p) => p.time).reduce(math.min);
      rows.add(row);
    }
    final seconds = pts.fold<double>(0, (n, p) => n + p.seconds);
    final xp = isLast ? xpLeft : (xpTotal * share).roundToDouble();
    final amount = isLast ? amountLeft : _round(amountTotal * share);
    final minutes = isLast ? minutesLeft : (itemized && totalSeconds > 0 ? seconds / 60 : _round(minutesTotal * share));
    xpLeft -= xp;
    amountLeft -= amount;
    minutesLeft -= minutes;
    final part = <String, dynamic>{
      ...session,
      'id': isLast ? id : '${id}_d${index + 1}',
      'date': key,
      'timestamp': pts.map((p) => p.time).reduce(math.max),
      'titles': rows,
      'xp': jsOut(xp),
      'actualAmount': jsOut(_round(amount)),
      'minutes': jsOut(_round(math.max(0.0, minutes))),
      'status': isLast ? session['status'] : 'logged',
      'mf566SavedAt': jsOut(savedAt),
      'mf566Split': {'group': jsStr(session['sessionGroupId']).isNotEmpty ? jsStr(session['sessionGroupId']) : id, 'part': index + 1, 'of': keys.length},
    };
    if (!isLast) part['targetAmount'] = part['actualAmount'];
    if (session.containsKey('v369DurationSeconds')) {
      part['v369DurationSeconds'] = jsOut((itemized ? seconds : jsNum(session['v369DurationSeconds']) * share).roundToDouble());
    }
    out.add(part);
  }
  return out;
}

/// Re-dates (and splits by day) [added] sessions inside [sessions], in place.
/// Returns the sessions that now stand for [added], in order.
List<Map<String, dynamic>> redateLogSessions(
    List<dynamic> sessions, List<Map<String, dynamic>> added, Map<String, int> addedAt, String mode, int now) {
  final result = <Map<String, dynamic>>[];
  for (final s in added) {
    final parts = redateSession(s, addedAt, mode, now);
    result.addAll(parts);
    if (parts.length > 1) {
      final at = sessions.indexWhere((x) => identical(x, s));
      if (at >= 0) sessions.replaceRange(at, at + 1, parts);
    }
  }
  return result;
}
