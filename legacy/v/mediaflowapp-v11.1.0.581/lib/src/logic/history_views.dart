// History views (read only), ported from the website:
// - Consumption history (v269): title events per log, week groups with
//   summaries (total, active days, average, most active day, peak hour,
//   longest session, categories, most consumed titles), latest consumed.
// - Recently viewed (v340/v344): one entry per title, newest first.
// - Browsing Behavior Insights (v261).
// - Ratings (v261): rated titles with filters and sorts.
// - The History CSV (v271).

import 'dart:convert';

import '../util/js.dart';

/// One title inside a log (`v269EventsFromSession`).
class HistoryEvent {
  HistoryEvent(this.session, this.row, this.item, this.categoryId, this.qty, this.minutes, this.identity, this.date);
  final Map<String, dynamic> session, row;
  final Map<String, dynamic>? item;
  final String categoryId, identity;
  final double qty, minutes;

  /// The local day/time of the event (`v331EventDate`, `v269SessionDate`).
  final DateTime date;

  String get title => cleanTitle(item?['title'] ?? row['title'] ?? session['title'] ?? '');
  String get sessionId => jsStr(session['id']);
}

DateTime? _isoLocal(Object? v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(jsStr(v));
  return m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), 12);
}

/// `v269SessionDate`.
DateTime sessionDate(Map<String, dynamic> s) =>
    _isoLocal(s['date']) ?? DateTime.fromMillisecondsSinceEpoch(jsNum(s['timestamp']).toInt() == 0 ? DateTime.now().millisecondsSinceEpoch : jsNum(s['timestamp']).toInt());

String localDayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `v269WeekStart`: the Monday (noon) of [d]'s week.
DateTime weekStart(DateTime d) {
  final x = DateTime(d.year, d.month, d.day, 12);
  return x.subtract(Duration(days: (x.weekday + 6) % 7));
}

/// `v269ISOWeek`.
int isoWeek(DateTime v) {
  final d = DateTime.utc(v.year, v.month, v.day);
  final day = d.weekday; // 1..7
  final thursday = d.add(Duration(days: 4 - day));
  final yearStart = DateTime.utc(thursday.year, 1, 1);
  return ((thursday.difference(yearStart).inDays + 1) / 7).ceil();
}

class LibraryLookup {
  LibraryLookup(Map<String, dynamic> state) {
    for (final raw in asList(state['library'])) {
      final i = asMap(raw);
      if (i == null) continue;
      final id = jsStr(i['id']);
      if (id.isNotEmpty) byId[id] = i;
      final t = cleanTitle(i['title']).toLowerCase();
      if (t.isNotEmpty) byTitle.putIfAbsent('${jsStr(i['categoryId'])}|$t', () => i);
    }
  }
  final Map<String, Map<String, dynamic>> byId = {}, byTitle = {};

  Map<String, dynamic>? resolve(Map<String, dynamic> session, Map<String, dynamic> row) {
    final id = jsStr(row['libraryId']).isNotEmpty
        ? jsStr(row['libraryId'])
        : (asList(session['titles']).length <= 1 ? jsStr(session['libraryId']) : '');
    final hit = id.isEmpty ? null : byId[id];
    if (hit != null) return hit;
    final t = cleanTitle(row['title'] ?? session['title'] ?? session['libraryTitle'] ?? '').toLowerCase();
    return t.isEmpty ? null : byTitle['${jsStr(session['categoryId'])}|$t'];
  }
}

/// `v269SessionRows`.
List<Map<String, dynamic>> sessionRows(Map<String, dynamic> s, {bool includeCategoryOnly = true}) {
  final src = [
    for (final t in asList(s['titles']))
      if (asMap(t) != null && (jsTruthy(asMap(t)!['title']) || jsTruthy(asMap(t)!['libraryId']))) asMap(t)!,
  ];
  if (src.isNotEmpty) return src;
  final title = cleanTitle(s['title'] ?? s['libraryTitle'] ?? '');
  if (title.isNotEmpty || jsTruthy(s['libraryId'])) {
    return [
      {'title': title.isEmpty ? 'Untitled' : title, 'libraryId': s['libraryId'], 'qty': jsNum(s['actualAmount'])},
    ];
  }
  if (!includeCategoryOnly) return const [];
  return [
    {'title': '', 'libraryId': null, 'qty': jsNum(s['actualAmount']), 'v269CategoryOnly': true},
  ];
}

