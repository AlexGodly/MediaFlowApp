import '../data/mediaflow_models.dart';

/// Source-pinned v410 identifiers: v377 editor + v378 import normalization.
/// Pure local data validation; no provider lookup or cloud mutation.
class NativeM39Metadata {
  static const providers = <String>[
    'mal', 'simkl', 'anilist', 'tmdb', 'imdb', 'trakt', 'kitsu', 'isbn'
  ];
  static final RegExp _key = RegExp(r'^[a-z][a-z0-9_]{0,32}$',
      caseSensitive: false);
  static final RegExp _positive = RegExp(r'^[1-9][0-9]*$');
  static final RegExp _imdb = RegExp(r'^tt[0-9]{7,12}$',
      caseSensitive: false);
  static final RegExp _isbn = RegExp(r'^[0-9Xx-]{10,20}$');
  static final RegExp _generic = RegExp(r'^[a-zA-Z0-9_.:-]{1,120}$');

  static bool validId(String provider, String value) {
    if (!_key.hasMatch(provider) || provider.length > 33 ||
        value.length > 120) { return false; }
    if (value.isEmpty) { return true; }
    if (const {'mal','simkl','anilist','tmdb','kitsu'}
        .contains(provider)) { return _positive.hasMatch(value); }
    if (provider == 'imdb') return _imdb.hasMatch(value);
    if (provider == 'isbn') return _isbn.hasMatch(value);
    return _generic.hasMatch(value);
  }

  static void validateIds(Map<String, String> ids,
      Map<String, String?> overrides) {
    if (ids.length > 100 || overrides.length > 100) {
      throw const FormatException('Too many provider identifiers');
    }
    for (final entry in ids.entries) {
      if (!validId(entry.key, entry.value) || entry.value.isEmpty) {
        throw FormatException('Invalid external ID: ${entry.key}');
      }
    }
    for (final entry in overrides.entries) {
      final value = entry.value;
      if (value != null && value.isEmpty) {
        throw const FormatException('Use null for an intentional ID clear');
      }
      if (!validId(entry.key, value ?? '')) {
        throw FormatException('Invalid manual override: ${entry.key}');
      }
    }
  }

  /// v377: a manual correction or *intentional clear* always wins over
  /// historical imported/alias identifiers. A null tombstone is meaningful.
  static NativeM39Ids applyIdChanges(
    Map<String, String> source,
    Map<String, String?> manual,
    Map<String, String?> changes,
  ) {
    validateIds(source, manual);
    final ids = Map<String, String>.of(source);
    final overrides = Map<String, String?>.of(manual);
    for (final entry in changes.entries) {
      final value = entry.value?.trim();
      if (!validId(entry.key, value ?? '')) {
        throw FormatException('Invalid external ID: ${entry.key}');
      }
      if (ids[entry.key] == value && value != null) continue;
      if (!ids.containsKey(entry.key) && (value == null || value.isEmpty) &&
          overrides.containsKey(entry.key) && overrides[entry.key] == null) {
        continue;
      }
      if (value == null || value.isEmpty) {
        ids.remove(entry.key);
        overrides[entry.key] = null;
      } else {
        ids[entry.key] = value;
        overrides[entry.key] = value;
      }
    }
    validateIds(ids, overrides);
    return NativeM39Ids(ids, overrides);
  }

  /// v252 season rows are integer-valued; aggregate derives from rows.
  /// Existing row identifiers are unique. Null totals are allowed.
  static void validateSeasons(List<MediaFlowSeason> seasons,
      {bool legacyUnidentified = false}) {
    if (seasons.length > 200) {
      throw const FormatException('200 seasons maximum');
    }
    final ids = <String>{};
    for (final season in seasons) {
      if ((season.id.trim().isEmpty && !legacyUnidentified) ||
          (season.id.trim().isNotEmpty && !ids.add(season.id)) ||
          season.id.length > 150 ||
          season.name.trim().isEmpty || season.name.length > 200 ||
          !season.progress.isFinite || season.progress < 0 ||
          season.progress != season.progress.roundToDouble() ||
          (season.number != null &&
            (!season.number!.isFinite || season.number! < 0 ||
             season.number != season.number!.roundToDouble())) ||
          (season.total != null &&
            (!season.total!.isFinite || season.total! < 0 ||
             season.total != season.total!.roundToDouble() ||
             season.progress > season.total!))) {
        throw const FormatException('Invalid or duplicate season row');
      }
    }
  }

  static NativeM39SeasonAggregate aggregate(List<MediaFlowSeason> seasons,
      {bool legacyUnidentified = false}) {
    validateSeasons(seasons, legacyUnidentified: legacyUnidentified);
    var progress = 0.0, total = 0.0;
    for (final season in seasons) {
      progress += season.progress;
      if (season.total != null) total += season.total!;
      if (!progress.isFinite || !total.isFinite) {
        throw const FormatException('Season aggregate overflow');
      }
    }
    return NativeM39SeasonAggregate(progress, total > 0 ? total : null);
  }

  static bool sameSeasons(List<MediaFlowSeason> a,List<MediaFlowSeason> b) {
    if (identical(a,b)) return true;
    if (a.length != b.length) { return false; }
    for (var i=0; i<a.length; i++) {
      final x=a[i], y=b[i];
      if (x.id != y.id || x.number != y.number || x.name != y.name ||
          x.progress != y.progress || x.total != y.total ||
          x.source != y.source || x.manual != y.manual ||
          x.synthetic != y.synthetic) { return false; }
    }
    return true;
  }
}

class NativeM39Ids {
  NativeM39Ids(Map<String,String> ids, Map<String,String?> manual)
      : ids = Map.unmodifiable(ids), manual = Map.unmodifiable(manual);
  final Map<String,String> ids;
  final Map<String,String?> manual;
}

class NativeM39SeasonAggregate {
  const NativeM39SeasonAggregate(this.progress, this.total);
  final double progress;
  final double? total;
}
