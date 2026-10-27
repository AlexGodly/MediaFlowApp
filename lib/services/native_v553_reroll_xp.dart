import 'dart:math' as math;

/// v553 source-parity projection for XP earned by consumed reroll titles.
///
/// This is a pure calculation only. It does not mutate a Library, create a
/// History session, or award XP. The caller must supply the current task's
/// recommendation history and the canonical v537/v544 base XP projection.
/// Cloud writes remain outside this helper.
abstract final class NativeV553RerollXp {
  static NativeV553RerollXpResult project({
    required List<NativeV553Recommendation> recommendationHistory,
    required int respectedSlotLimit,
    required List<NativeV553DraftEntry> draftEntries,
    required bool itemized,
    required List<NativeV553LibraryTitle> library,
    required Map<String, NativeV553Category> categories,
    required NativeV553LevelingSettings settings,
    required NativeV553BaseProjection base,
    String taskCategoryId = '',
    String draftCategoryId = '',
  }) {
    if (!base.eligible || settings.enabled == false) {
      return NativeV553RerollXpResult.empty(base.total);
    }

    final start = respectedSlotLimit
        .clamp(0, recommendationHistory.length)
        .toInt();
    final rerollTitlesByKey = <String, String>{};
    for (final recommendation in recommendationHistory.skip(start)) {
      final key = _titleKey(recommendation.libraryId, recommendation.title);
      if (key.isEmpty) continue;
      rerollTitlesByKey.putIfAbsent(
        key,
        () => recommendation.title.trim().isNotEmpty
            ? recommendation.title.trim()
            : 'Reroll title',
      );
    }
    if (rerollTitlesByKey.isEmpty || draftEntries.isEmpty) {
      return NativeV553RerollXpResult.empty(base.total);
    }

    final libraryById = <String, NativeV553LibraryTitle>{};
    for (final title in library) {
      if (title.id.isNotEmpty) {
        libraryById.putIfAbsent(title.id, () => title);
      }
    }

    final byCategory = <String, _RerollCategoryUnits>{};
    final names = <String>{};
    var unitsTotal = 0;
    var baseXp = 0.0;

    for (final entry in draftEntries) {
      final key = _titleKey(entry.libraryId, entry.title);
      if (key.isEmpty || !rerollTitlesByKey.containsKey(key)) continue;

      final units = itemized
          ? entry.itemizedUnits.where((unit) => unit is Map).length
          : _safeNumber(entry.quantity).floor();
      if (units <= 0) continue;

      final libraryTitle = entry.libraryId.isEmpty
          ? null
          : libraryById[entry.libraryId];
      final categoryId = (libraryTitle?.categoryId.isNotEmpty == true)
          ? libraryTitle!.categoryId
          : taskCategoryId.isNotEmpty
              ? taskCategoryId
              : draftCategoryId;
      final category = categories[categoryId];
      if (category == null || category.id.isEmpty) continue;

      final perUnit = _safeNumber(settings.unitXp[category.unit]);
      if (perUnit <= 0) continue;

      final xp = units * perUnit;
      final row = byCategory.putIfAbsent(
        category.id,
        () => _RerollCategoryUnits(categoryId: category.id),
      );
      row.units += units;
      row.baseXp += xp;
      unitsTotal += units;
      baseXp += xp;
      final rerollName = rerollTitlesByKey[key];
      final entryName = entry.title.trim();
      names.add(rerollName ??
          (entryName.isNotEmpty ? entryName : 'Reroll title'));
    }

    if (unitsTotal == 0 || baseXp <= 0) {
      return NativeV553RerollXpResult.empty(base.total);
    }

    var awardDelta = 0;
    var rotationXp = 0.0;
    for (final row in base.categories) {
      final reroll = byCategory[row.id];
      if (reroll == null) continue;

      final rotation = row.rotation.isFinite
          ? math.max(0.0, row.rotation).toDouble()
          : 1.0;
      final rawBonus = reroll.baseXp * rotation;
      rotationXp += rawBonus - reroll.baseXp;

      final repeat = _safeNumber(base.repeatPerCategory[row.id]);
      final multiplier = base.dayMultiplier.isFinite
          ? math.max(0.0, base.dayMultiplier).toDouble()
          : 1.0;
      final before = ((_safeNumber(row.consumption) +
                  _safeNumber(row.respect) +
                  repeat) *
              multiplier)
          .round();
      final after = ((_safeNumber(row.consumption) +
                  _safeNumber(row.respect) +
                  repeat +
                  rawBonus) *
              multiplier)
          .round();
      final delta = after - before;
      if (delta > 0) awardDelta += delta;
    }

    final streakXp = awardDelta - (baseXp + rotationXp);
    return NativeV553RerollXpResult(
      units: unitsTotal,
      baseXp: baseXp,
      rotationXp: rotationXp.roundToDouble(),
      streakXp: streakXp.roundToDouble(),
      awardXp: awardDelta.toDouble(),
      totalXp: _safeNumber(base.total) + awardDelta,
      titles: List.unmodifiable(names),
    );
  }

