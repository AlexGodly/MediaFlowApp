import '../data/mediaflow_models.dart';

/// v120 original logged-completion ledger behavior, run on a DEFENSIVE COPY
/// of synthetic/provided ledger values. Never mutate an account or award XP.
class NativeCompletionLedgerPreview {
  const NativeCompletionLedgerPreview({
    required this.awards,
    required this.projectedLedger,
  });
  final List<int> awards;
  final Map<String, int> projectedLedger;
  bool get canCommit => false;
}

abstract final class NativeXpLedgerParity {
  static NativeCompletionLedgerPreview simulate({
    required bool enabled,
    required double configuredCompletionBonusXp,
    required Map<String, int> existingLedger,
    required Iterable<String> completedTitleIds,
  }) {
    if (!configuredCompletionBonusXp.isFinite) {
      throw const FormatException('Invalid XP configuration');
    }
    final ledger = Map<String, int>.of(existingLedger);
    final awards = <int>[];
    final bonus = configuredCompletionBonusXp.round().clamp(0, 100000000).toInt();
    for (final id in completedTitleIds) {
      if (!enabled || id.isEmpty || ledger.containsKey(id)) {
        awards.add(0);
        continue;
      }
      // v120 deliberately persists zero in the logCompletions ledger:
      // a future change to settings must NEVER reaward the same title.
      ledger[id] = bonus;
      awards.add(bonus);
    }
    return NativeCompletionLedgerPreview(
      awards: List.unmodifiable(awards),
      projectedLedger: Map.unmodifiable(ledger),
    );
  }
}

/// v331EventDate: logged title-specific timestamp precedes the parent
/// session's local date; legacy sessions fall back to session timestamp.
/// All results are provisional display calculations; no History is written.
abstract final class NativeHistoryEventClock {
  static DateTime eventDate({
    required String sessionDate,
    required DateTime? sessionTimestamp,
    required DateTime? titleLoggedAt,
    required DateTime now,
  }) {
    final rawTime = titleLoggedAt?.millisecondsSinceEpoch;
    final maxTime = now.millisecondsSinceEpoch + 86400000;
    if (rawTime != null && rawTime >= 946684800000 &&
        rawTime <= maxTime) {
      return titleLoggedAt!;
    }

    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(sessionDate)) {
      final local = DateTime.tryParse(sessionDate + 'T12:00:00');
      if (local != null) return local;
    }

    if (sessionTimestamp != null &&
        sessionTimestamp.millisecondsSinceEpoch > 0) {
      return sessionTimestamp;
    }
    return now;
  }

  static DateTime eventDateForRow({
    required MediaFlowSession session,
    required MediaFlowSessionTitle titleRow,
    required DateTime now,
  }) => eventDate(
        sessionDate: session.date,
        sessionTimestamp: session.timestamp,
        titleLoggedAt: titleRow.loggedAt,
        now: now,
      );
}
