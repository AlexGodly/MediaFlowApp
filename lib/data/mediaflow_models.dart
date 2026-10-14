// ignore_for_file: prefer_interpolation_to_compose_strings
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
  const MediaFlowSeason(this.name, this.progress, this.total, {
    this.id = '', this.number, this.synthetic = false,
  });
  final String id, name;
  final double progress;
  final double? total, number;
  final bool synthetic;
  factory MediaFlowSeason.fromJson(Map<String, dynamic> json) =>
      MediaFlowSeason(
        mediaFlowText(json['name'] ?? json['number'], fallback: 'Season'),
        mediaFlowNumber(json['progress']) ?? 0,
        mediaFlowNumber(json['total']),
        id: mediaFlowText(json['id'] ?? json['seasonId'] ?? json['season_id']),
        number: mediaFlowNumber(json['number'] ?? json['seasonNumber']),
        synthetic: json['synthetic'] == true,
      );
}

/// Read-only projection of a real v369 itemized History unit. This is a
/// diagnostic only, NEVER a serialized cloud edit or a new History record.
class MediaFlowLoggedUnit {
  const MediaFlowLoggedUnit({
    required this.id, required this.number, required this.seasonId,
    required this.isRepeat, required this.durationSeconds,
    required this.loggedAt,
  });
  final String id, seasonId;
  final int number;
  final bool isRepeat;
  final int? durationSeconds;
  final DateTime? loggedAt;

  factory MediaFlowLoggedUnit.fromJson(Map<String, dynamic> raw) {
    final secs = mediaFlowNumber(raw['durationSeconds']);
    final fallbackMinutes = mediaFlowNumber(raw['minutes']);
    return MediaFlowLoggedUnit(
      id: mediaFlowText(raw['id']),
      number: (mediaFlowNumber(raw['number']) ?? 0).floor(),
      seasonId: mediaFlowText(raw['seasonId']),
      isRepeat: raw['isRepeat'] == true,
      durationSeconds: secs != null && secs.isFinite
          ? secs.floor() : fallbackMinutes != null &&
              fallbackMinutes.isFinite ? (fallbackMinutes * 60).round() : null,
      loggedAt: mediaFlowDate(raw['loggedAt']),
    );
  }
}

/// Read-only native projection of the existing web application's entries.
class MediaFlowTitle {
  MediaFlowTitle({
    required this.id, required this.title, required this.categoryId,
    required this.status, required this.priority, required this.progress,
    required this.total, required this.rating, required this.coverUrl,
    required this.tags, required this.seasons, required this.addedAt,
    required this.description,
    this.completedAt,
  });
  final DateTime? completedAt;
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
      completedAt: mediaFlowDate(json['completedAt']),
    );
  }
}

class MediaFlowCatalog {
  const MediaFlowCatalog({
    required this.categories,
    required this.library,
    this.sessions = const [],
    this.collections = const [],
    this.personalOrderIds = const [],
    this.currentTask,
    this.sessionActive = false,
    this.tasksPerDay,
    this.dailyMinutes,
    this.updatedAt,
  });

  final List<MediaFlowCategory> categories;
  final List<MediaFlowTitle> library;
  final List<MediaFlowSession> sessions;
  final List<MediaFlowCollection> collections;
  final List<String> personalOrderIds;
  final MediaFlowTask? currentTask;
  final bool sessionActive;
  final double? tasksPerDay, dailyMinutes;
  final DateTime? updatedAt;

  Map<String, MediaFlowCategory> get categoryById => {
    for (final category in categories) category.id: category,
  };
}

class MediaFlowCollection {
  const MediaFlowCollection({
    required this.id, required this.title, required this.description,
    required this.coverUrl, required this.titleIds,
  });

  final String id, title, description, coverUrl;
  final List<String> titleIds;

  factory MediaFlowCollection.fromJson(Map<String, dynamic> raw) {
    final ids = raw['titleIds'];
    final order = raw['order'];
    final membership = ids is List
        ? ids.map((value) => value.toString()).toSet()
        : <String>{};
    final ordered = <String>[];
    if (order is List) {
      for (final value in order) {
        final id = value.toString();
        if (membership.contains(id) && !ordered.contains(id)) ordered.add(id);
      }
    }
    for (final id in membership) {
      if (!ordered.contains(id)) ordered.add(id);
    }
    return MediaFlowCollection(
      id: mediaFlowText(raw['id']),
      title: mediaFlowText(raw['title'], fallback: 'Untitled Collection'),
      description: mediaFlowText(raw['description']),
      coverUrl: mediaFlowText(raw['coverUrl']),
      titleIds: List.unmodifiable(ordered),
    );
  }

  List<MediaFlowTitle> resolvedTitles(Map<String, MediaFlowTitle> byId) =>
      [for (final id in titleIds) if (byId[id] != null) byId[id]!];