  static String _titleKey(String libraryId, String title) {
    final id = libraryId.trim();
    if (id.isNotEmpty) return 'id:$id';
    // The website's canonical Library-ID path is preferred. This conservative
    // fallback is only for older rows that lack IDs; it never fuzzy-matches.
    final normalized = title.trim().toLowerCase().replaceAll(
      RegExp(r'\\s+'),
      ' ',
    );
    return normalized.isEmpty ? '' : 'title:$normalized';
  }

  static double _safeNumber(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return number != null && number.isFinite
        ? math.max(0.0, number).toDouble()
        : 0.0;
  }
}

class NativeV553Recommendation {
  const NativeV553Recommendation({
    required this.libraryId,
    required this.title,
  });
  final String libraryId;
  final String title;
}

class NativeV553DraftEntry {
  const NativeV553DraftEntry({
    required this.libraryId,
    required this.title,
    required this.quantity,
    this.categoryId = '',
    this.itemizedUnits = const [],
  });
  final String libraryId;
  final String title;
  final Object? quantity;
  final String categoryId;
  final List<Object?> itemizedUnits;
}

class NativeV553LibraryTitle {
  const NativeV553LibraryTitle({
    required this.id,
    required this.categoryId,
  });
  final String id;
  final String categoryId;
}

class NativeV553Category {
  const NativeV553Category({
    required this.id,
    required this.unit,
  });
  final String id;
  final String unit;
}

class NativeV553LevelingSettings {
  const NativeV553LevelingSettings({
    required this.enabled,
    required this.unitXp,
  });
  final bool enabled;
  final Map<String, double> unitXp;
}

class NativeV553XpCategoryRow {
  const NativeV553XpCategoryRow({
    required this.id,
    required this.rotation,
    required this.consumption,
    required this.respect,
  });
  final String id;
  final double rotation;
  final double consumption;
  final double respect;
}

class NativeV553BaseProjection {
  const NativeV553BaseProjection({
    required this.eligible,
    required this.total,
    required this.dayMultiplier,
    required this.categories,
    this.repeatPerCategory = const {},
  });
  final bool eligible;
  final double total;
  final double dayMultiplier;
  final List<NativeV553XpCategoryRow> categories;
  final Map<String, double> repeatPerCategory;
}

class NativeV553RerollXpResult {
  const NativeV553RerollXpResult({
    required this.units,
    required this.baseXp,
    required this.rotationXp,
    required this.streakXp,
    required this.awardXp,
    required this.totalXp,
    required this.titles,
  });

  final int units;
  final double baseXp;
  final double rotationXp;
  final double streakXp;
  final double awardXp;
  final double totalXp;
  final List<String> titles;

  factory NativeV553RerollXpResult.empty(double baseTotal) =>
      NativeV553RerollXpResult(
        units: 0,
        baseXp: 0,
        rotationXp: 0,
        streakXp: 0,
        awardXp: 0,
        totalXp: baseTotal,
        titles: const [],
      );
}

class _RerollCategoryUnits {
  _RerollCategoryUnits({required this.categoryId});
  final String categoryId;
  int units = 0;
  double baseXp = 0;
}
