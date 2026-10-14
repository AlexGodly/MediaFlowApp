// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:math' as math;

import '../data/mediaflow_models.dart';

/// Reference-derived, READ-ONLY calculations. They are not v410 submission
/// parity and never create sessions/XP/Library mutations.
/// Sources: original MediaFlow 008-session-flow.js, v179 dual logging,
/// v120 completion XP, v149 day streak and v369/v394 itemized logging.
enum NativeLogInputMode { amount, lastProgress }

class NativeLoggingPreview {
  const NativeLoggingPreview({
    required this.mode,
    required this.repeat,
    required this.start,
    required this.input,
    required this.consumed,
    required this.previewEnd,
    required this.projectedLibraryProgress,
    required this.projectedStatus,
    required this.wouldComplete,
    required this.prospectiveStreak,
    required this.streakMultiplier,
    required this.historyProjection,
    required this.unverifiedFields,
  });

  final NativeLogInputMode mode;
  final bool repeat;
  final double start, input, consumed, previewEnd, projectedLibraryProgress;
  final String projectedStatus;
  final bool wouldComplete;
  final int prospectiveStreak;
  final double streakMultiplier;
  final NativeHistoryProjection historyProjection;
  final List<String> unverifiedFields;
  /// XP is not computable from a lossy catalog: category/leveling settings,
  /// ledgers, per-unit metadata and late v410 modifiers are absent.
  double? get prospectiveXp => null;
  bool get productionReady => false;
}

class NativeHistoryProjection {
  const NativeHistoryProjection({
    required this.titleId,
    required this.title,
    required this.categoryId,
    required this.quantity,
    required this.minutes,
    required this.note,
    required this.repeat,
    required this.date,
  });

  final String titleId, title, categoryId, note, date;
  final double quantity, minutes;
  final bool repeat;

  /// Intentionally not a v410 session payload: no IDs, XP, completion
  /// ledgers, category-health, user task context or itemized timestamps.
  bool get canCommit => false;
}

abstract final class NativeLoggingParityPreview {
  static bool isCompleted(MediaFlowTitle title) =>
      title.status == 'completed' ||
      (title.total != null && title.total! > 0 &&
          title.progress >= title.total!);

  static NativeLoggingPreview calculate({
    required MediaFlowTitle title,
    required Iterable<MediaFlowSession> existingSessions,
    required NativeLogInputMode mode,
    required double value,
    required double minutes,
    required String note,
    bool repeat = false,
    DateTime? date,
  }) {
    if (!value.isFinite || value < 0 || value > 100000 ||
        !minutes.isFinite || minutes < 0 || minutes > 100000 ||
        note.length > 2000) {
      throw const FormatException('Invalid log amount or runtime');
    }
    if (title.id.isEmpty) {
      throw const FormatException('A Library title ID is required');
    }
    // Season ownership/ID and archived unit evidence are absent from the
    // native read-only projection. Never silently approximate these.
    if (title.seasons.isNotEmpty) {
      throw const FormatException(
        'Season logging needs full v252/v369 unit and season identifiers',
      );
    }
    if (repeat && !isCompleted(title)) {
      throw const FormatException(
        'Repeat logging requires an already completed title',
      );
    }
    final start = isCompleted(title) ? 0.0 :
        math.max(0.0, title.progress);
    final safeEnd = title.total != null && title.total! > 0
        ? math.min(math.max(0.0, value), title.total!)
        : math.max(0.0, value);
    final consumed = mode == NativeLogInputMode.lastProgress
        ? math.max(0.0, safeEnd - start) : value;
    if (consumed <= 0) {
      throw const FormatException('A positive quantity is required');
    }
    // v179: completed-title last-progress starts at zero; v81/submitLog:
    // repeats count as consumption but cannot increment main Library progress.
    // Normal consumption increments and clamps to total.
    final rawNext = title.progress + consumed;
    final next = repeat ? title.progress :
        title.total != null && title.total! > 0
        ? math.min(rawNext, title.total!) : rawNext;
    final wouldComplete = !repeat &&
        !isCompleted(title) &&
        title.total != null && title.total! > 0 &&
        next >= title.total!;
    final nextStatus = repeat ? title.status :
        next >= (title.total ?? double.infinity) &&
            (title.total ?? 0) > 0 && title.status != 'dropped'
          ? 'completed'
          : title.status == 'planned' ? 'active' : title.status;
    final stamp = date ?? DateTime.now().toUtc();
    final day = dateKey(stamp);
    final streak = prospectiveStreak(existingSessions, day);
    return NativeLoggingPreview(
      mode: mode,
      repeat: repeat,
      start: start,
      input: value,
      consumed: consumed,
      previewEnd: mode == NativeLogInputMode.lastProgress
          ? safeEnd : start + consumed,
      projectedLibraryProgress: next,
      projectedStatus: nextStatus,
      wouldComplete: wouldComplete,
      prospectiveStreak: streak,
      streakMultiplier: streakMultiplier(streak),
      historyProjection: NativeHistoryProjection(
        titleId: title.id, title: title.title,
        categoryId: title.categoryId, quantity: consumed,
        minutes: minutes, note: note.trim(), repeat: repeat, date: day,
      ),
      unverifiedFields: const [
        'History IDs and grouping',
        'configured consumption XP',
        'XP ledgers and one-time completion rewards',
        'newer global action multipliers',
        'season/unit timestamps and active task outcome',
      ],
    );
  }

