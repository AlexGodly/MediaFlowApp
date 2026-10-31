// XP rules ported from the MediaFlow website (v554): levelingSettings(),
// calculateConsumptionXP(), categoryStatus(), the v149 day streak and the
// v334/v348 reward settings.

import '../state/models.dart';
import '../util/js.dart';

const Map<String, num> _defaultUnitXP = {
  'episodes': 10, 'chapters': 3, 'issues': 6, 'movies': 30, 'sessions': 12, 'videos': 9,
  'pages': 1, 'volumes': 14, 'tracks': 2, 'albums': 18, 'levels': 10, 'missions': 10,
  'matches': 12, 'lessons': 8, 'items': 5,
};
const Map<String, num> _defaultRotation = {'neglected': 10, 'due': 8, 'healthy': 5, 'overused': 2};
const Map<String, num> _defaultRepeatUnitXP = {
  'episodes': 10, 'chapters': 3, 'issues': 6, 'movies': 30, 'sessions': 6, 'videos': 5,
  'pages': 1, 'volumes': 7, 'tracks': 1, 'albums': 9, 'levels': 5, 'missions': 5,
  'matches': 6, 'lessons': 4, 'items': 3,
};
const Map<String, num> _defaultScalars = {
  'minuteXP': 1,
  'libraryAdditionXP': 25,
  'completionXP': 50,
  'loggingCompletionBonusXP': 25,
  'fullRepeatXP': 50,
  // v348
  'batchLogXP': 15,
  // v334
  'firstTitleStartXP': 40,
};

class Leveling {
  Leveling(Map<String, dynamic> state) : _l = asMap(asMap(state['settings'])?['leveling']) ?? const {};
  final Map<String, dynamic> _l;

  bool get enabled => _l['enabled'] != false;
  bool get globalStreakEnabled => _l['globalStreakMultiplierEnabled'] != false;

  double _scalar(String key) {
    // levelingSettings(): stored value overrides the default when present.
    if (_l.containsKey(key)) return jsNum(_l[key]);
    return (_defaultScalars[key] ?? 0).toDouble();
  }

  double get minuteXP => _scalar('minuteXP');
  double get completionXP => jsRound(_scalar('completionXP')).clamp(0, double.infinity).toDouble();
  double get loggingCompletionBonusXP =>
      jsRound(_scalar('loggingCompletionBonusXP')).clamp(0, double.infinity).toDouble();

  double unitXP(String unit) {
    final custom = asMap(_l['unitXP']);
    if (custom != null && custom.containsKey(unit)) return jsNum(custom[unit]);
    return (_defaultUnitXP[unit] ?? 0).toDouble();
  }

  double repeatUnitXP(String unit) {
    final custom = asMap(_l['repeatUnitXP']);
    if (custom != null && custom.containsKey(unit)) return jsNum(custom[unit]);
    return (_defaultRepeatUnitXP[unit] ?? 0).toDouble();
  }

  double get fullRepeatXP {
    final v = jsNumFromKey(_l, 'fullRepeatXP');
    return (v ?? 50).clamp(0, double.infinity).toDouble();
  }

  /// `xpRotationMultiplier`: missing/blank → ×1, invalid → ×1, 0 is valid.
  double rotationMultiplier(String status) {
    final custom = asMap(_l['rotationMultiplier']);
    Object? raw;
    if (custom != null && custom.containsKey(status)) {
      raw = custom[status];
    } else {
      raw = _defaultRotation[status];
    }
    if (raw == null || raw == '') return 1;
    final v = jsNumOrNull(raw);
    return v != null && v >= 0 ? v : 1.0;
  }

  /// `v348Rate` / `v334Reward`: `Number(settings[key] ?? DEFAULT)`, clamped 0..100000.
  double reward(String key) {
    final raw = _l[key] ?? _defaultScalars[key];
    final v = jsNumOrNull(raw);
    if (v == null) return (_defaultScalars[key] ?? 0).toDouble();
    return v.clamp(0, 100000).toDouble();
  }

  /// `calculateConsumptionXP(cat, amount, minutes, status).xp`
  double consumptionXP(Category cat, double amount, double minutes, String status) {
    if (!enabled || status == 'skipped' || amount <= 0 || minutes <= 0) return 0;
    final double roundedMinutes = jsRound(minutes) < 0 ? 0.0 : jsRound(minutes);
    final double perMinute = minuteXP < 0 ? 0.0 : minuteXP;
    final double roundedAmount = jsRound(amount) < 0 ? 0.0 : jsRound(amount);
    final double base = roundedMinutes * perMinute + roundedAmount * unitXP(cat.unit);
    final double xp = jsRound(base * rotationMultiplier(status));
    return xp < 0 ? 0.0 : xp;
  }

  /// `v149StreakMultiplier` with the v348 global switch.
  double streakMultiplier(num streak) {
    if (!globalStreakEnabled) return 1;
    if (!enabled) return 1;
    final int n = streak.floor() < 0 ? 0 : streak.floor();
    if (n <= 1) return 1;
    return jsRound((1 + 0.10 * jsLog2(n.toDouble())) * 100) / 100;
  }
}

/// `v149DateKeyFromSession`.
String sessionDayKey(Map<String, dynamic> s) {
  final raw = jsStr(s['date']).trim();
  if (isIsoDay(raw)) return raw;
  final ts = jsNum(s['timestamp']);
  if (ts > 0) return isoDateUtc(ts.toInt());
  return '';
}

