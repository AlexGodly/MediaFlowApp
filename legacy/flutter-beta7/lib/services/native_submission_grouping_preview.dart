import 'dart:math' as math;

/// Read-only subset of original 008-session-flow.js submitLog grouping.
/// This is NOT an authenticated History record, task rotation, or XP award.
class NativeGroupingInput {
  const NativeGroupingInput({
    required this.categoryId,
    required this.quantity,
    required this.minutesPerUnit,
    this.itemizedSeconds,
  });
  final String categoryId;
  final double quantity, minutesPerUnit;
  final int? itemizedSeconds;
}

class NativeGroupingRow {
  const NativeGroupingRow({
    required this.categoryId,
    required this.quantity,
    required this.minutes,
    required this.status,
    required this.recommended,
    required this.skippedRecommendation,
  });
  final String categoryId, status;
  final double quantity, minutes;
  final bool recommended, skippedRecommendation;
  bool get maySubmit => false;
  double? get exactXp => null;
}

abstract final class NativeSubmissionGroupingPreview {
  /// Categories appear in first-seen order, as in the source Map.
  /// Times are weighted and rounded for all but the last category. For
  /// itemized entries, exact seconds take precedence over global minutes.
  static List<NativeGroupingRow> group({
    required String assignedCategoryId,
    required double target,
    required double minutes,
    required Iterable<NativeGroupingInput> inputs,
    bool itemized = false,
  }) {
    if (assignedCategoryId.isEmpty || !target.isFinite ||
        target < 0 || !minutes.isFinite || minutes < 0 ||
        minutes > 999999) {
      throw const FormatException('Invalid recommendation or duration');
    }
    final order = <String>[];
    final amounts = <String, double>{};
    final weights = <String, double>{};
    final durations = <String, int>{};
    for (final item in inputs) {
      if (item.categoryId.isEmpty ||
          !item.quantity.isFinite || item.quantity < 0 ||
          !item.minutesPerUnit.isFinite || item.minutesPerUnit < 0 ||
          item.itemizedSeconds != null &&
              (item.itemizedSeconds! < 0 ||
               item.itemizedSeconds! > 864000000)) {
        throw const FormatException('Invalid grouped logging entry');
      }
      if (!amounts.containsKey(item.categoryId)) {
        order.add(item.categoryId);
        amounts[item.categoryId] = 0;
        weights[item.categoryId] = 0;
        durations[item.categoryId] = 0;
      }
      amounts[item.categoryId] = amounts[item.categoryId]! + item.quantity;
      weights[item.categoryId] = weights[item.categoryId]! +
          item.quantity * math.max(1, item.minutesPerUnit);
      if (itemized) {
        if (item.itemizedSeconds == null) {
          throw const FormatException('Missing itemized duration');
        }
        durations[item.categoryId] = durations[item.categoryId]! +
            item.itemizedSeconds!;
      }
    }
    final totalWeight = math.max(1.0,
        weights.values.fold<double>(0, (sum, value) => sum + value));
    final result = <NativeGroupingRow>[];
    var minutesLeft = minutes;
    for (var i = 0; i < order.length; i++) {
      final id = order[i];
      final amount = amounts[id]!;
      final isAssigned = id == assignedCategoryId;
      final groupMinutes = itemized
          ? durations[id]! / 60
          : i == order.length - 1
            ? minutesLeft
            : math.min(minutesLeft,
                (minutes * (weights[id]! / totalWeight)).roundToDouble()).toDouble();
      minutesLeft = math.max(0.0, minutesLeft - groupMinutes).toDouble();
      String status = 'logged';
      if (isAssigned) {
        if (amount < target) {
          status = 'partial';
        } else if (amount > target) {
          status = 'over';
        } else {
          status = 'complete';
        }
      }
      result.add(NativeGroupingRow(
        categoryId: id, quantity: amount, minutes: groupMinutes,
        status: status, recommended: isAssigned,
        skippedRecommendation: false,
      ));
    }
    // Source appends a separate skipped row when assigned category wasn't
    // positively consumed, even if other categories did receive consumption.
    if (!result.any((g) =>
        g.categoryId == assignedCategoryId && g.quantity > 0)) {
      result.add(NativeGroupingRow(
        categoryId: assignedCategoryId, quantity: 0, minutes: 0,
        status: 'skipped', recommended: true,
        skippedRecommendation: true,
      ));
    }
    return List.unmodifiable(result);
  }
}
