// The website's Dashboard tools, shown in the app's Extras tab:
//   Stopwatch (stopwatch* + v257 cloud state), Runtime Calculator (v256/v257),
//   Today's Balance (v265 + mf508 panel scope) and On This Day (v159 model).
// Stopwatch and Runtime Calculator live in the account (`dashboardToolsV257`,
// newest `modifiedAt` wins, exactly like the website's own merge).

import 'dart:convert';
import 'dart:math' as math;

import '../state/models.dart';
import '../util/js.dart';
import 'leveling.dart';
import 'recommend.dart';

T _clone<T>(T v) => jsonDecode(jsonEncode(v)) as T;

double _nonNeg(Object? v) => math.max(0, jsNum(v));
int _floorNonNeg(Object? v) => math.max(0, jsNum(v).floor());

// ---- Stopwatch ------------------------------------------------------------------

/// `v257NormalizeStopwatch`.
Map<String, dynamic> normalizeStopwatch(Object? raw) {
  final x = asMap(raw) ?? const {};
  return {
    'running': x['running'] == true,
    'startedAt': jsOut(_nonNeg(x['startedAt'])),
    'elapsed': jsOut(_nonNeg(x['elapsed'])),
    'resetValue': jsOut(_nonNeg(x['resetValue'])),
    'modifiedAt': jsOut(_nonNeg(x['modifiedAt'])),
  };
}

/// `fmtStopwatch`.
String fmtStopwatch(num ms) {
  final sec = math.max(0, (ms / 1000).floor());
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(sec ~/ 3600)}:${two(sec % 3600 ~/ 60)}:${two(sec % 60)}';
}

/// One Stopwatch (the state stored in the account).
class Stopwatch2 {
  Stopwatch2(Object? raw) : data = normalizeStopwatch(raw);
  final Map<String, dynamic> data;

  bool get running => data['running'] == true;
  double get elapsedBase => jsNum(data['elapsed']);
  double get resetValue => jsNum(data['resetValue']);

  double elapsed(int now) => running ? elapsedBase + (now - jsNum(data['startedAt'])) : elapsedBase;

  void _touch(int now) => data['modifiedAt'] = now;

  static int _ms(int h, int m, int s) =>
      (h.clamp(0, 999).toInt() * 3600 + m.clamp(0, 59).toInt() * 60 + s.clamp(0, 59).toInt()) * 1000;

  /// `stopwatchStart`.
  bool start(int now) {
    if (running) return false;
    data['running'] = true;
    data['startedAt'] = now;
    _touch(now);
    return true;
  }

  /// `stopwatchPause`.
  bool pause(int now) {
    if (!running) return false;
    data['elapsed'] = jsOut(elapsedBase + now - jsNum(data['startedAt']));
    data['running'] = false;
    data['startedAt'] = 0;
    _touch(now);
    return true;
  }

  /// `stopwatchSetTime`. Returns the toast.
  String? setTime(int h, int m, int s, int now) {
    if (running) return null;
    final ms = _ms(h, m, s);
    data['elapsed'] = ms;
    data['resetValue'] = ms;
    data['startedAt'] = 0;
    _touch(now);
    return 'Stopwatch set to ${fmtStopwatch(ms)} ✓';
  }

  /// `stopwatchReset`.
  void reset(int now) {
    if (running) {
      data['running'] = false;
      data['startedAt'] = 0;
    }
    data['elapsed'] = jsOut(math.max(0, resetValue));
    _touch(now);
  }

  /// `stopwatchClear`.
  void clear(int now) {
    data
      ..['running'] = false
      ..['startedAt'] = 0
      ..['elapsed'] = 0
      ..['resetValue'] = 0;
    _touch(now);
  }

  /// `stopwatchAddTime`. Returns the toast.
  String? addTime(int h, int m, int s, int now) {
    if (running) return null;
    final add = _ms(h, m, s);
    if (add == 0) return 'Enter a time to add.';
    data['elapsed'] = jsOut(math.max(0.0, elapsedBase) + add);
    data['resetValue'] = data['elapsed'];
    data['startedAt'] = 0;
    _touch(now);
    return 'Added ${fmtStopwatch(add)} · ${fmtStopwatch(jsNum(data['elapsed']))} total ✓';
  }

