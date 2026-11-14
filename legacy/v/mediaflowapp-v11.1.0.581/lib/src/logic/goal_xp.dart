// Task goal XP (website v580, 433-v580-goal-xp.js).
//
// A recommendation ("Consume 5–7 issues") pays XP for its goal:
//   - reaching the minimum (task.low):  +100 XP (setting)
//   - reaching the maximum (task.high): +300 XP more (setting)
//   - each unit past the maximum:       +10 XP, up to +100 (settings)
// Once per task, by any log (Logging, Log any title / Batch Log). The task's
// progress is everything logged in its category since the task was created;
// each part is paid once, on the first new log in the task's category:
//   session.mf580GoalXP / mf580GoalTaskId / mf580Goal {min,max,extra,low,high,amount,version}
// Like System Respect XP it is part of the session's base XP (the day streak
// multiplies it). Settings: settings.mf580GoalXP {enabled,min,max,perExtra,extraCap}.

import 'dart:math' as math;

import '../util/js.dart';

class GoalXPConfig {
  const GoalXPConfig({this.enabled = true, this.min = 100, this.max = 300, this.perExtra = 10, this.extraCap = 100});
  final bool enabled;
  final int min, max, perExtra, extraCap;

  static const defaults = GoalXPConfig();

  /// `mf580GoalCfg`.
  static GoalXPConfig of(Map<String, dynamic>? settings) {
    final c = asMap(settings?['mf580GoalXP']) ?? const <String, dynamic>{};
    // JS `Number.isFinite(Number(v)) ? … : default`: a missing key is the default.
    int n(String key, int d) {
      if (!c.containsKey(key)) return d;
      final x = jsNumOrNull(c[key]);
      return x == null || !x.isFinite ? d : jsRound(x).clamp(0, 100000).toInt();
    }

    return GoalXPConfig(
      enabled: c['enabled'] != false,
      min: n('min', defaults.min),
      max: n('max', defaults.max),
      perExtra: n('perExtra', defaults.perExtra),
      extraCap: n('extraCap', defaults.extraCap),
    );
  }

  Map<String, dynamic> toJson(int modifiedAt) =>
      {'enabled': enabled, 'min': min, 'max': max, 'perExtra': perExtra, 'extraCap': extraCap, 'modifiedAt': modifiedAt};
}

/// `mf580GoalBounds`.
({int low, int high}) goalBounds(Map<String, dynamic>? task) {
  double safe(Object? v) {
    final x = v == null ? null : jsNumOrNull(v);
    return x == null || !x.isFinite ? 0 : math.max(0, x);
  }

  final low = math.max(1, jsRound(safe(task?['low'] ?? task?['targetMid'] ?? 1)).toInt());
  final high = math.max(low, jsRound(safe(task?['high'] ?? task?['targetMid'] ?? low)).toInt());
  return (low: low, high: high);
}

class GoalXP {
  const GoalXP({this.min = 0, this.max = 0, this.extra = 0, this.low = 0, this.high = 0, this.amount = 0});
  final double min, max, extra, amount;
  final int low, high;
  double get total => min + max + extra;
}

/// `mf580GoalTiers`: what the goal is worth at [amount].
GoalXP goalTiers(double amount, int low, int high, GoalXPConfig c) {
  if (!c.enabled) return const GoalXP();
  final a = math.max(0.0, amount);
  return GoalXP(
    min: a >= low ? c.min.toDouble() : 0,
    max: a >= high ? c.max.toDouble() : 0,
    extra: a > high ? math.min(c.extraCap, (a - high).floor() * c.perExtra).toDouble() : 0,
  );
}

/// `mf580TaskAmount`: logged in the task's category since the task was created.
double taskAmount(Map<String, dynamic>? task, List<dynamic> sessions) {
  final cat = jsStr(task?['categoryId']), since = jsNum(task?['createdAt']);
  var n = 0.0;
  for (final raw in sessions) {
    final s = asMap(raw);
    if (s == null || s['status'] == 'skipped' || jsStr(s['categoryId']) != cat) continue;
    if (jsNum(s['timestamp']) < since) continue;
    n += math.max(0.0, jsNum(s['actualAmount']));
  }
  return n;
}

/// `mf580GoalPaid`.
GoalXP goalPaid(Map<String, dynamic>? task, List<dynamic> sessions) {
  final id = jsStr(task?['id']);
  if (id.isEmpty) return const GoalXP();
  double mn = 0, mx = 0, ex = 0;
  for (final raw in sessions) {
    final s = asMap(raw);
    if (s == null || jsStr(s['mf580GoalTaskId']) != id) continue;
    final g = asMap(s['mf580Goal']) ?? const <String, dynamic>{};
    mn += jsNum(g['min']);
    mx += jsNum(g['max']);
    ex += jsNum(g['extra']);
  }
  return GoalXP(min: mn, max: mx, extra: ex);
}

/// `mf580GoalDue`: the goal XP still to pay when the task's amount becomes [amount].
GoalXP goalDue(Map<String, dynamic>? task, double amount, List<dynamic> sessions, GoalXPConfig c, {bool leveling = true}) {
  if (task == null || jsStr(task['id']).isEmpty || jsStr(task['categoryId']).isEmpty || !leveling) return const GoalXP();
  final b = goalBounds(task);
  final t = goalTiers(amount, b.low, b.high, c), paid = goalPaid(task, sessions);
  return GoalXP(
    min: math.max(0, t.min - paid.min),
    max: math.max(0, t.max - paid.max),
    extra: math.max(0, t.extra - paid.extra),
    low: b.low,
    high: b.high,
    amount: amount,
  );
}

/// `mf580ApplyGoal`: after a log is added to `state.sessions`, the goal XP goes
/// on its first new session in the task's category. Returns the XP (before
/// the day streak). The caller re-annotates streak XP afterwards.
double applyGoalXP(Map<String, dynamic> state, Map<String, dynamic>? task, List<Map<String, dynamic>> added, {bool leveling = true}) {
  if (task == null || jsStr(task['id']).isEmpty || jsStr(task['categoryId']).isEmpty) return 0;
  final target = added.where((s) =>
      s['status'] != 'skipped' && jsStr(s['categoryId']) == jsStr(task['categoryId']) && jsNum(s['actualAmount']) > 0).firstOrNull;
  if (target == null || jsStr(target['mf580GoalTaskId']).isNotEmpty) return 0;
  final sessions = asList(state['sessions']);
  final due = goalDue(task, taskAmount(task, sessions), sessions, GoalXPConfig.of(asMap(state['settings'])), leveling: leveling);
  if (due.total <= 0) return 0;
  target['mf580GoalXP'] = jsOut(due.total);
  target['mf580GoalTaskId'] = jsStr(task['id']);
  target['mf580Goal'] = {
    'min': jsOut(due.min),
    'max': jsOut(due.max),
    'extra': jsOut(due.extra),
    'low': due.low,
    'high': due.high,
    'amount': jsOut(due.amount),
    'version': 580,
  };
  return due.total;
}