/// `v149BuildStreakMap`: consecutive-day streak reached on each logged day.
Map<String, int> buildStreakMap(List<dynamic> sessions) {
  final days = <String>{};
  for (final raw in sessions) {
    final s = asMap(raw);
    if (s == null || s['status'] == 'skipped') continue;
    final key = sessionDayKey(s);
    if (key.isNotEmpty) days.add(key);
  }
  final sorted = days.toList()..sort();
  final map = <String, int>{};
  for (final key in sorted) {
    map[key] = (map[shiftDayKey(key, -1)] ?? 0) + 1;
  }
  return map;
}

/// `v149ProspectiveTodayStreak`.
int prospectiveTodayStreak(List<dynamic> sessions, int nowMs) {
  final map = buildStreakMap(sessions);
  final today = isoDateUtc(nowMs);
  if (map.containsKey(today)) return map[today] == 0 ? 1 : map[today]!;
  return (map[shiftDayKey(today, -1)] ?? 0) + 1;
}

/// `v348Multiplier`: today's streak multiplier used for ledger awards.
double awardMultiplier(Leveling l, List<dynamic> sessions, int nowMs) {
  if (!l.enabled || !l.globalStreakEnabled) return 1;
  final m = l.streakMultiplier(prospectiveTodayStreak(sessions, nowMs));
  return m < 1 ? 1 : m;
}

/// `categoryStatus(cat)` — the category "health" that scales log XP.
String categoryStatus(Category cat, List<dynamic> sessions, int nowMs) {
  Map<String, dynamic>? last;
  double lastTs = 0;
  for (final raw in sessions) {
    final s = asMap(raw);
    if (s == null || jsStr(s['categoryId']) != cat.id) continue;
    final ts = jsNum(s['timestamp']);
    if (last == null || ts > lastTs) {
      last = s;
      lastTs = ts;
    }
  }
  final dSince = (last == null || lastTs == 0) ? double.infinity : (nowMs - lastTs) / 86400000;
  final cutoff = nowMs - 72 * 3600000;
  var min72 = 0.0;
  var todayAmt = 0.0;
  final today = isoDateUtc(nowMs);
  for (final raw in sessions) {
    final s = asMap(raw);
    if (s == null || jsStr(s['categoryId']) != cat.id || s['status'] == 'skipped') continue;
    if (jsNum(s['timestamp']) >= cutoff) min72 += jsNum(s['minutes']);
    if (s['date'] == today) todayAmt += jsNum(s['actualAmount']);
  }
  final target = cat.target;
  final expected3d = target == null ? double.nan : target * cat.minutesPerUnit * 2.2;
  final double satRatio = expected3d > 0 ? min72 / expected3d : 0.0;
  if (todayAmt > 0 && satRatio >= 1.6) return 'overused';
  if (dSince >= 6) return 'neglected';
  if (dSince >= 2.2) return 'due';
  return 'healthy';
}

/// `v149AnnotateSessionStreakXP`: streak fields on every History log.
void annotateStreakXP(Map<String, dynamic> state, Leveling l) {
  final sessions = asList(state['sessions']);
  final map = buildStreakMap(sessions);
  AccountView? view; // built only if a legacy log has no stored XP
  for (final raw in sessions) {
    final s = asMap(raw);
    if (s == null) continue;
    if (s['status'] == 'skipped') {
      s['streakAtLog'] = 0;
      s['streakMultiplier'] = 1;
      s['streakBaseXP'] = 0;
      s['streakBonusXP'] = 0;
      s['xpWithStreak'] = 0;
      s['streakXPVersion'] = 1;
      continue;
    }
    final key = sessionDayKey(s);
    final streak = key.isNotEmpty ? (map[key] ?? 1) : 1;
    final multiplier = l.streakMultiplier(streak);
    final rawXP = jsRound(_storedXP(s, l, () => view ??= AccountView(state)));
    final base = rawXP < 0 ? 0.0 : rawXP;
    final total = jsRound(base * multiplier);
    s['streakAtLog'] = streak;
    s['streakMultiplier'] = jsOut(multiplier);
    s['streakBaseXP'] = jsOut(base);
    s['streakBonusXP'] = jsOut(total - base < 0 ? 0.0 : total - base);
    s['xpWithStreak'] = jsOut(total < 0 ? 0.0 : total);
    s['streakXPVersion'] = 1;
  }
}

/// `v150BaseSessionXP` (as extended by v165): the log's stored XP — or, when
/// that is 0/missing, a recalculation — plus its recommendation "respect" bonus.
double _storedXP(Map<String, dynamic> s, Leveling l, AccountView Function() view) {
  if (s['status'] == 'skipped') return 0;
  double base = 0;
  final stored = jsNumOrNull(s['xp']);
  if (stored != null && stored > 0) {
    base = stored;
  } else if (jsNum(s['actualAmount']) > 0 && jsNum(s['minutes']) > 0) {
    final health = jsStr(s['healthStatus']).isEmpty ? 'healthy' : jsStr(s['healthStatus']);
    base = l.consumptionXP(view().category(jsStr(s['categoryId'])), jsNum(s['actualAmount']), jsNum(s['minutes']), health);
  }
  final respect = jsRound(jsNum(s['v165RespectBonusXP']));
  final total = base + (respect < 0 ? 0.0 : respect);
  return total < 0 ? 0.0 : total;
}