  double progressPercent(Map<String, MediaFlowTitle> byId) {
    final items = resolvedTitles(byId);
    if (items.isEmpty) return 0;
    var done = 0.0, total = 0.0, completed = 0;
    for (final item in items) {
      final t = item.total ?? 0;
      if (t > 0) {
        total += t;
        done += item.progress.clamp(0, t);
      }
      if (item.status == 'completed' || (t > 0 && item.progress >= t)) {
        completed++;
      }
    }
    return total > 0 ? (done / total * 100).clamp(0, 100).toDouble()
        : (completed / items.length * 100).clamp(0, 100).toDouble();
  }
}

class MediaFlowSessionTitle {
  const MediaFlowSessionTitle({
    required this.title, required this.libraryId, required this.quantity,
    required this.loggedAt,
    this.units = const [],
    this.repeat = false,
  });
  final String title;
  final String libraryId;
  final double quantity;
  final DateTime? loggedAt;
  final bool repeat;
  final List<MediaFlowLoggedUnit> units;

  factory MediaFlowSessionTitle.fromJson(Map<String, dynamic> data) =>
      MediaFlowSessionTitle(
        title: mediaFlowText(data['title'], fallback: 'Untitled'),
        libraryId: mediaFlowText(data['libraryId']),
        quantity: mediaFlowNumber(data['qty']) ?? 0,
        loggedAt: mediaFlowDate(data['loggedAt']),
        repeat: data['repeat'] == true,
        units: data['v369Units'] is List
            ? (data['v369Units'] as List).whereType<Map>().map(
                (item) => MediaFlowLoggedUnit.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              ).toList(growable: false)
            : const [],
      );
}

class MediaFlowSession {
  const MediaFlowSession({
    required this.id, required this.categoryId, required this.status,
    required this.date, required this.timestamp, required this.actualAmount,
    required this.minutes, required this.xp, required this.unit,
    required this.note, required this.titles, required this.source,
    this.sessionGroupId = '', this.batchGroupId = '',
    this.healthStatus = '', this.assignedCategoryId = '',
  });

  final String sessionGroupId, batchGroupId, healthStatus, assignedCategoryId;
  final String id, categoryId, status, date, unit, note, source;
  final DateTime? timestamp;
  final double actualAmount, minutes, xp;
  final List<MediaFlowSessionTitle> titles;

  bool isOnDate(DateTime dateToCheck) {
    final target = dateToCheck.year.toString().padLeft(4, '0') + '-'
        + dateToCheck.month.toString().padLeft(2, '0') + '-'
        + dateToCheck.day.toString().padLeft(2, '0');
    if (date.isNotEmpty) return date == target;
    final time = timestamp?.toLocal();
    if (time == null) return false;
    return time.year == dateToCheck.year &&
        time.month == dateToCheck.month && time.day == dateToCheck.day;
  }

  factory MediaFlowSession.fromJson(Map<String, dynamic> data) {
    final rawTitles = data['titles'];
    return MediaFlowSession(
      id: mediaFlowText(data['id']),
      categoryId: mediaFlowText(data['categoryId']),
      status: mediaFlowText(data['status'], fallback: 'logged'),
      date: mediaFlowText(data['date']),
      timestamp: mediaFlowDate(data['timestamp']),
      actualAmount: mediaFlowNumber(data['actualAmount']) ?? 0,
      minutes: mediaFlowNumber(data['minutes']) ?? 0,
      xp: mediaFlowNumber(data['xp']) ?? 0,
      unit: mediaFlowText(data['unit'], fallback: 'units'),
      note: mediaFlowText(data['note']),
      source: mediaFlowText(data['source']),
      sessionGroupId: mediaFlowText(data['sessionGroupId']),
      batchGroupId: mediaFlowText(data['batchGroupId']),
      healthStatus: mediaFlowText(data['healthStatus']),
      assignedCategoryId: mediaFlowText(data['assignedCategoryId']),
      titles: rawTitles is List
          ? rawTitles.whereType<Map>().map((title) =>
              MediaFlowSessionTitle.fromJson(Map<String, dynamic>.from(title)))
              .toList(growable: false)
          : const [],
    );
  }
}

class MediaFlowTask {
  const MediaFlowTask({
    required this.categoryId, required this.title, required this.low,
    required this.high, required this.unit, required this.reasons,
  });
  final String categoryId, title, unit;
  final double low, high;
  final List<String> reasons;

  factory MediaFlowTask.fromJson(Map<String, dynamic> data) {
    final rawReasons = data['reasons'];
    return MediaFlowTask(
      categoryId: mediaFlowText(data['categoryId']),
      title: mediaFlowText(data['title']),
      low: mediaFlowNumber(data['low'] ?? data['targetMid']) ?? 0,
      high: mediaFlowNumber(data['high'] ?? data['targetMid']) ?? 0,
      unit: mediaFlowText(data['unit'], fallback: 'units'),
      reasons: rawReasons is List
          ? rawReasons.map((item) => item.toString()).toList(growable: false)
          : const [],
    );
  }
}

/// The v410 account snapshot supplies projections together.
/// No derived properties are written back to state_data.

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