/// `v269EventsFromSession`.
List<HistoryEvent> sessionEvents(Map<String, dynamic> s, LibraryLookup lib, {bool includeCategoryOnly = true}) {
  final rows = sessionRows(s, includeCategoryOnly: includeCategoryOnly);
  final qtyTotal = rows.fold<double>(0, (a, r) => a + (jsNum(r['qty']) > 0 ? jsNum(r['qty']) : 0));
  final mins = jsNum(s['minutes']) > 0 ? jsNum(s['minutes']) : 0.0;
  return [
    for (final row in rows)
      () {
        final item = lib.resolve(s, row);
        final cat = jsStr(item?['categoryId']).isNotEmpty ? jsStr(item?['categoryId']) : jsStr(s['categoryId']);
        final qty = jsNum(row['qty']) > 0 ? jsNum(row['qty']) : 0.0;
        final secs = jsNumOrNull(row['v369DurationSeconds']);
        final minutes = row['v369DurationSeconds'] != null && secs != null
            ? (secs > 0 ? secs : 0) / 60
            : (qtyTotal > 0 ? (mins * (qty / qtyTotal)).roundToDouble() : (mins / (rows.isEmpty ? 1 : rows.length)).roundToDouble());
        final title = cleanTitle(row['title'] ?? s['title'] ?? '').toLowerCase();
        final identity = item != null ? 'id:${item['id']}' : 'title:$cat:$title';
        final loggedAt = jsNum(row['loggedAt']).toInt();
        final date = loggedAt > 0 ? DateTime.fromMillisecondsSinceEpoch(loggedAt) : sessionDateTime(s);
        return HistoryEvent(s, row, item, cat, qty, minutes, identity, date);
      }(),
  ];
}

/// The log's time on its day (`v331EventDate`: the saved day at the log's clock time).
DateTime sessionDateTime(Map<String, dynamic> s) {
  final ts = jsNum(s['timestamp']).toInt();
  final at = DateTime.fromMillisecondsSinceEpoch(ts == 0 ? DateTime.now().millisecondsSinceEpoch : ts);
  final day = _isoLocal(s['date']);
  return day == null ? at : DateTime(day.year, day.month, day.day, at.hour, at.minute, at.second);
}

// ---- Consumption history (v269) -------------------------------------------------

class WeekGroup {
  WeekGroup(this.start);
  final DateTime start;
  final List<Map<String, dynamic>> sessions = [];
  List<HistoryEvent>? _events;
  DateTime get end => start.add(const Duration(days: 6));
  List<HistoryEvent> events(LibraryLookup lib) => _events ??= [for (final s in sessions) ...sessionEvents(s, lib)];
}

List<WeekGroup> weekGroups(List<Map<String, dynamic>> sessions) {
  final map = <String, WeekGroup>{};
  for (final s in sessions) {
    final start = weekStart(sessionDate(s));
    map.putIfAbsent(localDayKey(start), () => WeekGroup(start)).sessions.add(s);
  }
  final out = map.values.toList()..sort((a, b) => b.start.compareTo(a.start));
  return out;
}

class WeekSummary {
  WeekSummary({
    required this.total,
    required this.activeDays,
    required this.average,
    required this.mostDay,
    required this.mostDayMinutes,
    required this.peakHour,
    required this.longest,
    required this.categories,
    required this.top,
  });
  final double total, average, mostDayMinutes, longest;
  final int activeDays;
  final DateTime? mostDay;
  final int? peakHour;
  final List<({String categoryId, double minutes, int titles, double units})> categories;
  final List<({HistoryEvent event, double units, double minutes})> top;
}

