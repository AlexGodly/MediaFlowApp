import '../../data/mediaflow_models.dart';

enum PersonalOrderDisplaySort { saved, alphabetical, progress, priority }

class PersonalOrderBrowser {
  PersonalOrderBrowser(MediaFlowCatalog catalog) {
    final byId = <String, MediaFlowTitle>{
      for (final item in catalog.library) item.id: item,
    };
    final entries = <PersonalOrderEntry>[];
    final used = <String>{};
    var position = 0;
    var missing = 0;
    for (final id in catalog.personalOrderIds) {
      position++;
      if (!used.add(id)) continue;
      final title = byId[id];
      if (title == null) {
        missing++;
      } else {
        entries.add(PersonalOrderEntry(position: position, title: title));
      }
    }
    _savedEntries = List<PersonalOrderEntry>.unmodifiable(entries);
    missingReferences = missing;
  }

  late final List<PersonalOrderEntry> _savedEntries;
  late final int missingReferences;
  int get availableCount => _savedEntries.length;

  List<PersonalOrderEntry> browse({
    String search = '',
    String categoryId = '',
    String status = '',
    String priority = '',
    PersonalOrderDisplaySort sort = PersonalOrderDisplaySort.saved,
  }) {
    final needle = search.trim().toLowerCase();
    final result = <PersonalOrderEntry>[
      for (final entry in _savedEntries)
        if ((needle.isEmpty || entry.title.searchText.contains(needle)) &&
            (categoryId.isEmpty || entry.title.categoryId == categoryId) &&
            (status.isEmpty || entry.title.status == status) &&
            (priority.isEmpty || entry.title.priority == priority))
          entry,
    ];
    const priorityRank = {'high': 0, 'medium': 1, 'low': 2};
    switch (sort) {
      case PersonalOrderDisplaySort.saved:
        break;
      case PersonalOrderDisplaySort.alphabetical:
        result.sort((a, b) {
          final order = a.title.title.toLowerCase().compareTo(
            b.title.title.toLowerCase(),
          );
          return order != 0 ? order : a.position.compareTo(b.position);
        });
      case PersonalOrderDisplaySort.progress:
        result.sort((a, b) {
          final order = b.title.progress.compareTo(a.title.progress);
          return order != 0 ? order : a.position.compareTo(b.position);
        });
      case PersonalOrderDisplaySort.priority:
        result.sort((a, b) {
          final order = (priorityRank[a.title.priority] ?? 3).compareTo(
            priorityRank[b.title.priority] ?? 3,
          );
          return order != 0 ? order : a.position.compareTo(b.position);
        });
    }
    return List<PersonalOrderEntry>.unmodifiable(result);
  }
}

class PersonalOrderEntry {
  const PersonalOrderEntry({required this.position, required this.title});

  /// Saved position is preserved even while a different display sort applies.
  final int position;
  final MediaFlowTitle title;
}
