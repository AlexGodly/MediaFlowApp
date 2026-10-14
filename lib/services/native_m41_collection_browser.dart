import '../data/mediaflow_models.dart';

/// Read-only v274/v276 Collection mini-Library explorer. Pagination limits
/// widgets, never mutates the manually saved membership sequence.
enum NativeM41View { list, compact, cards, covers, coversTitles }
enum NativeM41Sort { saved, title, priority, rating, progress }

class NativeM41BrowseOptions {
  const NativeM41BrowseOptions({
    this.search = '', this.categoryId = '', this.status = '',
    this.priority = '', this.minRating, this.cover = 'all',
    this.sort = NativeM41Sort.saved, this.page = 0, this.pageSize = 25,
  });
  final String search, categoryId, status, priority, cover;
  final double? minRating;
  final NativeM41Sort sort;
  final int page, pageSize;
}

class NativeM41Page {
  const NativeM41Page({required this.items, required this.total,
    required this.page, required this.pages, required this.pageSize});
  final List<MediaFlowTitle> items;
  final int total, page, pages, pageSize;
}

/// One scan of only resolved member IDs; unrelated Library entries are never
/// added, and saved order is unchanged when sorting/filtering display.
NativeM41Page browseCollection(MediaFlowCollection collection,
    Map<String,MediaFlowTitle> library, NativeM41BrowseOptions options) {
  if (!const [25,50,100,200].contains(options.pageSize)) {
    throw const FormatException('Invalid page size');
  }
  final needle = options.search.trim().toLowerCase();
  final items = <MediaFlowTitle>[];
  for (final id in collection.titleIds) {
    final title = library[id];
    if (title == null) continue;
    if (needle.isNotEmpty && !title.title.toLowerCase().contains(needle) &&
        !title.tags.any((tag)=>tag.toLowerCase().contains(needle))) continue;
    if (options.categoryId.isNotEmpty &&
        title.categoryId != options.categoryId) continue;
    if (options.status.isNotEmpty && title.status != options.status) continue;
    if (options.priority.isNotEmpty && title.priority != options.priority) {
      continue;
    }
    if (options.minRating != null &&
        (title.rating == null || title.rating! < options.minRating!)) {
      continue;
    }
    if (options.cover == 'with' && title.coverUrl.isEmpty) continue;
    if (options.cover == 'without' && title.coverUrl.isNotEmpty) continue;
    items.add(title);
  }
  final saved = <String,int>{
    for (var i=0;i<collection.titleIds.length;i++)
      collection.titleIds[i]:i,
  };
  const rank = <String,int>{'high':0,'medium':1,'low':2};
  if (options.sort != NativeM41Sort.saved) {
    items.sort((a,b) {
      final order = switch(options.sort) {
        NativeM41Sort.saved => 0,
        NativeM41Sort.title =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        NativeM41Sort.priority =>
          (rank[a.priority]??3).compareTo(rank[b.priority]??3),
        NativeM41Sort.rating =>
          (b.rating??-1).compareTo(a.rating??-1),
        NativeM41Sort.progress => b.progress.compareTo(a.progress),
      };
      return order != 0 ? order :
          (saved[a.id]??0).compareTo(saved[b.id]??0);
    });
  }
  final pages = items.isEmpty ? 1 : (items.length + options.pageSize - 1) ~/
      options.pageSize;
  final page = options.page.clamp(0,pages-1);
  final start = page * options.pageSize;
  return NativeM41Page(
    items:List.unmodifiable(items.skip(start).take(options.pageSize)),
    total:items.length,page:page,pages:pages,pageSize:options.pageSize);
}

/// Read-only impact check. A v287 assignment can refer to this Collection
/// even when its titles are not direct Personal Order titleIds; never rewrite
/// the assignment or count collection members as direct order placements.
class NativeM41OrderImpact {
  const NativeM41OrderImpact({
    required this.assignments,
    required this.directMembers,
    required this.traversedMembers,
  });
  final List<MediaFlowCollectionAssignment> assignments;
  final int directMembers, traversedMembers;
  bool get hasAssignments => assignments.isNotEmpty;
  bool get requiresQueueReview => hasAssignments || directMembers > 0 ||
      traversedMembers > 0;
}

NativeM41OrderImpact inspectCollectionOrderImpact(
    MediaFlowCatalog catalog,MediaFlowCollection collection) {
  final assignments = catalog.collectionAssignments.where(
    (a)=>a.collectionId == collection.id).toList(growable:false);
  final members=collection.titleIds.toSet();
  final direct=catalog.personalOrderIds.toSet();
  final traversed=<String>{};
  for (final assignment in assignments) {
    traversed.addAll(assignment.traversedTitleIds.where(members.contains));
  }
  return NativeM41OrderImpact(
    assignments:List.unmodifiable(assignments),
    directMembers:members.where(direct.contains).length,
    traversedMembers:traversed.length,
  );
}
