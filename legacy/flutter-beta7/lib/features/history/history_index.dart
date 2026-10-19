import '../../data/mediaflow_models.dart';
import 'history_filter.dart';

/// Immutable-snapshot History index. Build once per refreshed catalog,
/// then filter a pre-sorted session list without sorting on every keystroke.
class MediaFlowHistoryIndex {
  MediaFlowHistoryIndex(List<MediaFlowSession> sessions)
      : _sorted = List<MediaFlowSession>.unmodifiable(
          MediaFlowHistoryFilter().apply(sessions),
        );

  final List<MediaFlowSession> _sorted;
  final Map<String, List<MediaFlowSession>> _cache = {};
  static const maxCachedQueries = 6;

  int get length => _sorted.length;
  int get cachedQueries => _cache.length;

  List<MediaFlowSession> query(
    MediaFlowHistoryFilter filter, {
    DateTime? now,
  }) {
    final today = now?.toLocal() ?? DateTime.now();
    final needle = filter.search.trim().toLowerCase();
    // Include local clock minute: Today/7/30-day results must not stay stale.
    final key = [
      filter.categoryId, filter.status, needle, filter.range.name,
      if (filter.range != MediaFlowHistoryRange.all)
        '${today.year}-${today.month}-${today.day}-${today.hour}-${today.minute}',
    ].join('\u0001');
    final cached = _cache[key];
    if (cached != null) return cached;
    final cutoff = switch (filter.range) {
      MediaFlowHistoryRange.all => null,
      MediaFlowHistoryRange.today => null,
      MediaFlowHistoryRange.sevenDays =>
        today.subtract(const Duration(days: 7)),
      MediaFlowHistoryRange.thirtyDays =>
        today.subtract(const Duration(days: 30)),
    };
    final result = List<MediaFlowSession>.unmodifiable([
      for (final session in _sorted)
        if ((filter.categoryId.isEmpty ||
                session.categoryId == filter.categoryId) &&
            (filter.status.isEmpty || session.status == filter.status) &&
            (needle.isEmpty ||
                session.note.toLowerCase().contains(needle) ||
                session.titles.any((entry) =>
                    entry.title.toLowerCase().contains(needle))) &&
            (filter.range != MediaFlowHistoryRange.today ||
                session.isOnDate(today)) &&
            (cutoff == null || _afterCutoff(session, cutoff)))
          session,
    ]);
    if (_cache.length >= maxCachedQueries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
    return result;
  }

  static bool _afterCutoff(MediaFlowSession session, DateTime cutoff) {
    final date = session.timestamp?.toLocal() ??
        DateTime.tryParse(session.date)?.toLocal();
    return date != null && !date.isBefore(cutoff);
  }
}