  /// `stopwatchMinusTime`. Returns the toast.
  String? minusTime(int h, int m, int s, int now) {
    if (running) return null;
    final sub = _ms(h, m, s);
    if (sub == 0) return 'Enter a time to subtract.';
    final before = math.max(0.0, elapsedBase);
    data['elapsed'] = jsOut(math.max(0.0, before - sub));
    data['resetValue'] = data['elapsed'];
    data['startedAt'] = 0;
    _touch(now);
    return 'Subtracted ${fmtStopwatch(math.min(sub.toDouble(), before))} · ${fmtStopwatch(jsNum(data['elapsed']))} total ✓';
  }

  /// `stopwatchUseMinutes`.
  int minutes(int now) => math.max(0, jsRound(elapsed(now) / 60000).toInt());
}

// ---- Runtime Calculator -----------------------------------------------------------

Map<String, dynamic> _blankTime() => {'h': 0, 'm': 0, 's': 0};

/// `v256NormalizeTime`.
Map<String, dynamic> normalizeTime(Object? raw) {
  final r = asMap(raw) ?? const {};
  return {
    'h': _floorNonNeg(r['h']).clamp(0, 99999).toInt(),
    'm': _floorNonNeg(r['m']).clamp(0, 59).toInt(),
    's': _floorNonNeg(r['s']).clamp(0, 59).toInt(),
  };
}

int timeToSeconds(Object? row) {
  final r = normalizeTime(row);
  return (r['h'] as int) * 3600 + (r['m'] as int) * 60 + (r['s'] as int);
}

Map<String, dynamic> secondsToTime(num total) {
  final sec = math.max(0, total.floor());
  return {'h': sec ~/ 3600, 'm': sec % 3600 ~/ 60, 's': sec % 60};
}

/// `v256FormatRuntime`.
String fmtRuntime(num total) => fmtStopwatch(total * 1000);

/// `v257NormalizeRuntimeCalculator`.
Map<String, dynamic> normalizeRuntime(Object? raw) {
  final src = asMap(raw) ?? const {};
  final chain = src['chain'] is List ? asList(src['chain']).take(2).map(normalizeTime).toList() : [_blankTime(), _blankTime()];
  while (chain.length < 2) {
    chain.add(_blankTime());
  }
  final rows = src['rows'] is List ? asList(src['rows']).map(normalizeTime).toList() : [_blankTime(), _blankTime()];
  while (rows.length < 2) {
    rows.add(_blankTime());
  }
  return {
    'mode': src['mode'] == 'multi' ? 'multi' : 'chain',
    'chain': chain,
    'rows': rows,
    'resultSeconds': _floorNonNeg(src['resultSeconds']),
    'hasResult': src['hasResult'] == true,
    'resultCount': _floorNonNeg(src['resultCount']),
    'carryCount': _floorNonNeg(src['carryCount']),
    'previousAccumulatorSeconds': _floorNonNeg(src['previousAccumulatorSeconds']),
    'previousAccumulatorCount': _floorNonNeg(src['previousAccumulatorCount']),
    'modifiedAt': jsOut(_nonNeg(src['modifiedAt'])),
  };
}

class RuntimeCalc {
  RuntimeCalc(Object? raw) : data = normalizeRuntime(raw);
  final Map<String, dynamic> data;

  bool get multi => data['mode'] == 'multi';
  List<Map<String, dynamic>> get chain => asList(data['chain']).map((e) => asMap(e)!).toList();
  List<Map<String, dynamic>> get rows => asList(data['rows']).map((e) => asMap(e)!).toList();
  int get resultSeconds => jsNum(data['resultSeconds']).toInt();
  bool get hasResult => data['hasResult'] == true;
  int get resultCount => jsNum(data['resultCount']).toInt();
  int get previousSeconds => jsNum(data['previousAccumulatorSeconds']).toInt();

  void touch(int now) => data['modifiedAt'] = now;

  /// `v256UpdateRuntimeField`.
  void updateField(String scope, int index, String unit, Object? value) {
    if (!const ['h', 'm', 's'].contains(unit)) return;
    final max = unit == 'h' ? 99999 : 59;
    final n = _floorNonNeg(value).clamp(0, max);
    final list = asList(data[scope == 'chain' ? 'chain' : 'rows']);
    if (scope == 'chain' && (index < 0 || index > 1)) return;
    if (index < 0 || index >= list.length) return;
    asMap(list[index])![unit] = n;
  }

