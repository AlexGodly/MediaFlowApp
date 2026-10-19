import '../data/mediaflow_models.dart';

/// UI-only picker projection. Never serializes data or modifies saved order.
/// Results are paged over the full Library, not truncated to the first 60.
enum NativeM46Membership { all, notAdded, alreadyAdded }
enum NativeM46Sort { library, alphabetical, priority, progress }

class NativeM46PickerPage {
  const NativeM46PickerPage({
    required this.titles, required this.total, required this.page,
    required this.pageSize,
  });
  final List<MediaFlowTitle> titles;
  final int total, page, pageSize;
  int get pageCount => total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
  bool get hasNext => page + 1 < pageCount;
}

class NativeM46TitlePicker {
  NativeM46TitlePicker(MediaFlowCatalog catalog, Iterable<String> orderedIds)
      : _library = catalog.library, _ordered = orderedIds.toSet() {
    final seen = <String>{};
    for (final title in _library) {
      if (!seen.add(title.id)) _ambiguous.add(title.id);
    }
  }

  final List<MediaFlowTitle> _library;
  final Set<String> _ordered;
  final Set<String> _ambiguous = {};

  /// All filters are composed before paging. Source Library order is retained
  /// by default; optional sorts affect display only, not v138 bulk-add order.
  NativeM46PickerPage browse({
    String search = '', String categoryId = '', String status = '',
    String priority = '',
    NativeM46Membership membership = NativeM46Membership.notAdded,
    NativeM46Sort sort = NativeM46Sort.library,
    int page = 0, int pageSize = 40,
  }) {
    if (page < 0 || pageSize < 1 || pageSize > 200) {
      throw const FormatException('Invalid Personal Order picker page');
    }
    final needle = search.trim().toLowerCase();
    final matches = <MediaFlowTitle>[];
    for (final title in _library) {
      if (title.id.isEmpty || _ambiguous.contains(title.id)) continue;
      final added = _ordered.contains(title.id);
      if (membership == NativeM46Membership.notAdded && added) continue;
      if (membership == NativeM46Membership.alreadyAdded && !added) continue;
      if (categoryId.isNotEmpty && title.categoryId != categoryId) continue;
      if (status.isNotEmpty && title.status != status) continue;
      if (priority.isNotEmpty && title.priority != priority) continue;
      if (needle.isNotEmpty && !title.searchText.contains(needle) &&
          !title.id.toLowerCase().contains(needle)) { continue; }
      matches.add(title);
    }
    switch (sort) {
      case NativeM46Sort.library:
        break;
      case NativeM46Sort.alphabetical:
        matches.sort((a, b) {
          final n = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          return n != 0 ? n : a.id.compareTo(b.id);
        });
      case NativeM46Sort.priority:
        int score(String p) => switch (p) {
          'high' => 3, 'medium' => 2, 'low' => 1, _ => 0,
        };
        matches.sort((a, b) {
          final n = score(b.priority).compareTo(score(a.priority));
          return n != 0 ? n : a.title.toLowerCase()
              .compareTo(b.title.toLowerCase());
        });
      case NativeM46Sort.progress:
        matches.sort((a, b) {
          final n = b.progress.compareTo(a.progress);
          return n != 0 ? n : a.title.toLowerCase()
              .compareTo(b.title.toLowerCase());
        });
    }
    final total = matches.length;
    final pages = total == 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
    final current = page.clamp(0, pages - 1);
    final start = current * pageSize;
    return NativeM46PickerPage(
      titles: List.unmodifiable(matches.skip(start).take(pageSize)),
      total: total, page: current, pageSize: pageSize,
    );
  }
}
