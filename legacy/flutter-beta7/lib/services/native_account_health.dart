import '../data/mediaflow_models.dart';

/// Computes a bounded, read-only integrity overview of the currently
/// authenticated MediaFlow snapshot. Never copies or changes account data.
class NativeAccountHealth {
  const NativeAccountHealth({
    required this.libraryTitles,
    required this.historySessions,
    required this.collections,
    required this.categories,
    required this.personalOrderReferences,
    required this.duplicateLibraryIds,
    required this.emptyLibraryIds,
    required this.missingCategoryReferences,
    required this.missingPersonalOrderReferences,
    required this.duplicatePersonalOrderReferences,
    required this.missingCollectionReferences,
    required this.duplicateCollectionReferences,
    required this.missingHistoryTitleReferences,
  });

  final int libraryTitles, historySessions, collections, categories;
  final int personalOrderReferences;
  final int duplicateLibraryIds, emptyLibraryIds;
  final int missingCategoryReferences;
  final int missingPersonalOrderReferences;
  final int duplicatePersonalOrderReferences;
  final int missingCollectionReferences;
  final int duplicateCollectionReferences;
  final int missingHistoryTitleReferences;

  int get unresolvedReferences =>
      missingCategoryReferences + missingPersonalOrderReferences +
      missingCollectionReferences + missingHistoryTitleReferences;

  bool get hasWarnings => unresolvedReferences > 0 ||
      duplicateLibraryIds > 0 || emptyLibraryIds > 0 ||
      duplicatePersonalOrderReferences > 0 ||
      duplicateCollectionReferences > 0;

  factory NativeAccountHealth.inspect(MediaFlowCatalog data) {
    final knownIds = <String>{};
    var duplicateLibraryIds = 0;
    var emptyLibraryIds = 0;
    for (final title in data.library) {
      if (title.id.isEmpty) {
        emptyLibraryIds++;
      } else if (!knownIds.add(title.id)) {
        duplicateLibraryIds++;
      }
    }
    final categoryIds = {
      for (final category in data.categories) category.id,
    };
    var missingCategories = 0;
    for (final title in data.library) {
      if (title.categoryId.isNotEmpty &&
          !categoryIds.contains(title.categoryId)) {
        missingCategories++;
      }
    }

    var missingOrder = 0, duplicateOrder = 0;
    final orderSeen = <String>{};
    for (final id in data.personalOrderIds) {
      if (!orderSeen.add(id)) duplicateOrder++;
      if (!knownIds.contains(id)) missingOrder++;
    }

    var missingCollections = 0, duplicateCollections = 0;
    for (final collection in data.collections) {
      final seen = <String>{};
      for (final id in collection.titleIds) {
        if (!seen.add(id)) duplicateCollections++;
        if (!knownIds.contains(id)) missingCollections++;
      }
    }

    var missingHistory = 0;
    for (final session in data.sessions) {
      for (final title in session.titles) {
        if (title.libraryId.isNotEmpty &&
            !knownIds.contains(title.libraryId)) {
          missingHistory++;
        }
      }
    }

    return NativeAccountHealth(
      libraryTitles: data.library.length,
      historySessions: data.sessions.length,
      collections: data.collections.length,
      categories: data.categories.length,
      personalOrderReferences: data.personalOrderIds.length,
      duplicateLibraryIds: duplicateLibraryIds,
      emptyLibraryIds: emptyLibraryIds,
      missingCategoryReferences: missingCategories,
      missingPersonalOrderReferences: missingOrder,
      duplicatePersonalOrderReferences: duplicateOrder,
      missingCollectionReferences: missingCollections,
      duplicateCollectionReferences: duplicateCollections,
      missingHistoryTitleReferences: missingHistory,
    );
  }
}
