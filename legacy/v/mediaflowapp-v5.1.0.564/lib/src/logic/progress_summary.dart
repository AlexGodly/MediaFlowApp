// The website sidebar's Leveling and Day Streak figures (render-shell
// `mediaFlowLevelInfo`, `computeDayStreak`, `v149StreakMultiplier`; kept live
// by v385). Read-only: nothing here changes the account.

import 'leveling.dart';
import 'stats.dart';
import '../util/js.dart';

class ProgressSummary {
  ProgressSummary({required this.level, required this.streak, required this.multiplier});
  final LevelInfo level;
  final int streak;
  final double multiplier;

  double get toNext => level.needed - level.current;

  /// "152,765 XP to Level 367", or "Ready for Level 367".
  bool get readyForNext => toNext <= 0;
}

/// `computeDayStreak`: days in a row, ending today (UTC, like the website's
/// `toISOString`), with at least one non-skipped log. 0 when today has none.
int computeDayStreak(List<dynamic> sessions, int nowMs) {
  final days = <String>{};
  for (final raw in sessions) {
    final s = asMap(raw);
    if (s == null || s['status'] == 'skipped') continue;
    days.add(jsStr(s['date']));
  }
  var streak = 0;
  var day = isoDateUtc(nowMs);
  while (days.contains(day)) {
    streak++;
    day = shiftDayKey(day, -1);
  }
  return streak;
}

ProgressSummary progressSummary(Map<String, dynamic> state, int nowMs) {
  final sessions = asList(state['sessions']);
  final streak = computeDayStreak(sessions, nowMs);
  return ProgressSummary(
    level: levelInfo(xpMetrics(state).total),
    streak: streak,
    multiplier: Leveling(state).streakMultiplier(streak),
  );
}

// The total XP walks every log and Library title, so it is worked out once per
// change to the account rather than on every redraw. Saving a draft does not
// change savedAt, sessions or the Library, so typing in the form reuses it.
Object? _cacheState;
String _cacheKey = '';
ProgressSummary? _cache;

ProgressSummary cachedProgressSummary(Map<String, dynamic> state, int nowMs) {
  final key = [
    jsNum(state['savedAt']),
    asList(state['sessions']).length,
    asList(state['library']).length,
    isoDateUtc(nowMs),
  ].join('|');
  final hit = _cache;
  if (hit != null && identical(_cacheState, state) && key == _cacheKey) return hit;
  final fresh = progressSummary(state, nowMs);
  _cacheState = state;
  _cacheKey = key;
  _cache = fresh;
  return fresh;
}