  /// `v256CalculateRuntime`. Returns a toast for errors.
  String? calculate() {
    if (multi) {
      final values = rows.map(timeToSeconds).toList();
      final count = values.where((v) => v > 0).length;
      if (count == 0) return 'Enter at least one runtime to calculate.';
      data['resultSeconds'] = values.fold<int>(0, (a, b) => a + b);
      data['resultCount'] = count;
      data['hasResult'] = true;
      data['carryCount'] = 0;
      data['previousAccumulatorSeconds'] = 0;
      data['previousAccumulatorCount'] = 0;
      return null;
    }
    final a = timeToSeconds(chain[0]), b = timeToSeconds(chain[1]);
    if (a <= 0 && b <= 0) return 'Enter at least one runtime to calculate.';
    final carry = jsNum(data['carryCount']).toInt();
    final firstCount = carry > 0 ? carry : (a > 0 ? 1 : 0);
    final secondCount = b > 0 ? 1 : 0;
    data['previousAccumulatorSeconds'] = a;
    data['previousAccumulatorCount'] = firstCount;
    data['resultSeconds'] = a + b;
    data['resultCount'] = firstCount + secondCount;
    data['hasResult'] = true;
    return null;
  }

  /// `v256ContinueRuntimeResult`.
  String continueResult() {
    if (!hasResult) return 'Calculate a result first.';
    data['mode'] = 'chain';
    data['chain'] = [secondsToTime(resultSeconds), _blankTime()];
    data['carryCount'] = math.max(1, resultCount == 0 ? 1 : resultCount);
    return '${fmtRuntime(resultSeconds)} moved to Runtime 1. Add the next runtime.';
  }

  /// `v256RestorePreviousRuntime`.
  String restorePrevious() {
    if (!hasResult || previousSeconds <= 0) return 'No previous accumulated runtime is available yet.';
    final prev = previousSeconds;
    final prevCount = math.max(1, jsNum(data['previousAccumulatorCount']).toInt());
    data['mode'] = 'chain';
    data['chain'] = [secondsToTime(prev), _blankTime()];
    data['resultSeconds'] = prev;
    data['resultCount'] = prevCount;
    data['carryCount'] = prevCount;
    data['hasResult'] = true;
    return 'Restored previous total ${fmtRuntime(prev)}.';
  }

  /// `v256SetRuntimeMode`.
  void setMode(String mode) {
    final next = mode == 'multi' ? 'multi' : 'chain';
    if (next == data['mode']) return;
    if (next == 'multi') {
      final seed = chain.map(normalizeTime).toList();
      data['rows'] = seed.any((x) => timeToSeconds(x) > 0) ? seed : [_blankTime(), _blankTime()];
    } else if (rows.isNotEmpty) {
      final r = rows;
      data['chain'] = [normalizeTime(r[0]), normalizeTime(r.length > 1 ? r[1] : _blankTime())];
    }
    data['mode'] = next;
  }

  /// `v256AddRuntimeRow`.
  void addRow() {
    data['mode'] = 'multi';
    data['rows'] = [...asList(data['rows']), _blankTime()];
  }

  /// `v256RemoveRuntimeRow`.
  String? removeRow(int index) {
    final list = List<dynamic>.of(asList(data['rows']));
    if (list.length <= 2) return 'Multi-row mode keeps at least two runtime rows.';
    list.removeAt(index.clamp(0, list.length - 1));
    data['rows'] = list;
    return null;
  }

  /// `v256ClearRuntimeCalculator`.
  void clear() {
    final at = data['modifiedAt'];
    data
      ..clear()
      ..addAll(normalizeRuntime(null))
      ..['modifiedAt'] = at;
  }

  /// `v256RuntimeUseMinutes`.
  int get minutes => math.max(0, jsRound(resultSeconds / 60).toInt());
}

// ---- account storage (dashboardToolsV257) ------------------------------------------

/// The tools as the website would read them (`v257ApplyDashboardTools`).
({Map<String, dynamic> stopwatch, Map<String, dynamic> runtime}) readTools(Map<String, dynamic> state) {
  final tools = asMap(state['dashboardToolsV257']);
  final sw = tools?['stopwatch'] != null ? tools!['stopwatch'] : state['stopwatch'];
  final rt = tools?['runtimeCalculator'] ?? state['v256RuntimeCalculator'];
  return (stopwatch: normalizeStopwatch(sw), runtime: normalizeRuntime(rt));
}

