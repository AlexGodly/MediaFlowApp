import 'mediaflow_models.dart';

/// A read-only index for one immutable cloud Library snapshot.
/// Sorted views are computed lazily and reused across search/filter changes.
/// A new cloud snapshot MUST construct a new index.
class MediaFlowLibraryIndex {
  MediaFlowLibraryIndex(List<MediaFlowTitle> titles)
      : _titles = List<MediaFlowTitle>.unmodifiable(titles);

  final List<MediaFlowTitle> _titles;
  final Map<LibrarySort, List<MediaFlowTitle>> _sorted = {};
  final Map<String, List<MediaFlowTitle>> _queryCache = {};
  static const int maxQueryCacheEntries = 8;

  int get length => _titles.length;
  int get cachedSortCount => _sorted.length;
  int get cachedQueryCount => _queryCache.length;

  List<MediaFlowTitle> query(MediaFlowLibraryFilter filter) {
    final needle = filter.search.trim().toLowerCase();
    final key = [
      filter.sort.name, needle, filter.categoryId,
      filter.status, filter.priority,
    ].join('\u0001');
    final cached = _queryCache[key];
    if (cached != null) return cached;

    final ordered = _sorted.putIfAbsent(filter.sort, () {
      // Reuse the website-model comparator as the authoritative sorting
      // behavior, but sort ONCE per snapshot and mode.
      return List<MediaFlowTitle>.unmodifiable(
        MediaFlowLibraryFilter(sort: filter.sort).apply(_titles),
      );
    });
    final List<MediaFlowTitle> result;
    if (needle.isEmpty && filter.categoryId.isEmpty &&
        filter.status.isEmpty && filter.priority.isEmpty) {
      result = ordered;
    } else {
      result = List<MediaFlowTitle>.unmodifiable([
        for (final title in ordered)
          if ((needle.isEmpty || title.searchText.contains(needle)) &&
              (filter.categoryId.isEmpty ||
                  title.categoryId == filter.categoryId) &&
              (filter.status.isEmpty || title.status == filter.status) &&
              (filter.priority.isEmpty ||
                  title.priority == filter.priority))
            title,
      ]);
    }
    // Bound the number of full-result references retained when the user
    // types hundreds of distinct queries. Oldest entry is evicted.
    if (_queryCache.length >= maxQueryCacheEntries) {
      _queryCache.remove(_queryCache.keys.first);
    }
    _queryCache[key] = result;
    return result;
  }

  void clearQueryCache() => _queryCache.clear();
}
