// Statistics, computed the way the website's Statistics page computes them
// (renderStatsV14 + v129 classic cards + v44 ratings + v119/v136 heatmap and
// recap + v150/v334/v348/mf544 XP totals + v186 scopes and visibility).

import 'dart:math' as math;

import '../state/models.dart';
import '../util/js.dart';
import 'extras.dart' show visiblePanelCategories;
import 'leveling.dart';
import 'library_hooks.dart' show isCompletedItem;
import 'recommend.dart' show stableSort;

/// Website component keys and labels (V186_STATS_COMPONENT_LABELS + v334 activeTime).
const List<(String, String)> kStatsComponents = [
  ('profile', 'Profile header'),
  ('achievements', 'Lifetime achievements'),
  ('leveling', 'Leveling'),
  ('activeTime', 'Active time spent in MediaFlow'),
  ('today', 'Today summary'),
  ('week', 'This week summary'),
  ('month', 'This month summary'),
  ('lifetime', 'Lifetime summary'),
  ('units', 'Units summary'),
  ('streak', 'Streak summary'),
  ('sevenDayMinutes', '7-day minutes chart'),
  ('sevenDaySessions', '7-day sessions chart'),
  ('thirtyDayMinutes', '30-day daily minutes'),
  ('ninetyDayActivity', '90-day activity'),
  ('categoryMix', '30-day category mix'),
  ('mediaTypeMix', 'Media type mix'),
  ('libraryStatus', 'Library status'),
  ('priorityDistribution', 'Priority distribution'),
  ('repeatConsumption', 'Repeat consumption'),
  ('libraryHealth', 'Library health'),
  ('advancedMetrics', 'Advanced metrics'),
  ('heatmap', 'Consumption heatmap'),
  ('monthlyRecap', 'Monthly recap'),
  ('categoryBalance', 'Category balance'),
  ('saturation', 'Recent saturation'),
  ('records', 'Records'),
  ('ratings', 'Ratings'),
  ('completionTimeline', 'Title completion timeline'),
];

/// `v186NormalizeStatsComponents`: is a component shown?
bool statsComponentVisible(Map<String, dynamic> state, String key) {
  final values = asMap(asMap(asMap(asMap(state['settings'])?['v186ControlCenter'])?['statsComponents'])?['values']);
  return values?[key] != false;
}

/// `v186ScopeCategories(key)`.
List<Map<String, dynamic>> scopeCategories(Map<String, dynamic> state, String key) {
  final cats = asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().toList();
  final scope = asMap(asMap(asMap(state['settings'])?['v186ControlCenter'])?[key]);
  if (scope?['mode'] != 'custom') return cats.where((c) => c['enabled'] != false).toList();
  final valid = cats.map((c) => jsStr(c['id'])).where((x) => x.isNotEmpty).toSet();
  final ids = scope!['categoryIds'] is List
      ? asList(scope['categoryIds']).map(jsStr).where(valid.contains).toSet()
      : cats.where((c) => c['enabled'] != false).map((c) => jsStr(c['id'])).toSet();
  return cats.where((c) => ids.contains(jsStr(c['id']))).toList();
}

// ---- XP and level ----------------------------------------------------------------

double _sumMap(Object? m) => (asMap(m) ?? const {}).values.fold<double>(0, (a, v) => a + math.max(0, jsNum(v)));

class XpMetrics {
  XpMetrics(this.m);
  final Map<String, double> m;
  double get total => m['total']!;
  double operator [](String k) => m[k] ?? 0;
}