/// Writes one tool if it is newer than what the account has. Returns true if changed.
bool writeTool(Map<String, dynamic> state, String tool, Map<String, dynamic> value) {
  final current = readTools(state);
  final incoming = tool == 'stopwatch' ? normalizeStopwatch(value) : normalizeRuntime(value);
  final existing = tool == 'stopwatch' ? current.stopwatch : current.runtime;
  if (jsonEncode(existing) == jsonEncode(incoming)) return false;
  if (jsNum(existing['modifiedAt']) > jsNum(incoming['modifiedAt'])) return false; // newer change wins
  final sw = tool == 'stopwatch' ? incoming : current.stopwatch;
  final rt = tool == 'stopwatch' ? current.runtime : incoming;
  state['dashboardToolsV257'] = {
    'stopwatch': sw,
    'runtimeCalculator': rt,
    'modifiedAt': math.max(jsNum(sw['modifiedAt']), jsNum(rt['modifiedAt'])),
  };
  state['stopwatch'] = _clone(sw);
  return true;
}

// ---- Today's Balance ---------------------------------------------------------------

/// `mf508NormalizePanel` (the parts Today's Balance reads).
Map<String, dynamic> balancePanel(Map<String, dynamic> state, String key) {
  final settings = asMap(state['settings']) ?? const {};
  final all = asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().where((c) => c['id'] != null).toList();
  final known = all.map((c) => jsStr(c['id'])).toSet();
  List<String> unique(Object? ids) => [
        ...{for (final x in asList(ids)) if (known.contains(jsStr(x))) jsStr(x)}
      ];
  final legacy = asMap(asMap(settings['v186ControlCenter'])?['todayBalance']);
  final previouslyCustom = key == 'todayBalance' && legacy?['mode'] == 'custom';
  final prior = unique(legacy?['categoryIds']);
  final def = {
    'enabled': key == 'todayBalance'
        ? (asMap(settings['v192Dashboard'])?['showTodayBalance']) != false
        : (asMap(settings['v183LibraryOverview'])?['showOverview']) != false,
    'source': previouslyCustom ? 'custom' : 'categories',
    'hiddenIds': previouslyCustom ? [for (final c in all) if (!prior.contains(jsStr(c['id']))) jsStr(c['id'])] : <String>[],
    'order': [for (final c in all) jsStr(c['id'])],
  };
  final val = asMap(asMap(settings['v508Panels'])?[key]) ?? const {};
  const sources = ['categories', 'system', 'custom', 'todayBalance', 'libraryOverview'];
  var source = sources.contains(val['source']) ? jsStr(val['source']) : def['source'] as String;
  if (source == key) source = 'categories';
  final oldOrder = unique(val['order']);
  final order = [...oldOrder, for (final c in all) if (!oldOrder.contains(jsStr(c['id']))) jsStr(c['id'])];
  return {
    'enabled': val.containsKey('enabled') ? val['enabled'] != false : def['enabled'],
    'source': source,
    'hiddenIds': val.containsKey('hiddenIds') ? unique(val['hiddenIds']) : def['hiddenIds'],
    'order': val.containsKey('order') ? order : def['order'],
    'metrics': key == 'todayBalance' && val['metrics'] == 'visible' ? 'visible' : 'all',
  };
}

/// `mf508VisibleCategories`.
List<Map<String, dynamic>> visiblePanelCategories(Map<String, dynamic> state, String key, [Set<String>? seen]) {
  final all = asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().where((c) => c['id'] != null).toList();
  List<Map<String, dynamic>> enabled() => all.where((c) => c['enabled'] != false).toList();
  const panels = ['todayBalance', 'libraryOverview'];
  final visited = seen ?? <String>{};
  if (!panels.contains(key) || visited.contains(key)) return enabled();
  visited.add(key);
  final cfg = balancePanel(state, key);
  // mf508NormalizeBoth: a circular link resolves to the categories list.
  var source = jsStr(cfg['source']);
  if (key == 'libraryOverview' && source == 'todayBalance' && balancePanel(state, 'todayBalance')['source'] == 'libraryOverview') {
    source = 'categories';
  }
  if (source == 'system') return Recommender(state, now: 0).schedulerCategories();
  if (source == 'custom') {
    final hidden = asList(cfg['hiddenIds']).map(jsStr).toSet();
    final byId = {for (final c in all) jsStr(c['id']): c};
    return [for (final id in asList(cfg['order']).map(jsStr)) if (byId.containsKey(id) && !hidden.contains(id)) byId[id]!];
  }
  if (panels.contains(source)) return visiblePanelCategories(state, source, visited);
  return enabled();
}