/// `v269WeekMetrics` + `v269WeekCategoryStats` + `v269TopTitles`.
WeekSummary summarizeWeek(WeekGroup g, LibraryLookup lib) {
  double m(Map<String, dynamic> s) => jsNum(s['minutes']) > 0 ? jsNum(s['minutes']) : 0;
  final total = g.sessions.fold<double>(0, (a, s) => a + m(s));
  final days = <String, double>{};
  final hours = <int, double>{};
  for (final s in g.sessions) {
    final key = localDayKey(sessionDate(s));
    days[key] = (days[key] ?? 0) + m(s);
    final ts = jsNum(s['timestamp']).toInt();
    final h = (ts > 0 ? DateTime.fromMillisecondsSinceEpoch(ts) : sessionDate(s)).hour;
    hours[h] = (hours[h] ?? 0) + m(s);
  }
  MapEntry<K, double>? best<K>(Map<K, double> x) => x.entries.isEmpty ? null : x.entries.reduce((a, b) => b.value > a.value ? b : a);
  final mostDay = best(days), peak = best(hours);
  final longest = g.sessions.fold<double>(0, (a, s) => m(s) > a ? m(s) : a);
  final cats = <String, ({double minutes, Set<String> ids, double units})>{};
  final top = <String, ({HistoryEvent event, double units, double minutes})>{};
  for (final ev in g.events(lib)) {
    final c = cats[ev.categoryId] ?? (minutes: 0.0, ids: <String>{}, units: 0.0);
    c.ids.add(ev.identity);
    cats[ev.categoryId] = (minutes: c.minutes + ev.minutes, ids: c.ids, units: c.units + ev.qty);
    final t = top[ev.identity];
    final latest = t == null || sessionDate(ev.session).isAfter(sessionDate(t.event.session)) ? ev : t.event;
    top[ev.identity] = (event: latest, units: (t?.units ?? 0) + ev.qty, minutes: (t?.minutes ?? 0) + ev.minutes);
  }
  final catList = [for (final e in cats.entries) (categoryId: e.key, minutes: e.value.minutes, titles: e.value.ids.length, units: e.value.units)]
    ..sort((a, b) => b.minutes != a.minutes ? b.minutes.compareTo(a.minutes) : b.titles - a.titles);
  final topList = top.values.toList()..sort((a, b) => b.units != a.units ? b.units.compareTo(a.units) : b.minutes.compareTo(a.minutes));
  return WeekSummary(
    total: total,
    activeDays: days.length,
    average: days.isEmpty ? 0 : (total / days.length).roundToDouble(),
    mostDay: mostDay == null ? null : _isoLocal(mostDay.key),
    mostDayMinutes: mostDay?.value ?? 0,
    peakHour: peak?.key,
    longest: longest,
    categories: catList,
    top: topList.take(3).toList(),
  );
}

/// `v269LatestEvents`: the newest title events, one per title.
List<HistoryEvent> latestEvents(List<Map<String, dynamic>> newestFirst, LibraryLookup lib, {int limit = 16}) {
  final seen = <String>{};
  final out = <HistoryEvent>[];
  for (final s in newestFirst) {
    for (final ev in sessionEvents(s, lib)) {
      if (!seen.add(ev.identity)) continue;
      out.add(ev);
      if (out.length >= limit) return out;
    }
  }
  return out;
}

String progressAbbr(String unit) {
  final u = unit.toLowerCase();
  if (u.contains('episode')) return 'Ep.';
  if (u.contains('chapter')) return 'Ch.';
  if (u.contains('issue')) return 'Issue';
  if (u.contains('volume')) return 'Vol.';
  if (u.contains('book')) return 'Book';
  if (RegExp('movie|film').hasMatch(u)) return 'Seen';
  return 'Progress';
}

// ---- Recently viewed (v340/v344) + insights (v261) --------------------------------

class RecentEntry {
  RecentEntry(this.event, this.timestamp);
  final HistoryEvent event;
  final int timestamp;
}

