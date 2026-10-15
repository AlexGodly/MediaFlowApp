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
    this.source = '', this.manual = false,
  });
  final String id, name, source;
  final double progress;
  final double? total, number;
  final bool synthetic, manual;
  factory MediaFlowSeason.fromJson(Map<String, dynamic> json) =>
      MediaFlowSeason(
        mediaFlowText(json['name'] ?? json['number'], fallback: 'Season'),
        mediaFlowNumber(json['progress']) ?? 0,
        mediaFlowNumber(json['total']),
        id: mediaFlowText(json['id'] ?? json['seasonId'] ?? json['season_id']),
        number: mediaFlowNumber(json['number'] ?? json['seasonNumber']),
        synthetic: json['synthetic'] == true,
        source: mediaFlowText(json['source']),
        manual: json['manual'] == true,
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
    this.externalIds = const {}, this.manualExternalIds = const {},
    this.seasonSource = '',
  });
  final DateTime? completedAt;
  final String id, title, categoryId, status, priority, coverUrl, description;
  final Map<String, String> externalIds;
  final Map<String, String?> manualExternalIds;
  final String seasonSource;
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
      externalIds: _mediaFlowExternalIds(json['externalIds']),
      manualExternalIds: _mediaFlowManualIds(json['v377ManualExternalIds']),
      seasonSource: mediaFlowText(json['seasonSource']),
    );
  }
}


/// Only the explicitly known ID maps are projected. Unknown Library fields
/// remain in MediaFlowFullState, which must not be rebuilt from these models.
Map<String, String> _mediaFlowExternalIds(Object? raw) {
  if (raw is! Map) return const {};
  return Map.unmodifiable({
    for (final e in raw.entries)
      if (e.key is String && e.value != null &&
          e.value.toString().trim().isNotEmpty)
        e.key as String: e.value.toString(),
  });
}

Map<String, String?> _mediaFlowManualIds(Object? raw) {
  if (raw is! Map) return const {};
  return Map.unmodifiable({
    for (final e in raw.entries)
      if (e.key is String)
        e.key as String: e.value?.toString(),
  });
}

/// Compact read-only v410 XP evidence, deliberately omitting individual
/// ledger IDs, event metadata, and all account/cloud writable state.
class MediaFlowXpEvidence {
  MediaFlowXpEvidence({
    required this.settingsPresent,
    required this.ledgerPresent,
    required this.levelingEnabled,
    required this.globalStreakEnabled,
    required Map<String, double> actionRates,
    required Map<String, double> ledgerTotals,
    required Map<String, int> ledgerCounts,
    required this.invalidLedgerValues,
  }) : actionRates = Map.unmodifiable(actionRates),
       ledgerTotals = Map.unmodifiable(ledgerTotals),
       ledgerCounts = Map.unmodifiable(ledgerCounts);

  static const actionKeys = [
    'collectionAddTitleXP', 'collectionReorderTitleXP',
    'orderAddTitleXP', 'orderAddCollectionXP',
    'orderReorderTitleXP', 'orderReorderCollectionXP', 'batchLogXP',
  ];
  static const ledgerKeys = [
    'v348ActionEvents', 'v348LibraryAdditionBonus',
    'v348LibraryCompletionBonus', 'logCompletions',
  ];
  final bool settingsPresent, ledgerPresent, levelingEnabled;
  final bool globalStreakEnabled;
  final Map<String, double> actionRates, ledgerTotals;
  final Map<String, int> ledgerCounts;
  final int invalidLedgerValues;

  double get knownExtraXp =>
      (ledgerTotals['v348ActionEvents'] ?? 0) +
      (ledgerTotals['v348LibraryAdditionBonus'] ?? 0) +
      (ledgerTotals['v348LibraryCompletionBonus'] ?? 0);
  int get actionEventCount => ledgerCounts['v348ActionEvents'] ?? 0;
  bool get completeAccountXp => false;
  bool get canWrite => false;