/// The base `overallCategoryStatus`.
String overallCategoryStatus(Category cat, List<dynamic> sessions, int now) {
  final rows = sessions
      .map(asMap)
      .whereType<Map<String, dynamic>>()
      .where((s) => jsStr(s['categoryId']) == cat.id && s['status'] != 'skipped' && jsNum(s['minutes']) > 0)
      .toList();
  if (rows.isEmpty) return 'healthy';
  double time(Map<String, dynamic> s) {
    final ts = jsNum(s['timestamp']);
    if (ts > 0) return ts;
    final d = DateTime.tryParse(jsStr(s['date']));
    return d == null ? double.nan : d.millisecondsSinceEpoch.toDouble();
  }

  stableSort(rows, (a, b) {
    final x = time(a), y = time(b);
    if (x.isNaN || y.isNaN) return 0;
    return x.compareTo(y);
  });
  final first = time(rows.first), last = time(rows.last);
  final spanDays = math.max(3.0, (last - first) / 86400000);
  final total = rows.fold<double>(0, (a, s) => a + jsNum(s['minutes']));
  final target = cat.target ?? double.nan;
  final expectedPerDay = target * cat.minutesPerUnit * 2.2 / 3;
  final expected = expectedPerDay * spanDays;
  final ratio = expected > 0 ? total / expected : 0.0;
  final dSince = last.isNaN ? double.infinity : (now - last) / 86400000;
  if (dSince >= 6) return 'neglected';
  if (ratio >= 1.6) return 'overused';
  if (dSince >= 2.2) return 'due';
  return 'healthy';
}

/// `v43BalanceGuidance` (plain text) + the v265 label.
({String label, String text}) balanceGuidance(Recommender r, Category cat, String today, String overall) {
  final a = r.suggestedAmount(cat.raw);
  final mid = math.max(1, jsRound((a.low + a.high) / 2).toInt());
  final mpu = cat.minutesPerUnit;
  final mins = math.max(0, jsRound(mid * mpu).toInt());
  final t = cat.target;
  final num base = math.max(1, (t == null || t == 0 || t.isNaN) ? 1 : t);
  final baseMin = jsRound((base * mpu).toDouble()).toInt();
  String unit(num n) => unitLabel(cat.unit, n);
  String text;
  if (today == 'overused' || a.direction == 'reduced') {
    final less = math.max(0, base - mid), lessMin = math.max(0, baseMin - mins);
    text = 'If this rotates now, about $mid ${unit(mid)} (~$mins min), ${_n(less)} ${unit(less)} / ~$lessMin min less than the normal target.';
  } else {
    final range = a.low == a.high ? '${a.low}' : '${a.low}–${a.high}';
    final lowMin = jsRound(a.low * mpu).toInt();
    final minRange = a.low == a.high ? '$lowMin' : '$lowMin–${jsRound(a.high * mpu).toInt()}';
    text = today == 'neglected' || today == 'due' || a.direction == 'increased'
        ? 'About $range ${unit(mid)} (~$minRange min) if selected now. This grows or shrinks with the scheduler\'s live balance calculation.'
        : 'About $range ${unit(mid)} (~$minRange min) if selected now.';
  }
  var label = 'Balanced rotation';
  if (today == 'overused') {
    label = 'Ease off today';
  } else if (today == 'due' || today == 'neglected' || overall == 'due' || overall == 'neglected') {
    label = 'Needs attention';
  } else if (today == 'healthy' && overall == 'healthy') {
    label = 'On track';
  }
  return (label: label, text: text);
}

