import 'dart:math' as math;

import '../data/mediaflow_models.dart';
import 'native_logging_parity_preview.dart';

/// Read-only source audit. Not a new XP reward or an authoritative level.
class NativeHistoryXpParityReport {
  const NativeHistoryXpParityReport({
    required this.historyRows,
    required this.logicalActions,
    required this.skippedRows,
    required this.knownBaseXp,
    required this.knownStreakBonusXp,
    required this.unresolvedXpRows,
    required this.ambiguousGroupRows,
    required this.completedEvidenceCount,
  });

  final int historyRows, logicalActions, skippedRows;
  final int unresolvedXpRows, ambiguousGroupRows, completedEvidenceCount;
  final double knownBaseXp, knownStreakBonusXp;
  double get illustrativeKnownXp => knownBaseXp + knownStreakBonusXp;
  bool get completeXpReconstruction => false;
  bool get mayWriteCloud => false;
}

/// Safe reference subset of v331 logical grouping, v149 History streak bonus
/// and v120 explicit completion evidence. Unknown formulas are not guessed.
abstract final class NativeHistoryXpParity {
  static String logicalKey(MediaFlowSession row, int fallbackCount) {
    if (row.sessionGroupId.isNotEmpty) {
      return 'session:' + row.sessionGroupId;
    }
    if (row.batchGroupId.isNotEmpty) {
      return 'batch:' + row.batchGroupId;
    }
    return 'entry:' + (row.id.isNotEmpty ? row.id : fallbackCount.toString());
  }

  /// The original v331 fallback uses the current DISTINCT count, not index.
  static int logicalActionCount(Iterable<MediaFlowSession> rows) {
    final seen = <String>{};
    for (final row in rows) {
      seen.add(logicalKey(row, seen.length));
    }
    return seen.length;
  }

  /// v149 positive stored XP only. Zero/nonpositive XP needs the original
  /// category, health and configured reward calculation.
  static double? knownBaseXp(MediaFlowSession session) {
    if (session.status == 'skipped') return 0;
    final xp = session.xp;
    if (!xp.isFinite || xp <= 0) return null;
    return xp;
  }

  static double multiplier(int streak, {bool levelingEnabled = true}) =>
      levelingEnabled
          ? NativeLoggingParityPreview.streakMultiplier(streak)
          : 1;

  static double? knownStreakXp(
    MediaFlowSession session,
    Map<String, int> dayStreaks, {
    required bool levelingEnabled,
  }) {
    if (session.status == 'skipped') return 0;
    final base = knownBaseXp(session);
    if (base == null) return null;
    final key = NativeLoggingParityPreview.sessionDate(session);
    final count = key == null ? 1 : (dayStreaks[key] ?? 1);
    return math.max(0,
        (base * multiplier(count, levelingEnabled: levelingEnabled)).round()
        - base);
  }

  static Map<String, int> streakMap(Iterable<MediaFlowSession> rows) {
    final days = <String>{};
    for (final row in rows) {
      if (row.status == 'skipped') continue;
      final date = NativeLoggingParityPreview.sessionDate(row);
      if (date != null) days.add(date);
    }
    final ordered = days.toList()..sort();
    final result = <String, int>{};
    for (final day in ordered) {
      final previous = DateTime.parse(day + 'T12:00:00Z')
          .subtract(const Duration(days: 1));
      final key = NativeLoggingParityPreview.dateKey(previous);
      result[day] = (result[key] ?? 0) + 1;
    }
    return result;
  }

  /// Original web also attempts cleanTitle/category fallback; that cannot
  /// be certified from a lossy projection. This checks explicit IDs only.
  static bool hasExplicitCompletionEvidence(
    MediaFlowTitle title, Iterable<MediaFlowSession> rows,
  ) {
    if (!NativeLoggingParityPreview.isCompleted(title) ||
        title.id.isEmpty || title.completedAt == null) return false;
    final ended = title.completedAt!.millisecondsSinceEpoch;
    for (final row in rows) {
      if (row.status == 'skipped' || row.timestamp == null ||
          (row.timestamp!.millisecondsSinceEpoch - ended).abs() > 300000) {
        continue;
      }
      if (row.titles.any((part) => part.libraryId == title.id)) return true;
    }
    return false;
  }

  /// XP below is a partial, illustrative reconstruction for positive stored
  /// XP only; user leveling settings and missing XP are NOT reconstructed.
  static NativeHistoryXpParityReport analyze(
    Iterable<MediaFlowSession> rows, {
    Iterable<MediaFlowTitle> library = const [],
    bool levelingEnabled = true,
    Map<String, int>? precomputedStreakDays,
  }) {
    final source = rows is List<MediaFlowSession> ? rows : rows.toList();
    final groups = <String>{};
    var unknown = 0, skipped = 0, ambiguous = 0;
    var baseSum = 0.0, bonusSum = 0.0;
    final days = precomputedStreakDays ?? streakMap(source);
    for (final row in source) {
      if (row.sessionGroupId.isNotEmpty && row.batchGroupId.isNotEmpty) {
        ambiguous++;
      }
      groups.add(logicalKey(row, groups.length));
      if (row.status == 'skipped') {
        skipped++;
        continue;
      }
      final base = knownBaseXp(row);
      final bonus = knownStreakXp(
        row, days, levelingEnabled: levelingEnabled,
      );
      if (base == null || bonus == null) {
        unknown++;
      } else {
        baseSum += base;
        bonusSum += bonus;
      }
    }
    var evidenced = 0;
    for (final title in library) {
      if (hasExplicitCompletionEvidence(title, source)) evidenced++;
    }
    return NativeHistoryXpParityReport(
      historyRows: source.length,
      logicalActions: groups.length,
      skippedRows: skipped,
      unresolvedXpRows: unknown,
      ambiguousGroupRows: ambiguous,
      completedEvidenceCount: evidenced,
      knownBaseXp: baseSum,
      knownStreakBonusXp: bonusSum,
    );
  }
}