/// `v150ComputeStateMetrics` with the v165, v334/v335, v348 and mf544 additions.
XpMetrics xpMetrics(Map<String, dynamic> state) {
  final sessions = asList(state['sessions']);
  final library = asList(state['library']).map(asMap).whereType<Map<String, dynamic>>().toList();
  final ledger = asMap(state['xpLedger']) ?? const {};
  final l = Leveling(state);
  final streakMap = buildStreakMap(sessions);
  AccountView? view;
  var raw = 0.0, history = 0.0;
  final latestByLibraryId = <String, ({double ts, String key})>{};
  for (final r in sessions) {
    final s = asMap(r);
    if (s == null || s['status'] == 'skipped') continue;
    final key = sessionDayKey(s);
    final streak = key.isNotEmpty ? (streakMap[key] ?? 1) : 1;
    final mult = l.streakMultiplier(streak);
    final base = math.max(0.0, jsRound(baseSessionXP(s, l, () => view ??= AccountView(state))));
    raw += base;
    history += math.max(0.0, jsRound(base * mult));
    final ts = jsNum(s['timestamp']);
    for (final t in asList(s['titles'])) {
      final id = jsStr(asMap(t)?['libraryId']);
      if (id.isEmpty) continue;
      final prev = latestByLibraryId[id];
      if (prev == null || ts >= prev.ts) latestByLibraryId[id] = (ts: ts, key: key);
    }
  }
  final completions = asMap(ledger['logCompletions']) ?? const {};
  var completedTitles = 0;
  final byId = <String, Map<String, dynamic>>{};
  for (final item in library) {
    if (isCompletedItem(item)) completedTitles++;
    final id = jsStr(item['id']);
    if (id.isNotEmpty && completions.containsKey(id)) byId[id] = item;
  }
  var completionStreakBonus = 0.0;
  for (final e in completions.entries) {
    final rawXP = math.max(0.0, jsNum(e.value));
    if (rawXP <= 0) continue;
    final item = byId[e.key];
    if (item == null) continue;
    final ts = jsNum(item['completedAt']);
    final key = ts > 0 ? isoDateUtc(ts.toInt()) : (latestByLibraryId[e.key]?.key ?? '');
    final streak = streakMap[key] ?? 0;
    final total = math.max(0.0, jsRound(rawXP * l.streakMultiplier(streak)));
    completionStreakBonus += math.max(0.0, total - rawXP);
  }
  final enabled = l.enabled;
  final libraryTitleXP = enabled ? library.length * math.max(0.0, jsRound(l.reward('libraryAdditionXP'))) : 0.0;
  final completedTitleXP = enabled ? completedTitles * l.completionXP : 0.0;
  final days = asMap(ledger['v334ActiveTimeDays']) ?? const {};
  final appDays = asMap(ledger['v561AppTimeDays']) ?? const {};
  double sum(Map<String, dynamic> d, String k) => d.values.fold<double>(0, (a, x) => a + math.max(0, jsNum(asMap(x)?[k])));
  // v561: time in the MediaFlow app counts like time on the website.
  final webMs = sum(days, 'ms'), appMs = sum(appDays, 'ms');
  final activeMs = webMs + appMs;
  final timeXP = sum(days, 'xp') + sum(appDays, 'xp');
  final platformMs = <String, double>{};
  for (final x in appDays.values) {
    (asMap(asMap(x)?['platforms']) ?? const {}).forEach((k, v) => platformMs['$k'] = (platformMs['$k'] ?? 0) + math.max(0, jsNum(v)));
  }
  final starts = _sumMap(ledger['v334StartedTitles']);
  final creates = _sumMap(ledger['v334CollectionCreates']);
  final edits = _sumMap(ledger['v334CollectionEdits']);
  final firstEpisode = _sumMap(ledger['v335FirstEpisodeRewards']);
  final v348 = _sumMap(ledger['v348ActionEvents']) + _sumMap(ledger['v348LibraryAdditionBonus']) + _sumMap(ledger['v348LibraryCompletionBonus']);
  // mf544: award-guarantee receipts for logs that still exist.
  final groups = <String>{}, ids = <String>{};
  for (final r in sessions) {
    final s = asMap(r);
    if (s == null || s['status'] == 'skipped') continue;
    if (jsTruthy(s['sessionGroupId'])) groups.add(jsStr(s['sessionGroupId']));
    if (jsTruthy(s['id'])) ids.add(jsStr(s['id']));
  }
  var receipts = 0.0;
  for (final x in (asMap(ledger['v544LogAwardGuarantees']) ?? const {}).values) {
    final rec = asMap(x);
    if (rec == null) continue;
    final ok = jsTruthy(rec['sessionId']) ? ids.contains(jsStr(rec['sessionId'])) : (jsTruthy(rec['groupId']) && groups.contains(jsStr(rec['groupId'])));
    if (ok) receipts += math.max(0, jsNum(rec['xp']));
  }
  final fixedBase = libraryTitleXP + completedTitleXP + _sumMap(ledger['libraryEdits']) + _sumMap(ledger['manualCovers']) +
      _sumMap(ledger['logCompletions']) + _sumMap(ledger['ratings']);
  final total = jsRound(history + fixedBase + completionStreakBonus) + timeXP + starts + creates + edits + firstEpisode + v348 + receipts;
  return XpMetrics({
    'total': total,
    'history': jsRound(history),
    'raw': jsRound(raw),
    'sessionStreakBonus': math.max(0.0, jsRound(history - raw)),
    'completionStreakBonus': jsRound(completionStreakBonus),
    'activeMs': activeMs,
    'websiteActiveMs': webMs,
    'appActiveMs': appMs,
    'activeTimeXP': timeXP,
    for (final e in platformMs.entries) 'appMs.${e.key}': e.value,
    'completedTitles': completedTitles.toDouble(),
  });
}