/// `v340RecentRows`: one entry per title (named titles only), newest first.
List<RecentEntry> recentRows(Map<String, dynamic> state, LibraryLookup lib,
    {String category = 'all', int periodDays = 0, String query = '', int? now}) {
  final t = now ?? DateTime.now().millisecondsSinceEpoch;
  final sessions = [for (final s in asList(state['sessions'])) if (asMap(s) != null && asMap(s)!['status'] != 'skipped') asMap(s)!]
    ..sort((a, b) => jsNum(b['timestamp']).compareTo(jsNum(a['timestamp'])));
  final q = query.trim().toLowerCase();
  final seen = <String>{};
  final out = <RecentEntry>[];
  for (final s in sessions) {
    for (final ev in sessionEvents(s, lib, includeCategoryOnly: false)) {
      if (ev.title.isEmpty) continue;
      final loggedAt = jsNum(ev.row['loggedAt']).toInt();
      final ts = loggedAt > 0 ? loggedAt : jsNum(s['timestamp']).toInt();
      if (periodDays > 0 && t - ts > periodDays * 86400000) continue;
      if (category != 'all' && ev.categoryId != category) continue;
      if (q.isNotEmpty && !ev.title.toLowerCase().contains(q)) continue;
      final key = ev.item != null ? 'id:${ev.item!['id']}' : 'title:${ev.categoryId}:${ev.title.toLowerCase()}';
      if (!seen.add(key)) continue;
      out.add(RecentEntry(ev, ts));
    }
  }
  out.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return out;
}

/// `v260TimeBucket`.
String daypart(int ts) {
  final h = DateTime.fromMillisecondsSinceEpoch(ts).hour;
  if (h < 6) return 'Night';
  if (h < 12) return 'Morning';
  if (h < 18) return 'Afternoon';
  return 'Evening';
}

class BrowsingInsights {
  BrowsingInsights(this.peakHour, this.peakCount, this.personality, this.personalityPct, this.mostDay, this.mostDayCount, this.topCategory,
      this.topCategoryPct, this.dayparts);
  final int peakHour, peakCount, personalityPct, mostDayCount, topCategoryPct;
  final String personality, mostDay, topCategory;
  final Map<String, int> dayparts; // percentages
}

/// `v261RecentInsights`.
BrowsingInsights? browsingInsights(List<RecentEntry> rows, String Function(String categoryId) categoryName) {
  if (rows.isEmpty) return null;
  final hours = List<int>.filled(24, 0);
  final days = <String, int>{};
  final parts = {'Morning': 0, 'Afternoon': 0, 'Evening': 0, 'Night': 0};
  final cats = <String, int>{};
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  for (final r in rows) {
    final d = DateTime.fromMillisecondsSinceEpoch(r.timestamp);
    hours[d.hour]++;
    final day = weekdays[d.weekday - 1];
    days[day] = (days[day] ?? 0) + 1;
    final p = daypart(r.timestamp);
    parts[p] = parts[p]! + 1;
    final c = categoryName(r.event.categoryId);
    cats[c] = (cats[c] ?? 0) + 1;
  }
  var peak = 0;
  for (var h = 1; h < 24; h++) {
    if (hours[h] > hours[peak]) peak = h;
  }
  int pct(int n) => (n / (rows.isEmpty ? 1 : rows.length) * 100).round();
  MapEntry<String, int> top(Map<String, int> m) => m.entries.reduce((a, b) => b.value > a.value ? b : a);
  final part = top(parts), day = top(days), cat = top(cats);
  return BrowsingInsights(peak, hours[peak], part.key, pct(part.value), day.key, day.value, cat.key, pct(cat.value),
      {for (final e in parts.entries) e.key: pct(e.value)});
}

// ---- Ratings (v261) -----------------------------------------------------------------

