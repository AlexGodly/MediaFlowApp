// The website's floating Task Progress (v397 `mf397ReadState`): how much of the
// current task's goal the open, unsaved log covers. Read-only.

import 'dart:math' as math;

import '../util/js.dart';

class TaskProgress {
  TaskProgress({
    required this.categoryName,
    required this.amount,
    required this.low,
    required this.high,
    required this.denominator,
    required this.status,
    required this.pct,
    this.unit = '',
    this.warn = false,
    this.finish = 'minimum',
  });
  final String categoryName;

  /// The task's unit (episodes, chapters, …) for "3 / 5 episodes".
  final String unit;
  final double amount;
  final int low, high;
  final double denominator;
  final String status;

  /// The percentage shown: against the goal's minimum or maximum ([finish],
  /// website v565 `mf565TaskFinish`); past 100% only with "Count past 100%".
  final double pct;

  /// Past the goal's maximum and the setting shows it (warning colour).
  final bool warn;

  /// 'minimum' (default) or 'maximum'.
  final String finish;

  bool get reached => amount >= low && amount <= high;
  bool get over => amount > high;

  /// Where the goal's minimum sits on the bar (0–1): only when the bar
  /// finishes at the maximum and the goal is a range.
  double? get marker => finish != 'maximum' || low == high ? null : low / high;
}

/// Null when the card is hidden: no open log for the current task, or no added
/// title from the task's category yet.
TaskProgress? taskProgress({
  required Map<String, dynamic> task,
  required Map<String, dynamic> logDraft,
  required Map<String, dynamic>? Function(Object? libraryId) libraryItem,
  required String categoryName,
  required String categoryType,
  required String unit,
  String finish = 'minimum',
  String over = 'count',
  double Function(Map<String, dynamic> entry, double amount)? toCategory,
}) {
  final categoryId = jsStr(task['categoryId']);
  final itemized = logDraft['v369Interface'] == 'itemized';
  final matching = <Map<String, dynamic>>[];
  for (final raw in asList(logDraft['entries'])) {
    final e = asMap(raw);
    if (e == null) continue;
    final item = libraryItem(jsStr(e['libraryId']));
    if (item != null && jsStr(item['categoryId']) == categoryId) matching.add(e);
  }
  if (matching.isEmpty) return null;
  final amount = matching.fold<double>(0, (sum, e) {
    final raw = itemized ? (e['v369Units'] is List ? (e['v369Units'] as List).length.toDouble() : 0.0) : math.max(0, jsNum(e['qty'])).toDouble();
    // v565: a title with its own unit counts in the category's unit.
    return sum + (toCategory == null ? raw : toCategory(e, raw));
  });
  double safe(Object? n) {
    final v = jsNumOrNull(n);
    return v == null || !v.isFinite ? 0.0 : math.max(0.0, v);
  }

  final lowRaw = task['low'] ?? task['targetMid'] ?? 1;
  final low = math.max(1, jsRound(safe(lowRaw)).toInt());
  final highRaw = task['high'] ?? task['targetMid'] ?? low;
  final high = math.max(low, jsRound(safe(highRaw)).toInt());
  final finishAt = finish == 'maximum' ? 'maximum' : 'minimum';
  final overMode = over == 'warning' || over == 'status' ? over : 'count';
  final double denominator = finishAt == 'minimum'
      ? low.toDouble()
      : high == low
          ? low.toDouble()
          : amount <= low
              ? low.toDouble()
              : math.min(amount, high.toDouble());
  final words = [categoryType, categoryName, unit].join(' ');
  final reading = RegExp(r'read|chapter|page|book|novel|comic|manga|manhwa|manhua|issue|volume', caseSensitive: false).hasMatch(words);
  final watching = RegExp(r'watch|episode|movie|anime|video|tv|film', caseSensitive: false).hasMatch(words);
  final prefix = reading ? 'Overread' : watching ? 'Overwatched' : 'Overconsumed';
  final status = amount == 0
      ? 'Ready to log'
      : amount < low
          ? 'In progress'
          : amount == low
              ? 'Goal reached'
              : amount < high
                  ? 'Within target range'
                  : amount == high
                      ? 'Recommended maximum reached'
                      : prefix;
  return TaskProgress(
    categoryName: categoryName,
    amount: amount,
    low: low,
    high: high,
    denominator: denominator,
    status: status,
    pct: () {
      final end = finishAt == 'maximum' ? high : low;
      final raw = end > 0 ? amount / end * 100 : 0.0;
      return math.max(0, overMode == 'count' ? raw : math.min(100, raw)).toDouble();
    }(),
    warn: overMode != 'status' && amount > high,
    finish: finishAt,
    unit: unit,
  );
}