class LevelInfo {
  LevelInfo(this.xp, this.level, this.current, this.needed);
  final double xp;
  final int level;
  final double current, needed;
  int get pct => needed == 0 ? 100 : math.min(100, (current / needed * 100).round());
}

/// `mediaFlowLevelInfo`.
LevelInfo levelInfo(double xp) {
  var level = 1;
  var spent = 0.0, need = 100.0;
  while (xp >= spent + need) {
    spent += need;
    level++;
    need = jsRound(100 * math.pow(level, 1.35).toDouble());
  }
  return LevelInfo(xp, level, xp - spent, need);
}

// ---- totals ------------------------------------------------------------------------

class Totals {
  double minutes = 0;
  int tasks = 0;
  final Map<String, double> units = {for (final u in kUnits.keys) u: 0};
  String unitsText() {
    final parts = [for (final e in units.entries) if (e.value > 0) '${_fmt(e.value)} ${unitLabel(e.key, e.value)}'];
    return parts.isEmpty ? 'No units recorded' : parts.join(' · ');
  }
}

String _fmt(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

/// `totalsForSessions`.
Totals totalsFor(Iterable<Map<String, dynamic>> list) {
  final t = Totals();
  for (final s in list) {
    if (s['status'] == 'skipped') continue;
    t.minutes += jsNum(s['minutes']);
    t.tasks++;
    final u = jsStr(s['unit']);
    if (t.units.containsKey(u)) t.units[u] = t.units[u]! + jsNum(s['actualAmount']);
  }
  return t;
}

/// `v331LogicalSessionCount`.
int logicalSessionCount(Iterable<Map<String, dynamic>> sessions) {
  final seen = <String>{};
  for (final s in sessions) {
    final key = jsTruthy(s['sessionGroupId'])
        ? 'session:${s['sessionGroupId']}'
        : jsTruthy(s['batchGroupId'])
            ? 'batch:${s['batchGroupId']}'
            : 'entry:${jsTruthy(s['id']) ? s['id'] : seen.length}';
    seen.add(key);
  }
  return seen.length;
}

class DayBar {
  DayBar(this.date, this.label, this.minutes, this.tasks);
  final String date, label;
  final double minutes;
  final int tasks;
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The website's daily series: local midnight of each day, keyed by its UTC date.
List<DayBar> dailySeries(List<Map<String, dynamic>> sessions, int days, DateTime now, String Function(DateTime d, int i) label) {
  final byDate = <String, ({double m, int n})>{};
  for (final s in sessions) {
    if (s['status'] == 'skipped') continue;
    final d = jsStr(s['date']);
    final cur = byDate[d] ?? (m: 0.0, n: 0);
    byDate[d] = (m: cur.m + jsNum(s['minutes']), n: cur.n + 1);
  }
  final out = <DayBar>[];
  for (var i = days - 1; i >= 0; i--) {
    final d = DateTime(now.year, now.month, now.day - i);
    final iso = isoDateUtc(d.millisecondsSinceEpoch);
    final v = byDate[iso];
    out.add(DayBar(iso, label(d, i), v?.m ?? 0, v?.n ?? 0));
  }
  return out;
}

String weekdayLabel(DateTime d, int i) => _wd[d.weekday - 1];
String monthDayLabel(DateTime d, int i) => '${_mo[d.month - 1]} ${d.day}';

/// `v129SessionTime`.
double sessionTime(Map<String, dynamic> s) {
  final ts = jsNum(s['timestamp']);
  if (ts > 0) return ts;
  final raw = jsStr(s['date']);
  if (raw.length >= 10 && isIsoDay(raw.substring(0, 10))) {
    return DateTime.parse('${raw.substring(0, 10)}T12:00:00').millisecondsSinceEpoch.toDouble();
  }
  return 0;
}

// ---- the whole page -------------------------------------------------------------------

class StatsModel {
  StatsModel(this.state, this.now);
  final Map<String, dynamic> state;
  final DateTime now;

  late final List<Map<String, dynamic>> sessions =
      asList(state['sessions']).map(asMap).whereType<Map<String, dynamic>>().toList();
  late final List<Map<String, dynamic>> consumption = sessions.where((s) => s['status'] != 'skipped').toList();
  late final List<Map<String, dynamic>> library =
      asList(state['library']).map(asMap).whereType<Map<String, dynamic>>().toList();
  late final List<Map<String, dynamic>> categories =
      asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().toList();
  int get nowMs => now.millisecondsSinceEpoch;

  Map<String, dynamic>? category(Object? id) => _categoryById[jsStr(id)];
  late final Map<String, Map<String, dynamic>> _categoryById = () {
    final out = <String, Map<String, dynamic>>{};
    for (final c in categories) {
      out.putIfAbsent(jsStr(c['id']), () => c);
    }
    return out;
  }();

  // History grouped once (same order as the list), so per-category, per-month
  // and per-year figures don't each read every log again.
  late final List<String> _dayKeys = [for (final s in consumption) sessionDayKey(s)];
  late final Map<String, double> _minutesByCategory = () {
    final out = <String, double>{};
    for (final s in consumption) {
      final id = jsStr(s['categoryId']);
      out[id] = (out[id] ?? 0) + jsNum(s['minutes']);
    }
    return out;
  }();
  late final Map<String, List<int>> _byMonth = () {
    final out = <String, List<int>>{};
    for (var i = 0; i < _dayKeys.length; i++) {
      final k = _dayKeys[i];
      if (k.length >= 7) (out[k.substring(0, 7)] ??= []).add(i);
    }
    return out;
  }();

  late final XpMetrics xp = xpMetrics(state);
  late final LevelInfo level = levelInfo(xp.total);
  late final Totals life = totalsFor(sessions);
  late final Totals today = () {
    final day = isoDateUtc(nowMs);
    return totalsFor(sessions.where((s) => s['date'] == day));
  }();
  late final Totals week = totalsFor(sessions.where((s) => jsNum(s['timestamp']) >= nowMs - 7 * 86400000));
  late final Totals month = totalsFor(sessions.where((s) => jsNum(s['timestamp']) >= nowMs - 30 * 86400000));
  double get totalUnits => life.units['episodes']! + life.units['chapters']! + life.units['movies']! + life.units['issues']!;
  int get logicalSessions => logicalSessionCount(sessions);
  late final int streak = buildStreakMap(sessions)[isoDateUtc(nowMs)] ?? 0;

  late final List<DayBar> last7 = dailySeries(sessions, 7, now, weekdayLabel);
  late final List<DayBar> last30 = dailySeries(sessions, 30, now, monthDayLabel);
  late final List<DayBar> last90 = dailySeries(sessions, 90, now, (d, i) => i % 7 == 0 ? monthDayLabel(d, i) : '');

  /// Profile pills.
  int get titles => library.length;

  /// `mfLifetime`.
  ({int completed, double episodes, double movies, double chapters, double issues, double minutes}) get achievements {
    double sum(String unit) => consumption.where((s) => s['unit'] == unit).fold<double>(0, (a, s) => a + math.max(0, jsNum(s['actualAmount'])));
    return (
      completed: library.where((i) => i['status'] == 'completed').map((i) => i['id']).toSet().length,
      episodes: sum('episodes'),
      movies: sum('movies'),
      chapters: sum('chapters'),
      issues: sum('issues'),
      minutes: consumption.fold<double>(0, (a, s) => a + math.max(0, jsNum(s['minutes']))),
    );
  }

  /// "30-day category mix" (the website sums all History for enabled categories).
  List<({Map<String, dynamic> cat, double minutes})> get categoryMix {
    final rows = [
      for (final c in categories.where((c) => jsTruthy(c['enabled'])))
        (cat: c, minutes: _minutesByCategory[jsStr(c['id'])] ?? 0.0),
    ];
    stableSort(rows, (a, b) => b.minutes.compareTo(a.minutes));
    return rows;
  }

  /// `v532MediaTypeMix`.
  List<(String, double)> get mediaTypeMix {
    const rows = [('video', 'Watching'), ('reading', 'Reading'), ('playing', 'Playing'), ('listening', 'Listening')];
    final types = {for (final r in rows) r.$1};
    final lookup = {for (final c in categories) jsStr(c['id']): jsStr(c['type'])};
    final totals = {for (final r in rows) r.$1: 0.0};
    var other = false;
    for (final s in consumption) {
      final raw = lookup[jsStr(s['categoryId'])] ?? '';
      final type = types.contains(raw) ? raw : 'other';
      if (type == 'other') {
        other = true;
        totals.putIfAbsent('other', () => 0);
      }
      totals[type] = totals[type]! + jsNum(s['minutes']);
    }
    return [for (final r in rows) (r.$2, totals[r.$1]!), if (other) ('Other', totals['other']!)];
  }

  List<(String, int)> get libraryStatus => [
        for (final k in const [('planned', 'Planned'), ('active', 'In progress'), ('paused', 'Paused'), ('completed', 'Completed'), ('dropped', 'Dropped')])
          (k.$2, library.where((i) => i['status'] == k.$1).length),
      ];

  List<(String, int)> get priorities => [
        for (final k in const ['high', 'medium', 'low']) ('${k[0].toUpperCase()}${k.substring(1)}', library.where((i) => i['priority'] == k).length),
      ];

  /// `v81RepeatTotals`.
  ({int sessions, double minutes, double episodes, double chapters, double issues, double movies}) get repeats {
    final byId = {for (final i in library) if (jsTruthy(i['id'])) jsStr(i['id']): i};
    var sessionsN = 0;
    var minutes = 0.0, ep = 0.0, ch = 0.0, iss = 0.0, mv = 0.0;
    void addUnits(String unit, double n) {
      if (unit == 'episodes') {
        ep += n;
      } else if (unit == 'chapters') {
        ch += n;
      } else if (unit == 'issues') {
        iss += n;
      } else if (unit == 'movies') {
        mv += n;
      }
    }

    for (final sess in sessions) {
      var had = false;
      for (final raw in asList(sess['titles'])) {
        final t = asMap(raw);
        if (t == null) continue;
        final itemized = t['v369Units'] is List && t['v369Itemized'] == true;
        if (t['repeat'] != true && !itemized) continue;
        final item = jsTruthy(t['libraryId']) ? byId[jsStr(t['libraryId'])] : null;
        final key = jsStr(item?['id'] ?? t['libraryId']);
        if (key.isEmpty) continue;
        final unit = jsStr(category(item?['categoryId'] ?? sess['categoryId'])?['unit']).isNotEmpty
            ? jsStr(category(item?['categoryId'] ?? sess['categoryId'])?['unit'])
            : (jsStr(sess['unit']).isEmpty ? 'units' : jsStr(sess['unit']));
        final amount = itemized
            ? asList(t['v369Units']).where((u) => t['repeat'] == true || asMap(u)?['isRepeat'] == true).length.toDouble()
            : math.max(0.0, jsNum(t['qty']));
        if (amount == 0) continue;
        had = true;
        addUnits(unit, amount);
      }
      if (had) {
        sessionsN++;
        minutes += math.max(0, jsNum(sess['minutes']));
      }
    }
    for (final item in library) {
      final manual = math.max(0, jsNum(item['manualRepeatAmount']).floor()).toDouble();
      if (manual == 0) continue;
      addUnits(jsStr(category(item['categoryId'])?['unit']), manual);
    }
    return (sessions: sessionsN, minutes: minutes, episodes: ep, chapters: ch, issues: iss, movies: mv);
  }

  double get avgDaily7 => jsRound(last7.fold<double>(0, (a, d) => a + d.minutes) / 7);
  double get avgSession => logicalSessions == 0 ? 0 : jsRound(life.minutes / logicalSessions);
  double get peakDay => last30.fold<double>(0, (a, d) => math.max(a, d.minutes));
  String? get mostActiveDay => last30.where((d) => d.minutes == peakDay).firstOrNull?.date;

  // ---- v129 classic cards ----

  List<({Map<String, dynamic> cat, double minutes, int pct})> get categoryBalance {
    final cats = scopeCategories(state, 'categoryBalance');
    final cutoff = nowMs - 7 * 86400000;
    final recent = <String, double>{};
    for (final s in consumption) {
      if (!(sessionTime(s) >= cutoff)) continue;
      final id = jsStr(s['categoryId']);
      recent[id] = (recent[id] ?? 0) + jsNum(s['minutes']);
    }
    final values = [
      for (final c in cats) (cat: c, minutes: recent[jsStr(c['id'])] ?? 0.0),
    ];
    final max = values.fold<double>(1, (a, x) => math.max(a, x.minutes));
    return [for (final x in values) (cat: x.cat, minutes: x.minutes, pct: x.minutes > 0 ? math.max(2, (x.minutes / max * 100).round()) : 0)];
  }

  /// `saturationLevel` per category (the saturation scope).
  List<({Map<String, dynamic> cat, String label, int color})> get saturation {
    final cutoff = nowMs - 72 * 3600000;
    final recent = <String, double>{};
    for (final s in consumption) {
      if (!(jsNum(s['timestamp']) >= cutoff)) continue;
      final id = jsStr(s['categoryId']);
      recent[id] = (recent[id] ?? 0) + jsNum(s['minutes']);
    }
    return [
      for (final c in scopeCategories(state, 'saturation'))
        () {
          final min72 = recent[jsStr(c['id'])] ?? 0.0;
          final cat = Category(c);
          final baseline = math.max((cat.target ?? double.nan) * cat.minutesPerUnit, 1) * 2.2;
          final ratio = baseline.isNaN ? double.nan : min72 / baseline;
          if (ratio < 0.25) return (cat: c, label: 'VERY LOW', color: 0xFF5AA9E6);
          if (ratio < 0.7) return (cat: c, label: 'LOW', color: 0xFF3FC7A6);
          if (ratio < 1.4) return (cat: c, label: 'MEDIUM', color: 0xFFE8A94A);
          if (ratio < 2.4) return (cat: c, label: 'HIGH', color: 0xFFF58A5A);
          return (cat: c, label: 'VERY HIGH', color: 0xFFE8607A);
        }(),
    ];
  }

  List<({Map<String, dynamic> cat, double minutes})> get _lifetimeByCategory => [
        for (final c in categories.where((c) => jsTruthy(c['enabled'])))
          (cat: c, minutes: _minutesByCategory[jsStr(c['id'])] ?? 0.0),
      ];

  ({Map<String, dynamic> cat, double minutes})? get mostConsumed {
    final rows = List.of(_lifetimeByCategory);
    if (rows.isEmpty) return null;
    stableSort(rows, (a, b) => b.minutes.compareTo(a.minutes));
    return rows.first;
  }

  ({Map<String, dynamic> cat, double minutes})? get leastConsumed {
    ({Map<String, dynamic> cat, double minutes})? least;
    for (final x in _lifetimeByCategory) {
      if (least == null || x.minutes <= least.minutes) least = x;
    }
    return least;
  }

  /// `v129CategoryStreaks`.
  ({Map<String, dynamic>? current, int currentCount, Map<String, dynamic>? longest, int longestCount}) get categoryStreaks {
    final rows = consumption.where((s) => jsTruthy(s['categoryId'])).toList();
    stableSort(rows, (a, b) => sessionTime(a).compareTo(sessionTime(b)));
    if (rows.isEmpty) return (current: null, currentCount: 0, longest: null, longestCount: 0);
    String? runCat, longestCat;
    var run = 0, longest = 0;
    for (final s in rows) {
      final c = jsStr(s['categoryId']);
      if (c == runCat) {
        run++;
      } else {
        runCat = c;
        run = 1;
      }
      if (run > longest) {
        longest = run;
        longestCat = c;
      }
    }
    final currentCat = jsStr(rows.last['categoryId']);
    var current = 0;
    for (var i = rows.length - 1; i >= 0; i--) {
      if (jsStr(rows[i]['categoryId']) != currentCat) break;
      current++;
    }
    return (current: category(currentCat), currentCount: current, longest: category(longestCat), longestCount: longest);
  }

  /// `v129MostNeglected`.
  (Map<String, dynamic>?, String) get mostNeglected {
    final cats = categories.where((c) => jsTruthy(c['enabled'])).toList();
    final lastTime = <String, double>{};
    for (final s in consumption) {
      final id = jsStr(s['categoryId']);
      final t = sessionTime(s);
      final cur = lastTime[id];
      lastTime[id] = cur == null ? (t > 0 ? t : double.negativeInfinity) : (t > 0 ? math.max(cur, t) : cur);
    }
    for (final c in cats) {
      if (!lastTime.containsKey(jsStr(c['id']))) return (c, 'never');
    }
    Map<String, dynamic>? winner;
    var oldest = double.infinity;
    for (final c in cats) {
      final last = lastTime[jsStr(c['id'])] ?? double.negativeInfinity;
      if (last < oldest) {
        oldest = last;
        winner = c;
      }
    }
    if (winner == null) return (null, '—');
    final days = math.max(0, ((nowMs - oldest) / 86400000).floor());
    return (winner, days == 0 ? 'today' : days == 1 ? '1 day ago' : '$days days ago');
  }

  /// `v129AverageDailyConsumption`.
  double get averageDaily {
    if (consumption.isEmpty) return 0;
    final days = <String>{};
    var minutes = 0.0;
    for (var i = 0; i < consumption.length; i++) {
      final k = _dayKeys[i];
      if (k.isNotEmpty) days.add(k);
      minutes += jsNum(consumption[i]['minutes']);
    }
    return days.isEmpty ? 0 : jsRound(minutes / days.length);
  }

  /// `v129TaskCompletionRate`.
  int get completionRate {
    final tasks = consumption.where((s) => const ['partial', 'complete', 'over'].contains(jsStr(s['status'])) && s['followedAssignedCategory'] != false).toList();
    if (tasks.isEmpty) return 0;
    final done = tasks.where((s) => s['status'] == 'complete' || s['status'] == 'over').length;
    return (done / tasks.length * 100).round();
  }

  // ---- ratings (v44) ----

  List<double> get _ratings => [for (final i in library) if (jsNum(i['rating']) > 0) jsNum(i['rating'])];
  int get ratedCount => _ratings.length;
  double get averageRating => _ratings.isEmpty ? 0 : _ratings.reduce((a, b) => a + b) / _ratings.length;
  int get rated8 => _ratings.where((r) => r >= 8).length;
  int get rated95 => _ratings.where((r) => r >= 9.5).length;
  List<(int, int)> get ratingDistribution => [for (var n = 10; n >= 1; n--) (n, _ratings.where((r) => r.ceil() == n).length)];

  // ---- heatmap / recap / timeline (v119/v136) ----

  List<double> get _historyTimes {
    final noon = <String, double>{};
    return [
        for (final k in _dayKeys)
          if (k.isNotEmpty) noon[k] ??= DateTime.parse('${k}T12:00:00').millisecondsSinceEpoch.toDouble(),
        for (final i in library)
          if (jsNum(i['completedAt']) > 0) jsNum(i['completedAt']),
        for (final x in asList(state['completionTimeline']))
          if (jsNum(asMap(x)?['completedAt']) > 0) jsNum(asMap(x)?['completedAt']),
      ];
  }

  List<String> get recapMonths {
    final times = _historyTimes;
    final minTime = times.isEmpty ? nowMs.toDouble() : times.reduce(math.min);
    final maxTime = math.max(nowMs.toDouble(), times.isEmpty ? 0.0 : times.reduce(math.max));
    final first = DateTime.fromMillisecondsSinceEpoch(minTime.toInt()), last = DateTime.fromMillisecondsSinceEpoch(maxTime.toInt());
    var cursor = DateTime(last.year, last.month);
    final stop = DateTime(first.year, first.month);
    final out = <String>[];
    while (!cursor.isBefore(stop) && out.length < 1200) {
      out.add('${cursor.year}-${cursor.month.toString().padLeft(2, '0')}');
      cursor = DateTime(cursor.year, cursor.month - 1);
    }
    return out.isEmpty ? ['${now.year}-${now.month.toString().padLeft(2, '0')}'] : out;
  }

  /// `renderMonthlyRecap` for [month] ('YYYY-MM').
  ({double minutes, Map<String, dynamic>? top, double topMinutes, int finished, int longest}) recap(String month) {
    final parts = month.split('-').map(int.parse).toList();
    final start = DateTime(parts[0], parts[1]).millisecondsSinceEpoch, end = DateTime(parts[0], parts[1] + 1).millisecondsSinceEpoch;
    final ss = [for (final i in _byMonth[month] ?? const <int>[]) consumption[i]];
    final byCat = <String, double>{};
    for (final s in ss) {
      byCat[jsStr(s['categoryId'])] = (byCat[jsStr(s['categoryId'])] ?? 0) + jsNum(s['minutes']);
    }
    final entries = byCat.entries.toList();
    stableSort(entries, (a, b) => b.value.compareTo(a.value));
    final finished = library.where((i) => i['status'] == 'completed' && jsNum(i['completedAt']) >= start && jsNum(i['completedAt']) < end).length;
    final days = [for (final i in _byMonth[month] ?? const <int>[]) _dayKeys[i]].where((d) => d.isNotEmpty).toSet().toList()..sort();
    var longest = 0, run = 0;
    DateTime? prev;
    for (final d in days) {
      final cur = DateTime.parse('${d}T12:00:00');
      run = prev != null && (cur.difference(prev).inHours / 24).round() == 1 ? run + 1 : 1;
      longest = math.max(longest, run);
      prev = cur;
    }
    return (
      minutes: ss.fold<double>(0, (a, s) => a + jsNum(s['minutes'])),
      top: entries.isEmpty ? null : category(entries.first.key),
      topMinutes: entries.isEmpty ? 0 : entries.first.value,
      finished: finished,
      longest: longest,
    );
  }

  List<int> get heatmapYears {
    final years = <int>{now.year};
    for (final k in _dayKeys) {
      final y = int.tryParse(k.padRight(4).substring(0, 4));
      if (y != null && y >= 1900 && y <= 9999) years.add(y);
    }
    for (final i in library) {
      for (final ts in [jsNum(i['startedAt']), jsNum(i['completedAt'])]) {
        if (ts > 0) years.add(DateTime.fromMillisecondsSinceEpoch(ts.toInt()).year);
      }
    }
    for (final x in asList(state['completionTimeline'])) {
      final ts = jsNum(asMap(x)?['completedAt']);
      if (ts > 0) years.add(DateTime.fromMillisecondsSinceEpoch(ts.toInt()).year);
    }
    return years.where((y) => y >= 1900 && y <= 9999).toList()..sort((a, b) => b - a);
  }

  /// `renderConsumptionHeatmap`: per local day of [year] → (minutes, started, finished).
  ({Map<String, ({double minutes, int sessions, List<String> started, List<String> finished})> days, double max}) heatmap(int year) {
    final map = <String, ({double minutes, int sessions, List<String> started, List<String> finished})>{};
    ({double minutes, int sessions, List<String> started, List<String> finished}) ensure(String k) =>
        map[k] ??= (minutes: 0, sessions: 0, started: <String>[], finished: <String>[]);
    for (var i = 0; i < consumption.length; i++) {
      final s = consumption[i];
      final k = _dayKeys[i];
      if (k.isEmpty || int.tryParse(k.substring(0, 4)) != year) continue;
      final v = ensure(k);
      map[k] = (minutes: v.minutes + jsNum(s['minutes']), sessions: v.sessions + 1, started: v.started, finished: v.finished);
    }
    String key(double ts) {
      final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    final seenStart = <String>{}, seenFinish = <String>{};
    for (final item in library) {
      final title = cleanTitle(item['title']);
      if (title.isEmpty) continue;
      final st = jsNum(item['startedAt']), fin = jsNum(item['completedAt']);
      if (st > 0 && DateTime.fromMillisecondsSinceEpoch(st.toInt()).year == year && seenStart.add('${item['id'] ?? title}::${key(st)}')) {
        ensure(key(st)).started.add(title);
      }
      if (fin > 0 && DateTime.fromMillisecondsSinceEpoch(fin.toInt()).year == year && seenFinish.add('${item['id'] ?? title}::${key(fin)}')) {
        ensure(key(fin)).finished.add(title);
      }
    }
    for (final raw in asList(state['completionTimeline'])) {
      final x = asMap(raw);
      final fin = jsNum(x?['completedAt']);
      if (x == null || fin <= 0 || DateTime.fromMillisecondsSinceEpoch(fin.toInt()).year != year) continue;
      final title = cleanTitle(x['title']);
      if (title.isEmpty || !seenFinish.add('${x['libraryId'] ?? title}::${key(fin)}')) continue;
      ensure(key(fin)).finished.add(title);
    }
    final max = map.values.fold<double>(1, (a, v) => math.max(a, v.minutes));
    return (days: map, max: max);
  }

  /// `renderCompletionTimeline`.
  List<({String title, Object? categoryId, double completedAt})> get completionTimeline {
    final map = <String, ({String title, Object? categoryId, double completedAt})>{};
    for (final raw in asList(state['completionTimeline'])) {
      final x = asMap(raw);
      if (x == null || !jsTruthy(x['completedAt'])) continue;
      final k = jsTruthy(x['libraryId']) ? jsStr(x['libraryId']) : '${x['title']}::${x['completedAt']}';
      map[k] = (title: cleanTitle(x['title']), categoryId: x['categoryId'], completedAt: jsNum(x['completedAt']));
    }
    for (final i in library) {
      if (i['status'] != 'completed' || !jsTruthy(i['completedAt'])) continue;
      map.putIfAbsent(jsStr(i['id']), () => (title: cleanTitle(i['title']), categoryId: i['categoryId'], completedAt: jsNum(i['completedAt'])));
    }
    final out = map.values.toList()..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return out;
  }

  /// v334 "Active time spent in MediaFlow".
  double get activeMs => xp['activeMs'];

  /// Visible Today's Balance categories (for the profile pills).
  int get balanceCategories => visiblePanelCategories(state, 'todayBalance').length;
}

/// Level, XP, today's streak and Library size, for Discord's {level}, {xp},
/// {streak} and {library}. 7.0.0: worked out in the sync isolate, where the
/// account is already decoded, instead of on the screen's thread after every
/// change (the regular slow frames on big accounts). Null when it can't be read.
Map<String, num>? presenceStatsOf(Map<String, dynamic> state, [DateTime? now]) {
  try {
    final t = now ?? DateTime.now();
    final xp = xpMetrics(state).total;
    return {
      'level': levelInfo(xp).level,
      'xp': xp,
      'streak': buildStreakMap(asList(state['sessions']))[isoDateUtc(t.millisecondsSinceEpoch)] ?? 0,
      'library': asList(state['library']).length,
    };
  } catch (_) {
    return null;
  }
}
