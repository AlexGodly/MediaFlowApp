import '../../data/mediaflow_models.dart';

/// Read-only totals of XP fields already saved on History sessions.
/// This is not the account XP ledger or the website's level calculation.
class HistoryXpSummary {
  const HistoryXpSummary({
    required this.sessions,
    required this.storedSessionXp,
    required this.loggedMinutes,
    required this.sessionsWithStoredXp,
  });

  final int sessions;
  final double storedSessionXp;
  final double loggedMinutes;
  final int sessionsWithStoredXp;

  factory HistoryXpSummary.fromSessions(
      Iterable<MediaFlowSession> records) {
    var count = 0;
    var xp = 0.0;
    var minutes = 0.0;
    var nonzeroXp = 0;
    for (final record in records) {
      count++;
      if (record.xp.isFinite) {
        xp += record.xp;
        if (record.xp != 0) nonzeroXp++;
      }
      if (record.minutes.isFinite) minutes += record.minutes;
    }
    return HistoryXpSummary(
      sessions: count,
      storedSessionXp: xp,
      loggedMinutes: minutes,
      sessionsWithStoredXp: nonzeroXp,
    );
  }
}
