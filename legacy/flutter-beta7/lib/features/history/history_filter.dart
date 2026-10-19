import '../../data/mediaflow_models.dart';

enum MediaFlowHistoryRange { all, today, sevenDays, thirtyDays }

class MediaFlowHistoryFilter {
  const MediaFlowHistoryFilter({
    this.categoryId = '',
    this.status = '',
    this.search = '',
    this.range = MediaFlowHistoryRange.all,
  });

  final String categoryId;
  final String status;
  final String search;
  final MediaFlowHistoryRange range;

  List<MediaFlowSession> apply(
    List<MediaFlowSession> sessions, {
    DateTime? now,
  }) {
    final today = now?.toLocal() ?? DateTime.now();
    final needle = search.trim().toLowerCase();
    final selected = <MediaFlowSession>[];

    for (final session in sessions) {
      if (categoryId.isNotEmpty && session.categoryId != categoryId) continue;
      if (status.isNotEmpty && session.status != status) continue;
      if (needle.isNotEmpty) {
        final note = session.note.toLowerCase();
        final titles = session.titles.any(
          (entry) => entry.title.toLowerCase().contains(needle),
        );
        if (!note.contains(needle) && !titles) continue;
      }

      final date = session.timestamp?.toLocal() ??
          DateTime.tryParse(session.date)?.toLocal();
      switch (range) {
        case MediaFlowHistoryRange.all:
          break;
        case MediaFlowHistoryRange.today:
          if (!session.isOnDate(today)) continue;
          break;
        case MediaFlowHistoryRange.sevenDays:
          if (date == null ||
              date.isBefore(today.subtract(const Duration(days: 7)))) {
            continue;
          }
          break;
        case MediaFlowHistoryRange.thirtyDays:
          if (date == null ||
              date.isBefore(today.subtract(const Duration(days: 30)))) {
            continue;
          }
          break;
      }
      selected.add(session);
    }

    // Use a stable secondary ordering when loggedAt is unavailable or equal.
    selected.sort((a, b) {
      final first = a.timestamp?.millisecondsSinceEpoch ??
          DateTime.tryParse(a.date)?.millisecondsSinceEpoch ?? 0;
      final second = b.timestamp?.millisecondsSinceEpoch ??
          DateTime.tryParse(b.date)?.millisecondsSinceEpoch ?? 0;
      final byDate = second.compareTo(first);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return selected;
  }
}