/// `v261RatingsData`.
List<Map<String, dynamic>> ratedTitles(Map<String, dynamic> state,
    {String category = 'all', String year = 'all', String rating = 'all', String query = '', String sort = 'recent'}) {
  final q = query.trim().toLowerCase();
  var rows = [
    for (final raw in asList(state['library']))
      if (asMap(raw) != null && jsNum(asMap(raw)!['rating']) > 0) asMap(raw)!,
  ];
  if (category != 'all') rows = rows.where((i) => jsStr(i['categoryId']) == category).toList();
  if (year != 'all') rows = rows.where((i) => jsStr(i['year']) == year).toList();
  if (rating != 'all') rows = rows.where((i) => jsNum(i['rating']).floor() == int.tryParse(rating)).toList();
  if (q.isNotEmpty) rows = rows.where((i) => cleanTitle(i['title']).toLowerCase().contains(q)).toList();
  int title(Map<String, dynamic> a, Map<String, dynamic> b) => cleanTitle(a['title']).toLowerCase().compareTo(cleanTitle(b['title']).toLowerCase());
  double updated(Map<String, dynamic> i) {
    for (final k in const ['modifiedAt', 'updatedAt', 'completedAt', 'createdAt']) {
      if (jsNum(i[k]) != 0) return jsNum(i[k]);
    }
    return 0;
  }

  if (sort == 'title') {
    rows.sort(title);
  } else if (sort == 'rating') {
    rows.sort((a, b) => jsNum(b['rating']) != jsNum(a['rating']) ? jsNum(b['rating']).compareTo(jsNum(a['rating'])) : title(a, b));
  } else {
    rows.sort((a, b) => updated(b).compareTo(updated(a)));
  }
  return rows;
}

// ---- CSV (v271) -------------------------------------------------------------------

String _csvCell(Object? v) {
  final text = v is String ? v : jsonEncode(v ?? '');
  return RegExp(r'[",\n\r]').hasMatch(text) ? '"${text.replaceAll('"', '""')}"' : text;
}

/// `v271ExportHistorySessions` (oldest first).
String historyCsv(List<Map<String, dynamic>> sessions, String Function(String id) categoryName, String version, double Function(Map<String, dynamic>) xpOf) {
  const header = [
    'id', 'date', 'time', 'timestamp', 'category', 'category_id', 'target', 'actual', 'unit', 'minutes', 'status', 'note', 'xp', 'health_status',
    'source', 'assigned_category_id', 'assigned_target', 'followed_assigned_category', 'session_group_id', 'batch_group_id', 'titles_json',
    'mediaflow_version', 'session_json', 'v369_itemized_units_json', 'v369_duration_seconds', 'v369_itemized',
  ];
  final list = [...sessions]..sort((a, b) => jsNum(a['timestamp']).compareTo(jsNum(b['timestamp'])));
  String two(int n) => n.toString().padLeft(2, '0');
  final rows = [
    for (final s in list)
      () {
        final ts = jsNum(s['timestamp']).toInt();
        final d = DateTime.fromMillisecondsSinceEpoch(ts == 0 ? DateTime.now().millisecondsSinceEpoch : ts);
        Object? or(Object? v) => v ?? '';
        return [
          jsStr(s['id']), jsStr(s['date']), '${two(d.hour)}:${two(d.minute)}:${two(d.second)}', ts == 0 ? '' : ts,
          categoryName(jsStr(s['categoryId'])), jsStr(s['categoryId']), or(s['targetAmount']), or(s['actualAmount']), jsStr(s['unit']),
          or(s['minutes']), jsStr(s['status']), jsStr(s['note']), xpOf(s).round(), jsStr(s['healthStatus']), jsStr(s['source']),
          jsStr(s['assignedCategoryId']), or(s['assignedTargetAmount']), or(s['followedAssignedCategory']), jsStr(s['sessionGroupId']),
          jsStr(s['batchGroupId']), asList(s['titles']), version, s,
          [
            for (final t in asList(s['titles']).map(asMap).whereType<Map<String, dynamic>>())
              for (final u in asList(t['v369Units']).map(asMap).whereType<Map<String, dynamic>>())
                {'title': jsStr(t['title']), 'libraryId': jsStr(t['libraryId']), ...u},
          ],
          or(s['v369DurationSeconds']), s['v369Itemized'] == true,
        ];
      }(),
  ];
  return [header, ...rows].map((r) => r.map(_csvCell).join(',')).join('\n');
}