String _n(num v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

class BalanceRow {
  BalanceRow(this.cat, this.amount, this.today, this.overall, this.target, this.label, this.text);
  final Category cat;
  final double amount;
  final String today, overall;
  final double target;
  final String label, text;
  int get pct => (amount / target * 100).round().clamp(0, 100).toInt();
}

class TodayBalance {
  TodayBalance(this.rows, this.units, this.minutes, this.streak, this.unrated, this.scopeVisible, this.todayCounts, this.overallCounts, this.subjects);
  final List<BalanceRow> rows;
  final double units, minutes;
  final int streak, unrated;
  final bool scopeVisible;
  final Map<String, int> todayCounts, overallCounts;
  final int subjects;
}

/// `v265BalanceMarkup` + `mf508HealthSummaryHtml`, as data.
TodayBalance todayBalance(Map<String, dynamic> state, int now) {
  final sessions = asList(state['sessions']);
  final today = isoDateUtc(now);
  final todays = sessions.map(asMap).whereType<Map<String, dynamic>>().where((s) => s['date'] == today).toList();
  final r = Recommender(state, now: now);
  final cats = visiblePanelCategories(state, 'todayBalance').map(Category.new).toList();
  // Each status only looks at its own category's logs: hand each one just
  // those (same order), and work each out once.
  final byCategory = <String, List<dynamic>>{};
  for (final raw in sessions) {
    final m = asMap(raw);
    if (m != null) (byCategory[jsStr(m['categoryId'])] ??= []).add(m);
  }
  final todayStatus = <String, String>{}, overallStatus = <String, String>{};
  String statusToday(Category c) => todayStatus[c.id] ??= categoryStatus(c, byCategory[c.id] ?? const [], now);
  String statusOverall(Category c) => overallStatus[c.id] ??= overallCategoryStatus(c, byCategory[c.id] ?? const [], now);
  final rows = <BalanceRow>[];
  for (final cat in cats) {
    final amt = todays.where((s) => jsStr(s['categoryId']) == cat.id && s['status'] != 'skipped').fold<double>(0, (a, s) => a + jsNum(s['actualAmount']));
    final t = statusToday(cat), o = statusOverall(cat);
    final target = math.max(1.0, cat.target == null || cat.target == 0 ? 1.0 : cat.target!);
    final g = balanceGuidance(r, cat, t, o);
    rows.add(BalanceRow(cat, amt, t, o, target, g.label, g.text));
  }
  final visible = balancePanel(state, 'todayBalance')['metrics'] == 'visible';
  final ids = cats.map((c) => c.id).toSet();
  final consumed = todays.where((s) => s['status'] != 'skipped' && (!visible || ids.contains(jsStr(s['categoryId'])))).toList();
  final units = consumed.fold<double>(0, (a, s) => a + jsNum(s['actualAmount']));
  final minutes = consumed.fold<double>(0, (a, s) => a + jsNum(s['minutes']));
  final map = buildStreakMap(sessions);
  final streak = map[today] ?? 0;
  final unrated = asList(state['library']).map(asMap).where((i) => !(jsNum(i?['rating']) > 0)).length;
  final subjects = visible
      ? cats
      : asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().where((c) => c['id'] != null).map(Category.new).toList();
  Map<String, int> count(String Function(Category) f) {
    final out = {'healthy': 0, 'due': 0, 'neglected': 0, 'overused': 0};
    for (final c in subjects) {
      final s = f(c);
      if (out.containsKey(s)) out[s] = out[s]! + 1;
    }
    return out;
  }

  return TodayBalance(
    rows,
    units,
    minutes,
    streak,
    unrated,
    visible,
    count(statusToday),
    count(statusOverall),
    subjects.length,
  );
}

// ---- On This Day ------------------------------------------------------------------

class OtdEvent {
  OtdEvent(this.kind, this.title, this.libraryId, this.categoryId, this.qty, this.minutes, this.item, this.timestamp, this.years);
  final String kind; // started | logged | finished
  final String title;
  final String? libraryId, categoryId;
  double qty, minutes;
  final Map<String, dynamic>? item;
  final double timestamp;
  int years;
}

/// `v159BuildOnThisDayModel`: events on today's date in earlier years, grouped by years ago.
List<({int years, List<OtdEvent> rows})> onThisDay(Map<String, dynamic> state, DateTime now) {
  final library = asList(state['library']).map(asMap).whereType<Map<String, dynamic>>().toList();
  final byId = <String, Map<String, dynamic>>{};
  final byTitle = <String, List<Map<String, dynamic>>>{};
  for (final item in library) {
    if (jsTruthy(item['id'])) byId[jsStr(item['id'])] = item;
    final key = cleanTitle(item['title']).toLowerCase();
    if (key.isNotEmpty) (byTitle[key] ??= []).add(item);
  }
  Map<String, dynamic>? find(Object? id, Object? title, Object? categoryId) {
    if (jsTruthy(id) && byId.containsKey(jsStr(id))) return byId[jsStr(id)];
    final rows = byTitle[cleanTitle(title).toLowerCase()] ?? const [];
    if (rows.length == 1) return rows.first;
    final cat = rows.where((x) => jsStr(x['categoryId']) == jsStr(categoryId)).toList();
    return cat.length == 1 ? cat.first : null;
  }

  final groups = <int, List<OtdEvent>>{};
  void add(DateTime d, OtdEvent Function(int years) make) {
    final years = now.year - d.year;
    if (years < 1 || d.month != now.month || d.day != now.day) return;
    (groups[years] ??= []).add(make(years));
  }

  for (final s in asList(state['sessions']).map(asMap).whereType<Map<String, dynamic>>()) {
    if (s['status'] == 'skipped') continue;
    final key = sessionDayKey(s);
    DateTime? d;
    if (key.isNotEmpty) d = DateTime.tryParse('${key}T12:00:00');
    if (d == null && jsNum(s['timestamp']) > 0) d = DateTime.fromMillisecondsSinceEpoch(jsNum(s['timestamp']).toInt());
    if (d == null) continue;
    final years = now.year - d.year;
    if (years < 1 || d.month != now.month || d.day != now.day) continue;
    final raw = asList(s['titles']).map(asMap).whereType<Map<String, dynamic>>().where((t) => jsTruthy(t['title'])).toList();
    final titles = raw.isNotEmpty
        ? raw
        : (jsTruthy(s['title'])
            ? [<String, dynamic>{'title': s['title'], 'libraryId': s['libraryId'], 'qty': s['actualAmount'] ?? 0, 'categoryId': s['categoryId']}]
            : <Map<String, dynamic>>[]);
    if (titles.isEmpty) continue;
    double qtyOf(Map<String, dynamic> t) => math.max(0, jsNum(t['qty'] ?? t['amount'] ?? 0));
    final totalQty = titles.fold<double>(0, (n, t) => n + qtyOf(t));
    final sessionMinutes = math.max(0.0, jsNum(s['minutes']));
    final stamp = d.millisecondsSinceEpoch.toDouble();
    for (final t in titles) {
      final qty = qtyOf(t);
      var minutes = math.max(0.0, jsNum(t['minutes']));
      if (minutes == 0 && sessionMinutes > 0) {
        if (titles.length == 1) {
          minutes = sessionMinutes;
        } else if (totalQty > 0) {
          minutes = sessionMinutes * (qty / totalQty);
        } else {
          minutes = sessionMinutes / titles.length;
        }
      }
      final item = find(t['libraryId'], t['title'], t['categoryId'] ?? s['categoryId']);
      add(d, (y) => OtdEvent('logged', cleanTitle(t['title']), jsStr(item?['id'] ?? t['libraryId']).isEmpty ? null : jsStr(item?['id'] ?? t['libraryId']),
          jsStr(item?['categoryId'] ?? t['categoryId'] ?? s['categoryId']), qty, minutes, item, stamp, y));
    }
  }
  for (final item in library) {
    final title = cleanTitle(item['title']);
    if (title.isEmpty) continue;
    for (final k in const [('startedAt', 'started'), ('completedAt', 'finished')]) {
      final ts = jsNum(item[k.$1]);
      if (ts <= 0) continue;
      final d = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
      add(d, (y) => OtdEvent(k.$2, title, jsStr(item['id']).isEmpty ? null : jsStr(item['id']), jsStr(item['categoryId']), 0, 0, item, ts, y));
    }
  }
  const priority = {'started': 0, 'logged': 1, 'finished': 2};
  final out = <({int years, List<OtdEvent> rows})>[];
  for (final years in groups.keys.toList()..sort()) {
    final raw = groups[years]!;
    stableSort(raw, (a, b) {
      final t = a.timestamp.compareTo(b.timestamp);
      return t != 0 ? t : priority[a.kind]! - priority[b.kind]!;
    });
    final merged = <OtdEvent>[];
    final byKey = <String, OtdEvent>{};
    for (final x in raw) {
      final identity = x.libraryId != null ? 'id:${x.libraryId}' : 'title:${x.title.toLowerCase()}::${x.categoryId ?? ''}';
      final key = '${x.kind}::$identity';
      var m = byKey[key];
      if (m == null) {
        m = OtdEvent(x.kind, x.title, x.libraryId, x.categoryId, 0, 0, x.item, x.timestamp, years);
        byKey[key] = m;
        merged.add(m);
      }
      m.qty += math.max(0, x.qty);
      m.minutes += math.max(0, x.minutes);
    }
    if (merged.isNotEmpty) out.add((years: years, rows: merged));
  }
  return out;
}