  /// v149 session date chooses YYYY-MM-DD if stored, else UTC timestamp day.
  static String? sessionDate(MediaFlowSession record) {
    final d = record.date.trim();
    if (_isValidDateKey(d)) return d;
    final ts = record.timestamp;
    return ts == null ? null : dateKey(ts.toUtc());
  }

  static String dateKey(DateTime value) {
    final d = value.toUtc();
    return d.year.toString().padLeft(4, '0') + '-' +
        d.month.toString().padLeft(2, '0') + '-' +
        d.day.toString().padLeft(2, '0');
  }

  static bool _isValidDateKey(String key) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return false;
    final parsed = DateTime.tryParse(key);
    return parsed != null && dateKey(parsed) == key;
  }

  static int prospectiveStreak(
      Iterable<MediaFlowSession> sessions, String targetDay) {
    if (!_isValidDateKey(targetDay)) {
      throw const FormatException('Invalid preview date');
    }
    final days = <String>{};
    for (final session in sessions) {
      if (session.status == 'skipped') continue;
      final day = sessionDate(session);
      if (day != null) days.add(day);
    }
    final sorted = days.toList()..sort();
    final streaks = <String, int>{};
    for (final day in sorted) {
      final previous = _offsetDay(day, -1);
      streaks[day] = (streaks[previous] ?? 0) + 1;
    }
    if (streaks.containsKey(targetDay)) return streaks[targetDay]!;
    return (streaks[_offsetDay(targetDay, -1)] ?? 0) + 1;
  }

  static String _offsetDay(String key, int difference) {
    final day = DateTime.parse(key + 'T12:00:00Z');
    return dateKey(day.add(Duration(days: difference)));
  }

  /// v149 rounded two-decimal modifier; actual use is gated by level settings.
  static double streakMultiplier(int consecutiveDays) {
    if (consecutiveDays <= 1) return 1;
    return ((1 + 0.10 *
        (math.log(consecutiveDays) / math.ln2)) * 100).round() / 100;
  }

  /// v369 contiguous-number rule for non-repeat episodes/chapters.
  /// This is a pure diagnostic, not a full season-aware edit.
  static int contiguousProgress({
    required int start,
    required Iterable<int> unitNumbers,
    int? total,
  }) {
    if (start < 0 || (total != null && total < start)) {
      throw const FormatException('Invalid existing unit range');
    }
    final pending = unitNumbers.where((n) => n > start).toSet();
    final max = total ?? 0x7fffffff;
    var end = start;
    while (end < max && pending.contains(end + 1)) {
      end++;
    }
    return end;
  }
}
