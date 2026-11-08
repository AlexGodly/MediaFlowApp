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
  });
  final String categoryName;

  /// The task's unit (episodes, chapters, …) for "3 / 5 episodes".
  final String unit;
  final double amount;
  final int low, high;
  final double denominator;
  final String status;

  /// 0–100, measured against the top of the goal ([high]).
  final double pct;

  bool get reached => amount >= low && amount <= high;
  bool get over => amount > high;

  /// Where the goal's minimum sits on the bar (0–1); null when min == max.
  double? get marker => low == high ? null : low / high;
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
    if (itemized) return sum + (e['v369Units'] is List ? (e['v369Units'] as List).length : 0);
    return sum + math.max(0, jsNum(e['qty']));
  });
  double safe(Object? n) {
    final v = jsNumOrNull(n);
    return v == null || !v.isFinite ? 0.0 : math.max(0.0, v);
  }

  final lowRaw = task['low'] ?? task['targetMid'] ?? 1;
  final low = math.max(1, jsRound(safe(lowRaw)).toInt());
  final highRaw = task['high'] ?? task['targetMid'] ?? low;
  final high = math.max(low, jsRound(safe(highRaw)).toInt());
  final double denominator = high == low
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
    pct: math.max(0, math.min(100, amount / high * 100)).toDouble(),
    unit: unit,
  );
}