  factory MediaFlowXpEvidence.fromState(Map<String, dynamic> state) {
    final settings = state['settings'];
    final rawLeveling = settings is Map ? settings['leveling'] : null;
    final leveling = rawLeveling is Map ? rawLeveling : const {};
    final ledgerRaw = state['xpLedger'];
    final ledger = ledgerRaw is Map ? ledgerRaw : const {};
    final rates = <String, double>{};
    for (final key in actionKeys) {
      final value = mediaFlowNumber(leveling[key]);
      if (value != null && value.isFinite) rates[key] = value;
    }
    var invalid = 0;
    final sums = <String, double>{};
    final counts = <String, int>{};
    for (final key in ledgerKeys) {
      final raw = ledger[key];
      var sum = 0.0, count = 0;
      if (raw is Map) {
        for (final value in raw.values) {
          // Unlike the JavaScript source, native diagnostics reject infinities
          // and malformed numbers rather than claiming an authoritative sum.
          final number = mediaFlowNumber(value);
          if (number == null || !number.isFinite) {
            invalid++;
            continue;
          }
          if (number >= 0) {
            final next = sum + number;
            if (next.isFinite) {
              sum = next;
              count++;
            } else {
              invalid++;
            }
          }
        }
      } else if (raw != null) {
        invalid++;
      }
      sums[key] = sum;
      counts[key] = count;
    }
    return MediaFlowXpEvidence(
      settingsPresent: rawLeveling is Map,
      ledgerPresent: ledgerRaw is Map,
      levelingEnabled: leveling['enabled'] != false,
      globalStreakEnabled: leveling['globalStreakMultiplierEnabled'] != false,
      actionRates: rates, ledgerTotals: sums,
      ledgerCounts: counts, invalidLedgerValues: invalid,
    );
  }

  Map<String, dynamic> toProjection() => {
    'settingsPresent': settingsPresent,
    'ledgerPresent': ledgerPresent,
    'levelingEnabled': levelingEnabled,
    'globalStreakEnabled': globalStreakEnabled,
    'actionRates': actionRates,
    'ledgerTotals': ledgerTotals,
    'ledgerCounts': ledgerCounts,
    'invalidLedgerValues': invalidLedgerValues,
  };

  factory MediaFlowXpEvidence.fromProjection(Map<String, dynamic> raw) {
    Map<String, double> doubles(Object? value, List<String> allowed,
        {bool nonnegativeOnly = true}) {
      final input = value is Map ? value : const {};
      return {
        for (final key in allowed)
          if (mediaFlowNumber(input[key]) case final v?)
            if (v.isFinite && (!nonnegativeOnly || v >= 0)) key: v,
      };
    }
    final rawCounts = raw['ledgerCounts'];
    final counts = rawCounts is Map ? rawCounts : const {};
    return MediaFlowXpEvidence(
      settingsPresent: raw['settingsPresent'] == true,
      ledgerPresent: raw['ledgerPresent'] == true,
      levelingEnabled: raw['levelingEnabled'] != false,
      globalStreakEnabled: raw['globalStreakEnabled'] != false,
      actionRates: doubles(raw['actionRates'], actionKeys,
          nonnegativeOnly: false),
      ledgerTotals: doubles(raw['ledgerTotals'], ledgerKeys),
      ledgerCounts: {
        for (final key in ledgerKeys)
          if (mediaFlowNumber(counts[key]) case final n?)
            if (n.isFinite && n >= 0 && n <= 100000000)
              key: n.toInt(),
      },
      invalidLedgerValues: (mediaFlowNumber(raw['invalidLedgerValues']) ?? 0)
          .clamp(0, 100000000).toInt(),
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
    this.collectionAssignments = const [],
    this.categoryQueues = const {},
    this.prioritizePersonalOrder,
    this.currentTask,
    this.sessionActive = false,
    this.tasksPerDay,
    this.dailyMinutes,
    this.xpEvidence,
    this.updatedAt,
  });

