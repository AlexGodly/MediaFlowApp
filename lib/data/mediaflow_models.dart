class MediaFlowCategory {
  const MediaFlowCategory({required this.id, required this.name,
      required this.icon, required this.iconUrl, required this.color});
  final String id, name, icon, iconUrl, color;

  factory MediaFlowCategory.fromJson(Map<String, dynamic> json) =>
      MediaFlowCategory(
        id: mediaFlowText(json['id']),
        name: mediaFlowText(json['name'], fallback: 'Category'),
        icon: mediaFlowText(json['icon'] ?? json['emoji'], fallback: '◈'),
        iconUrl: mediaFlowText(json['iconUrl']),
        color: mediaFlowText(json['color']),
      );
}

String mediaFlowText(Object? value, {String fallback = ''}) =>
    value == null ? fallback : value.toString();

double? mediaFlowNumber(Object? value) {
  if (value == null || value == '') return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? mediaFlowDate(Object? value) {
  if (value == null || value == '') return null;
  if (value is num) {
    final n = value.toInt();
    if (n <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(n < 100000000000 ? n * 1000 : n);
  }
  return DateTime.tryParse(value.toString());
}

class MediaFlowSeason {
  const MediaFlowSeason(this.name, this.progress, this.total);
  final String name;
  final double progress;
  final double? total;
  factory MediaFlowSeason.fromJson(Map<String, dynamic> json) =>
      MediaFlowSeason(
        mediaFlowText(json['name'] ?? json['number'], fallback: 'Season'),
        mediaFlowNumber(json['progress']) ?? 0,
        mediaFlowNumber(json['total']),
      );
}

/// Read-only native projection of the existing web application's entries.
class MediaFlowTitle {
  MediaFlowTitle({
    required this.id, required this.title, required this.categoryId,
    required this.status, required this.priority, required this.progress,
    required this.total, required this.rating, required this.coverUrl,
    required this.tags, required this.seasons, required this.addedAt,
    required this.description,
  });
  final String id, title, categoryId, status, priority, coverUrl, description;
  final double progress;
  final double? total, rating;
  final List<String> tags;
  final List<MediaFlowSeason> seasons;
  final DateTime? addedAt;
  late final String searchText = (title + ' ' + tags.join(' ')).toLowerCase();

  factory MediaFlowTitle.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final rawSeasons = json['seasons'];
    return MediaFlowTitle(
      id: mediaFlowText(json['id']),
      title: mediaFlowText(json['title'], fallback: 'Untitled'),
      categoryId: mediaFlowText(json['categoryId']),
      status: mediaFlowText(json['status'], fallback: 'planned'),
      priority: mediaFlowText(json['priority'], fallback: 'medium'),
      progress: mediaFlowNumber(json['progress']) ?? 0,
      total: mediaFlowNumber(json['total']),
      rating: mediaFlowNumber(json['rating']),
      coverUrl: mediaFlowText(json['coverUrl']),
      tags: rawTags is List
          ? rawTags.map((item) => item.toString()).toList(growable: false)
          : const [],
      seasons: rawSeasons is List
          ? rawSeasons.whereType<Map>().map((item) =>
              MediaFlowSeason.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
      addedAt: mediaFlowDate(json['createdAt'] ?? json['addedAt'] ?? json['dateAdded']),
      description: mediaFlowText(json['description'] ?? json['synopsis']),
    );
  }
}

class MediaFlowCatalog {
  const MediaFlowCatalog({
    required this.categories, required this.library, this.updatedAt,
  });
  final List<MediaFlowCategory> categories;
  final List<MediaFlowTitle> library;
  final DateTime? updatedAt;
  Map<String, MediaFlowCategory> get categoryById => {
    for (final category in categories) category.id: category,
  };
}

enum LibrarySort {
  alphabetical, alphabeticalReverse, progressHigh, progressLow,
  ratingHigh, priorityHigh, recentlyAdded,
}

class MediaFlowLibraryFilter {
  const MediaFlowLibraryFilter({
    this.search = '', this.categoryId = '', this.status = '',
    this.priority = '', this.sort = LibrarySort.alphabetical,
  });
  final String search, categoryId, status, priority;
  final LibrarySort sort;

  List<MediaFlowTitle> apply(List<MediaFlowTitle> library) {
    final needle = search.trim().toLowerCase();
    final matches = <MediaFlowTitle>[];
    for (final item in library) {
      if (needle.isNotEmpty && !item.searchText.contains(needle)) continue;
      if (categoryId.isNotEmpty && item.categoryId != categoryId) continue;
      if (status.isNotEmpty && item.status != status) continue;
      if (priority.isNotEmpty && item.priority != priority) continue;
      matches.add(item);
    }
    const priorityRanks = {'low': 0, 'medium': 1, 'high': 2};
    int compare(MediaFlowTitle a, MediaFlowTitle b) {
      switch (sort) {
        case LibrarySort.alphabetical:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case LibrarySort.alphabeticalReverse:
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        case LibrarySort.progressHigh:
          return b.progress.compareTo(a.progress);
        case LibrarySort.progressLow:
          return a.progress.compareTo(b.progress);
        case LibrarySort.ratingHigh:
          return (b.rating ?? -1).compareTo(a.rating ?? -1);
        case LibrarySort.priorityHigh:
          return (priorityRanks[b.priority] ?? 1)
              .compareTo(priorityRanks[a.priority] ?? 1);
        case LibrarySort.recentlyAdded:
          return (b.addedAt?.millisecondsSinceEpoch ?? 0)
              .compareTo(a.addedAt?.millisecondsSinceEpoch ?? 0);
      }
    }
    matches.sort((a, b) {
      final order = compare(a, b);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
    return matches;
  }
}