  final List<MediaFlowCategory> categories;
  final List<MediaFlowTitle> library;
  final List<MediaFlowSession> sessions;
  final List<MediaFlowCollection> collections;
  final List<String> personalOrderIds;
  final List<MediaFlowCollectionAssignment> collectionAssignments;
  /// Raw v287 per-category t:/c: tokens, never a cloud-write payload.
  final Map<String, List<String>> categoryQueues;
  /// Null if the snapshot did not explicitly state the website toggle.
  final bool? prioritizePersonalOrder;
  final MediaFlowTask? currentTask;
  final bool sessionActive;
  final double? tasksPerDay, dailyMinutes;
  final MediaFlowXpEvidence? xpEvidence;
  final DateTime? updatedAt;

  Map<String, MediaFlowCategory> get categoryById => {
    for (final category in categories) category.id: category,
  };
}

/// v287 Personal Order Collection assignment, read-only and opaque-safe.
class MediaFlowCollectionAssignment {
  const MediaFlowCollectionAssignment({
    required this.id, required this.collectionId,
    required this.categoryId, required this.categoryRule,
    required this.completedRule, required this.traversedTitleIds,
    this.createdAt = 0,
  });
  final String id, collectionId, categoryId, categoryRule, completedRule;
  final List<String> traversedTitleIds;
  final int createdAt;

  factory MediaFlowCollectionAssignment.fromJson(Map<String,dynamic> raw) =>
      MediaFlowCollectionAssignment(
        id: mediaFlowText(raw['id']),
        createdAt: (mediaFlowNumber(raw['createdAt']) ?? 0).toInt(),
        collectionId: mediaFlowText(raw['collectionId']),
        categoryId: mediaFlowText(raw['categoryId']),
        categoryRule: mediaFlowText(raw['categoryRule'],fallback:'match'),
        completedRule: mediaFlowText(raw['completedRule'],fallback:'skip'),
        traversedTitleIds: List.unmodifiable(
          (raw['traversedTitleIds'] is List
            ? raw['traversedTitleIds'] as List : const [])
              .map((v)=>v.toString())),
      );
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

/// The exact v287 task annotation, when present in the saved snapshot.
/// A source label alone is NOT proof that a queue entry still exists.
class MediaFlowTaskOrderSource {
  const MediaFlowTaskOrderSource({
    required this.type,required this.categoryId,
    required this.libraryId,required this.assignmentId,
  });
  final String type,categoryId,libraryId,assignmentId;

  factory MediaFlowTaskOrderSource.fromJson(Map<String,dynamic> json) =>
      MediaFlowTaskOrderSource(
        type:mediaFlowText(json['type']),
        categoryId:mediaFlowText(json['categoryId']),
        libraryId:mediaFlowText(json['libraryId']),
        assignmentId:mediaFlowText(json['assignmentId']),
      );
}

class MediaFlowTask {
  const MediaFlowTask({
    required this.categoryId, required this.title, required this.low,
    required this.high, required this.unit, required this.reasons,
    this.libraryId = '',this.orderSource,
  });
  final String categoryId, title, unit;
  /// Explicit v410 currentTask.libraryId. Never infer an ID from title text.
  final String libraryId;
  /// Raw currentTask.v287OrderSource, if serialized by the website.
  final MediaFlowTaskOrderSource? orderSource;
  final double low, high;
  final List<String> reasons;

  factory MediaFlowTask.fromJson(Map<String, dynamic> data) {
    final rawReasons = data['reasons'];
    final rawSource=data['v287OrderSource'];
    return MediaFlowTask(
      categoryId: mediaFlowText(data['categoryId']),
      title: mediaFlowText(data['title']),
      libraryId:mediaFlowText(data['libraryId']),
      orderSource:rawSource is Map
        ? MediaFlowTaskOrderSource.fromJson(
            Map<String,dynamic>.from(rawSource))
        : null,
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
