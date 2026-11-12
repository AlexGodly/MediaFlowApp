// The website's Recovery Workspace logic:
//  - Cover Recovery (v424 / v425): covers for titles that have none, from
//    verified search results; only confident matches are applied
//    automatically, the rest wait for review. Saved as `auto:<provider>:verified`
//    with the cover-change XP (mf425Credit).
//  - Metadata Recovery (v439): per-field proposals from verified provider
//    records with evidence (`mf439Evidence`, `mf439Proposals`); only missing
//    fields are filled, protected and existing values are never replaced, and
//    automatic mode applies only nonconflicting fields at ≥ 94 % confidence
//    (`mf439Apply`).

import 'dart:convert';

import '../util/js.dart';
import 'library_logic.dart' show coverCredit, findTitle;
import 'ratings_engine.dart';
import 'title_names.dart';

// ---------- shared ----------

/// `MF439_LEGACY_FIELDS`: the Library fields Metadata Recovery may fill.
/// `MF437_FIELDS` (website v437): the universal `field.*` values, label and kind.
const kUniversalFields = <String, (String, String)>{
  'originalTitle': ('Original title', 'text'),
  'alternateTitles': ('Alternate titles', 'list'),
  'originalLanguage': ('Original language', 'text'),
  'countries': ('Countries of origin', 'list'),
  'creators': ('Creators', 'list'),
  'keywords': ('Keywords', 'list'),
  'releaseStatus': ('Release status', 'text'),
  'franchise': ('Franchise / universe', 'text'),
  'officialWebsite': ('Official website', 'url'),
  'awards': ('Awards / nominations', 'list'),
  'animeSeason': ('Broadcast season', 'text'),
  'animeLicensors': ('Licensors', 'list'),
  'animeVoiceCast': ('Voice cast', 'list'),
  'animeBroadcast': ('Broadcast schedule', 'text'),
  'mangaAuthors': ('Authors', 'list'),
  'mangaArtists': ('Artists / illustrators', 'list'),
  'serialization': ('Serialization / magazine', 'text'),
  'mangaPublisher': ('Publisher', 'text'),
  'chapterCount': ('Chapters', 'number'),
  'volumeCount': ('Volumes', 'number'),
  'directors': ('Directors', 'list'),
  'screenwriters': ('Screenwriters', 'list'),
  'cast': ('Cast', 'list'),
  'distributors': ('Distributors', 'list'),
  'productionCountries': ('Production countries', 'list'),
  'boxOffice': ('Box office', 'text'),
  'budget': ('Production budget', 'text'),
  'tvCreators': ('Series creators', 'list'),
  'tvCast': ('Cast', 'list'),
  'networks': ('Networks', 'list'),
  'showrunners': ('Showrunners', 'list'),
  'seasonCount': ('Seasons', 'number'),
  'episodeCount': ('Episodes', 'number'),
  'broadcastStatus': ('Broadcast status', 'text'),
  'authors': ('Authors', 'list'),
  'editors': ('Editors', 'list'),
  'translators': ('Translators', 'list'),
  'narrators': ('Narrators', 'list'),
  'bookPublishers': ('Publishers', 'list'),
  'pageCount': ('Pages', 'number'),
  'bookSeries': ('Book series', 'text'),
  'bookEdition': ('Edition', 'text'),
  'comicWriters': ('Writers', 'list'),
  'comicArtists': ('Artists', 'list'),
  'comicInkers': ('Inkers', 'list'),
  'comicColorists': ('Colorists', 'list'),
  'comicLetterers': ('Letterers', 'list'),
  'comicPublisher': ('Publisher', 'text'),
  'issueCount': ('Issues', 'number'),
  'comicImprint': ('Imprint', 'text'),
  'gameDevelopers': ('Developers', 'list'),
  'gamePublishers': ('Publishers', 'list'),
  'platforms': ('Platforms', 'list'),
  'gameEngine': ('Game engine', 'text'),
  'gameModes': ('Game modes', 'list'),
  'gameSeries': ('Series', 'text'),
  'esrbRating': ('ESRB rating', 'text'),
  'pegiRating': ('PEGI rating', 'text'),
  'mainStoryHours': ('Main story hours', 'decimal'),
  'vnDevelopers': ('Developers', 'list'),
  'vnPublishers': ('Publishers', 'list'),
  'vnEngine': ('Engine', 'text'),
  'vnRoutes': ('Routes', 'list'),
  'vnEndings': ('Endings', 'number'),
  'vnCharacters': ('Characters', 'list'),
  'vnVoices': ('Voice actors', 'list'),
  'albumArtists': ('Album artists', 'list'),
  'featuredArtists': ('Featured artists', 'list'),
  'composers': ('Composers', 'list'),
  'recordLabels': ('Labels', 'list'),
  'releaseType': ('Release type', 'text'),
  'trackCount': ('Tracks', 'number'),
  'discCount': ('Discs', 'number'),
  'catalogNumber': ('Catalog number', 'text'),
  'tracklist': ('Tracklist (one track per line)', 'multiline'),
  'ifAuthors': ('Authors', 'list'),
  'ifEngine': ('Engine / system', 'text'),
  'ifFormat': ('Format', 'text'),
  'ifParser': ('Parser / choice-based', 'text'),
  'ifPlatforms': ('Platforms', 'list'),
  'ifCharacters': ('Characters', 'list'),
  'ifPlaytimeMinutes': ('Playtime (minutes)', 'number'),
};

const kRecoveryFields = <String, (String, String)>{
  'synopsis': ('Synopsis / Description', 'text'),
  'genres': ('Genres', 'list'),
  'studios': ('Studios', 'list'),
  'producers': ('Producers', 'list'),
  'themes': ('Themes', 'list'),
  'year': ('Release year', 'number'),
  'releaseDate': ('Release date', 'text'),
  'mediaFormat': ('Media format', 'text'),
  'durationMinutes': ('Duration (minutes)', 'number'),
  'seasonLabel': ('Season', 'text'),
  'ageRating': ('Age rating', 'text'),
  'demographic': ('Demographic', 'text'),
  'mediaSource': ('Source material', 'text'),
};

/// `mf439Has`.
bool hasValue(Object? v) => v != null && v != '' && !(v is List && v.isEmpty);

/// `MF439_DEFAULT` merged with `settings.v439Metadata` (`mf439Preferences`).
Map<String, dynamic> metadataPreferences(Map<String, dynamic>? settings) {
  final data = asMap(settings?['v439Metadata']) ?? const <String, dynamic>{};
  final defaults = <String, dynamic>{
    'enabled': [...kPublicSources, ...kGatewaySources],
    'batchSize': 25,
    'maxBatch': 250,
    'minimumConfidence': 0.94,
    'manualReview': true,
  };
  int clampInt(Object? v, int def, int max) {
    final n = jsNum(v);
    final i = n.isFinite && n != 0 ? n.floor() : def;
    return i < 1 ? 1 : (i > max ? max : i);
  }

  return {
    ...defaults,
    ...data,
    'enabled': data['enabled'] is List ? asList(data['enabled']).whereType<String>().toList() : List<String>.of(defaults['enabled'] as List<String>),
    'batchSize': clampInt(data['batchSize'], 25, 100),
    'maxBatch': clampInt(data['maxBatch'], 250, 250),
  };
}

/// What `mf439SaveSettings` writes to `settings.v439Metadata`.
Map<String, dynamic> metadataSettingsToSave(Map<String, dynamic>? settings, List<String> enabled, int maxBatch) {
  final prefs = metadataPreferences(settings);
  final allowed = kAvailableSources.toSet();
  return {
    ...prefs,
    'enabled': [for (final id in kAvailableSources) if (enabled.contains(id) && allowed.contains(id)) id],
    'maxBatch': maxBatch.clamp(1, 250),
  };
}

/// `mf453ProvidersFor('metadata', category)`.
List<String> metadataProvidersFor(Map<String, dynamic>? settings, String categoryId) {
  final preset = asMap(asMap(settings?['v453RecoveryPresets'])?[categoryId])?['metadata'];
  if (preset is List) return [...{...preset.whereType<String>()}];
  return (metadataPreferences(settings)['enabled'] as List).cast<String>().toList();
}

/// What `mf453SavePreset(category, 'metadata', providers)` writes to
/// `settings.v453RecoveryPresets` (null providers = use the global list).
Map<String, dynamic> presetsToSave(Map<String, dynamic>? settings, String categoryId, List<String>? providers) {
  final preset = <String, dynamic>{...?asMap(settings?['v453RecoveryPresets'])};
  final row = <String, dynamic>{...?asMap(preset[categoryId])};
  if (providers == null) {
    row.remove('metadata');
  } else {
    final registered = kAvailableSources.toSet();
    row['metadata'] = [...{...providers.where(registered.contains)}];
  }
  if (row.isNotEmpty) {
    preset[categoryId] = row;
  } else {
    preset.remove(categoryId);
  }
  return preset;
}

/// The metadata sources Recovery uses for a title (`mf453Ready('metadata')`).
List<String> metadataSourcesFor(Map<String, dynamic> item, Map<String, dynamic>? settings, Set<String> gatewayReady) {
  final selected = metadataProvidersFor(settings, jsStr(item['categoryId'])).toSet();
  return [
    for (final id in kAvailableSources)
      if ((!kGatewaySources.contains(id) || gatewayReady.contains(id)) && selected.contains(id)) id,
  ];
}

// ---------- Cover Recovery ----------

/// A cover a search found for a title.
class CoverCandidate {
  CoverCandidate(
      {required this.url,
      required this.provider,
      required this.title,
      this.year,
      required this.confidence,
      required this.reason,
      this.recordId = '',
      this.externalIdKey = '',
      this.recordUrl = '',
      this.reportedIds = const [],
      this.altTitles = const [],
      this.format = '',
      this.idMatch = false});
  final String url, provider, title, reason;

  /// The record's other names ("also known as") and its format line.
  final List<String> altTitles;
  final String format;
  final int? year;
  final double confidence;

  /// The provider's own record (website `candidate.recordId`,
  /// `externalIdKey`, `recordUrl`) and the IDs the provider reports with it.
  final String recordId, externalIdKey, recordUrl;
  final List<(String, String)> reportedIds;
  final bool idMatch;

  /// `mf433EnrichCoverCandidate`: the verified IDs this cover can link.
  late final List<(String, String)> ids = coverCandidateIds(this);
}

/// The app's search sources as website provider ids.
String coverProviderId(String source) => switch (source.toLowerCase()) {
      'anilist' => 'anilist',
      'tvmaze' => 'tvmaze',
      'open library' => 'openlibrary',
      'itunes' => 'itunes',
      'tmdb' => 'tmdb',
      'myanimelist official' => 'malofficial',
      'fanart.tv' => 'fanart',
      final s => s.replaceAll(' ', ''),
    };

/// `mf424AsCandidate`'s externalIdKey for the app's sources.
String coverExternalIdKey(String provider) =>
    const {
      'anilist': 'anilist', 'tvmaze': 'tvmaze', 'openlibrary': 'openlibrary', 'jikan': 'mal', 'tenrai': 'mal', 'kitsu': 'kitsu',
      'mangadex': 'mangadex', 'malofficial': 'mal',
    }[provider] ??
    '';

const _nativeIdKeys = {
  'tenrai': 'mal', 'jikan': 'mal', 'anilist': 'anilist', 'kitsu': 'kitsu', 'tvmaze': 'tvmaze',
  'mangadex': 'mangadex', 'tmdb': 'tmdb', 'omdb': 'imdb', 'thetvdb': 'tvdb_series',
  'simkl': 'simkl', 'malofficial': 'mal', 'anidb': 'anidb',
  'animeschedule': 'animeschedule', 'watchmode': 'watchmode',
  'episodate': 'episodate', 'mangaupdates': 'mangaupdates',
  'livechart': 'livechart', 'trakt': 'trakt', 'hardcover': 'hardcover_book',
  'gutendex': 'gutendex', 'royalroad': 'royalroad',
  'wikidata': 'wikidata', 'comicvine': 'comicvine_volume', 'metron': 'metron_series',
};

/// `mf433NativeKey`.
String coverNativeKey(String provider, String recordId, String externalIdKey) {
  if (finderIdKey(externalIdKey)) return externalIdKey;
  if (provider == 'openlibrary') {
    if (RegExp(r'^OL\d+W$', caseSensitive: false).hasMatch(recordId)) return 'openlibrary_work';
    if (RegExp(r'^OL\d+M$', caseSensitive: false).hasMatch(recordId)) return 'openlibrary_edition';
    return 'openlibrary';
  }
  return _nativeIdKeys[provider] ?? '';
}

List<(String, String)> coverCandidateIds(CoverCandidate c) {
  final ids = <(String, String)>[];
  void add(String key, String value) {
    final str = value.trim();
    if (finderIdValid(key, str) && !ids.any((r) => r.$1 == key && r.$2 == str)) ids.add((key, str));
  }

  final native = coverNativeKey(c.provider, c.recordId, c.externalIdKey);
  if (native.isNotEmpty && c.recordId.isNotEmpty) add(native, c.recordId);
  if (c.provider == 'openlibrary') {
    final isbn = RegExp(r'/isbn/([\dXx-]{10,20})').firstMatch(c.recordUrl)?[1];
    if (isbn != null) add('isbn', isbn);
  }
  for (final (k, v) in c.reportedIds) {
    if ((c.provider == 'anilist' && k == 'mal') || (c.provider == 'tvmaze' && k == 'imdb')) add(k, v);
  }
  return ids;
}

/// `mf433CandidateLinks`: what linking this cover would write.
List<({String key, String value, String existing, bool conflict})> coverIdLinks(Map<String, dynamic> item, CoverCandidate c) {
  final links = <({String key, String value, String existing, bool conflict})>[];
  final seen = <String>{};
  final ids = asMap(item['externalIds']) ?? const {};
  void push(String key, String value) {
    final k = key.trim().toLowerCase(), v = value.trim();
    if (!finderIdValid(k, v) || seen.contains(k)) return;
    seen.add(k);
    final existing = ids[k] == null ? '' : jsStr(ids[k]).trim();
    links.add((key: k, value: v, existing: existing, conflict: existing.isNotEmpty && existing != v));
  }

  for (final (k, v) in c.ids.take(32)) {
    push(k, v);
  }
  final native = coverNativeKey(c.provider, c.recordId, c.externalIdKey);
  if (native.isNotEmpty && c.recordId.isNotEmpty && !links.any((l) => l.key == native)) push(native, c.recordId);
  if (c.externalIdKey.isNotEmpty && c.recordId.isNotEmpty) push(c.externalIdKey, c.recordId);
  return links;
}

/// `mf456CandidateLink`: the one provider ID Quick Title Recovery links.
({String key, String id, bool canLink}) quickCoverLink(Map<String, dynamic> item, CoverCandidate c) {
  final links = coverIdLinks(item, c);
  ({String key, String value, String existing, bool conflict})? link;
  if (links.isNotEmpty) {
    link = links.where((l) => !l.conflict && l.existing != l.value).firstOrNull ?? links.first;
  } else {
    final key = c.externalIdKey.trim(), value = c.recordId.trim();
    final okKey = RegExp(r'^[a-z][a-z0-9_]{0,32}$').hasMatch(key);
    final okValue = value.isNotEmpty &&
        value.length <= 120 &&
        (RegExp(r'^[\w.:-]+$').hasMatch(value) || (key == 'openlibrary' && RegExp(r'^/works/OL\d+W$').hasMatch(value)));
    if (okKey && okValue) {
      final ids = asMap(item['externalIds']) ?? const {};
      final existing = ids[key] == null ? '' : jsStr(ids[key]).trim();
      link = (key: key, value: value, existing: existing, conflict: existing.isNotEmpty && existing != value);
    }
  }
  final key = (link?.key ?? c.externalIdKey).trim();
  final id = (link?.value ?? c.recordId).trim();
  return (key: key, id: id, canLink: link != null && !link.conflict && link.existing.isEmpty && id.isNotEmpty);
}

/// Quick Title Recovery's cover save (website v453 `mf453ApplyQuick`): the
/// chosen cover replaces the current one (after the person confirms) and
/// links the provider's record ID when no ID is saved for it yet.
bool applyQuickCover(Map<String, dynamic> item, CoverCandidate c, int now) {
  if (jsStr(item['coverUrl']) == c.url) return false;
  item['coverUrl'] = c.url;
  item['coverSource'] = 'manual:quick:${c.provider.isEmpty ? 'verified' : c.provider}';
  final link = quickCoverLink(item, c);
  if (link.canLink) {
    item['externalIds'] = {...?asMap(item['externalIds']), link.key: link.id};
    item['v377ManualExternalIds'] = {...?asMap(item['v377ManualExternalIds']), link.key: link.id};
  }
  item['modifiedAt'] = now;
  return true;
}

/// `mf433LinkCandidateIds`: saves the verified IDs that don't conflict.
/// Returns how many were written.
int linkCoverIds(Map<String, dynamic> item, CoverCandidate c, {bool manual = false}) {
  final overrides = Map<String, dynamic>.of(asMap(item['v377ManualExternalIds']) ?? const {});
  // Cleared IDs and the person's own overrides stay unless they picked this.
  final links = coverIdLinks(item, c)
      .where((l) => !l.conflict && l.existing != l.value && (manual || !overrides.containsKey(l.key)))
      .toList();
  if (links.isEmpty) return 0;
  final ids = Map<String, dynamic>.of(asMap(item['externalIds']) ?? const {});
  for (final l in links) {
    ids[l.key] = l.value;
    if (manual) overrides[l.key] = l.value;
  }
  item['externalIds'] = ids;
  if (manual) item['v377ManualExternalIds'] = overrides;
  return links.length;
}

/// The compatibility characters NFKC folds that turn up in titles: full-width
/// forms, the ideographic space, Latin ligatures, Roman numerals, vulgar
/// fractions, super/subscript digits, ellipsis. (Dart has no NFKC; this
/// covers what matters for comparing titles — see cover-match-golden.json.)
String nfkcLite(String s) {
  const map = {
    0x3000: ' ', 0x2026: '...', 0x2025: '..', 0x00A0: ' ', 0x2002: ' ', 0x2003: ' ', 0x2009: ' ', 0x200A: ' ',
    0xFB00: 'ff', 0xFB01: 'fi', 0xFB02: 'fl', 0xFB03: 'ffi', 0xFB04: 'ffl', 0xFB05: 'st', 0xFB06: 'st',
    0x00BC: '1⁄4', 0x00BD: '1⁄2', 0x00BE: '3⁄4', 0x2153: '1⁄3', 0x2154: '2⁄3', 0x215B: '1⁄8',
    0x00B2: '2', 0x00B3: '3', 0x00B9: '1', 0x2070: '0', 0x2074: '4', 0x2075: '5', 0x2076: '6', 0x2077: '7', 0x2078: '8', 0x2079: '9',
    0x2080: '0', 0x2081: '1', 0x2082: '2', 0x2083: '3', 0x2084: '4', 0x2085: '5', 0x2086: '6', 0x2087: '7', 0x2088: '8', 0x2089: '9',
    0x2122: 'TM', 0x2116: 'No', 0x00AA: 'a', 0x00BA: 'o',
  };
  const roman = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII', 'L', 'C', 'D', 'M'];
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      out.writeCharCode(r - 0xFEE0);
    } else if (r >= 0x2160 && r <= 0x216F) {
      out.write(roman[r - 0x2160]);
    } else if (r >= 0x2170 && r <= 0x217F) {
      out.write(roman[r - 0x2170].toLowerCase());
    } else if (r >= 0x2460 && r <= 0x2473) {
      out.write('${r - 0x2460 + 1}');
    } else if (map[r] case final v?) {
      out.write(v);
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

final _notLetterOrNumber = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// `mf424Normalize`.
// JS lowercases İ to i + combining dot (which then splits the word); Dart to i.
String coverNorm(Object? value) => nfkcLite(value == null ? '' : '$value').replaceAll('\u0130', 'i\u0307').toLowerCase().replaceAll(_notLetterOrNumber, ' ').trim();

/// `mf424Titles`: every name a provider record carries.
List<String> coverRecordTitles(Map<String, dynamic>? x) {
  final attrs = asMap(x?['attributes']);
  final arr = <Object?>[
    x?['title'], x?['title_english'], x?['title_japanese'], x?['name'], attrs?['canonicalTitle'],
    for (final t in asList(x?['titles'])) t is String ? t : asMap(t)?['title'],
    ...asList(x?['title_synonyms']),
    ...?asMap(attrs?['titles'])?.values,
  ];
  return [for (final v in arr) if (jsTruthy(v)) '$v'];
}

/// `mf424Match`: how sure a provider record is the title (names compared
/// against the Library title; release years when both have one).
({double confidence, String reason}) coverMatch(Map<String, dynamic> item, Map<String, dynamic> entry, bool idMatch) {
  final names = coverRecordTitles(entry).map(coverNorm).toList();
  final wanted = coverNorm(cleanTitle(item['title']));
  if (idMatch) {
    return names.contains(wanted)
        ? (confidence: 1.0, reason: 'Exact saved external ID and compatible title')
        : (confidence: 0.84, reason: 'Saved ID matches, but returned title is different; manual confirmation required');
  }
  if (wanted.isEmpty || !names.contains(wanted)) return (confidence: 0.0, reason: 'Title mismatch');
  double year(Object? v) {
    final n = jsNumOrNull(v);
    return n == null || !n.isFinite ? 0 : n;
  }

  final stated = year(jsTruthy(item['year'])
      ? item['year']
      : jsTruthy(item['releaseYear'])
          ? item['releaseYear']
          : item['publicationYear']);
  final premiered = jsStr(jsTruthy(entry['premiered']) ? entry['premiered'] : asMap(entry['published'])?['from']);
  final source = year(jsTruthy(entry['year'])
      ? entry['year']
      : jsTruthy(entry['first_publish_year'])
          ? entry['first_publish_year']
          : (premiered.length > 4 ? premiered.substring(0, 4) : premiered));
  if (stated != 0 && source != 0 && stated != source) return (confidence: 0.35, reason: 'Conflicting publication years');
  if (stated != 0 && source != 0 && stated == source) return (confidence: 0.96, reason: 'Exact title and release year');
  return (confidence: 0.7, reason: 'Exact title; no independent year or creator confirmation');
}

/// How sure a search result is about the title (the v439 evidence rules
/// applied to a cover result: exact title, release year).
({double confidence, String reason}) coverEvidence(Map<String, dynamic> item, String resultTitle, int? resultYear) {
  final names = titleVariants(item).map(normTitle).where((n) => n.isNotEmpty).toSet();
  final exact = names.contains(normTitle(resultTitle));
  final userYear = yearOf(jsTruthy(item['year']) ? item['year'] : item['releaseDate']);
  final recordYear = resultYear ?? 0;
  if (userYear != 0 && recordYear != 0 && userYear != recordYear) return (confidence: 0.48, reason: 'Conflicting release years · manual review');
  if (!exact) return (confidence: 0.0, reason: 'Title did not match');
  if (userYear != 0 && recordYear != 0 && userYear == recordYear) return (confidence: 0.97, reason: 'Exact title and release year');
  return (confidence: 0.89, reason: 'Exact title only · manual review');
}

/// `mf424Missing`: the title has no cover.
bool coverMissing(Map<String, dynamic>? item) => item != null && jsStr(item['coverUrl']).trim().isEmpty;

/// `mf424Apply`: saves a recovered cover (only while the title still has none
/// and was not changed since it was checked). Returns the XP earned, or null
/// when nothing was saved.
double? applyRecoveredCover(Map<String, dynamic> state, String id, CoverCandidate c, int expectedModifiedAt, int now, String Function() uid,
    {bool manual = false, bool linkIds = true}) {
  final item = findTitle(state, id);
  if (item == null || !coverMissing(item)) return null;
  if (jsNum(item['modifiedAt']).toInt() != expectedModifiedAt) return null;
  item['coverUrl'] = c.url;
  item['coverSource'] = 'auto:${c.provider}:${c.idMatch ? 'external-id' : 'verified'}';
  // Automatic jobs link only exact-ID matches; a cover picked by the person
  // links the verified IDs it carries (website v424/v433).
  if (linkIds && (manual || (c.idMatch && c.confidence >= 0.95))) linkCoverIds(item, c, manual: manual);
  item['modifiedAt'] = now;
  return coverCredit(state, item, '', c.url, 'auto:${c.provider}', now, uid);
}

// ---------- Metadata Recovery ----------

/// `mf439Evidence`.
({double confidence, String reason}) metadataEvidence(Map<String, dynamic> item, Map<String, dynamic> row) {
  if (!jsTruthy(row['recordId']) || !jsTruthy(row['title'])) return (confidence: 0.0, reason: 'No verified provider record');
  final names = titleVariants(item).map(normTitle).where((n) => n.isNotEmpty).toList();
  final recordNames = [row['title'], ...asList(row['aliases'])].map(normTitle).where((n) => n.isNotEmpty).toList();
  final exact = names.any(recordNames.contains);
  final ids = asMap(item['externalIds']) ?? const {};
  var idMatch = false, idConflict = false;
  (asMap(row['externalIds']) ?? const {}).forEach((k, v) {
    if (!jsTruthy(v) || !jsTruthy(ids[k])) return;
    if (jsStr(ids[k]).toLowerCase() == jsStr(v).toLowerCase()) {
      idMatch = true;
    } else {
      idConflict = true;
    }
  });
  if (idConflict) return (confidence: 0.0, reason: 'Saved External ID conflicts with provider result');
  final userYear = yearOf(jsTruthy(item['year']) ? item['year'] : item['releaseDate']), recordYear = yearOf(row['year']);
  if (userYear != 0 && recordYear != 0 && userYear != recordYear) {
    return (confidence: idMatch ? 0.78 : 0.48, reason: 'Conflicting release years · manual review');
  }
  if (!exact) {
    return (confidence: idMatch ? 0.78 : 0.0, reason: idMatch ? 'Matching saved ID, but title differs · manual review' : 'Title did not match');
  }
  if (idMatch) return (confidence: 1.0, reason: 'Exact title and confirmed external ID');
  if (userYear != 0 && recordYear != 0 && userYear == recordYear) return (confidence: 0.97, reason: 'Exact title and release year');
  return (confidence: 0.89, reason: 'Exact title only · manual review');
}

/// `mf439Value` for a field token.
Object? fieldValue(String token, Object? input) {
  if (token.startsWith('rating.')) return ratingValue(token.substring(7), input);
  final def = token.startsWith('legacy.')
      ? kRecoveryFields[token.substring(7)]
      : token.startsWith('field.')
          ? kUniversalFields[token.substring(6)]
          : null;
  if (def == null) return null;
  switch (def.$2) {
    case 'number':
      final n = input is num ? input : num.tryParse(jsStr(input).trim());
      if (n == null || !n.isFinite || n <= 0 || n >= 1e9) return null;
      return n is double && n == n.truncateToDouble() ? n.toInt() : n;
    case 'list':
      final arr = input is List ? input : jsStr(input).split(',');
      final rows = stringList(arr, 40);
      return rows.isEmpty ? null : rows;
    default:
      final s = plainText(input, token == 'legacy.synopsis' ? 6000 : 750);
      return s.isEmpty ? null : s;
  }
}

/// `mf439ValueKey`.
String valueKey(Object? v) {
  if (v is Map) return '[${v['score']},${v['scale']},${v['votes']}]';
  if (v is List) return (v.map(normTitle).toList()..sort()).join('\u0001');
  return jsStr(v).trim().toLowerCase();
}

/// `mf439FieldValue`.
Object? currentFieldValue(Map<String, dynamic> item, String token) {
  if (token.startsWith('legacy.')) return item[token.substring(7)];
  final env = asMap(item['universalMetadata']);
  if (token.startsWith('field.')) return asMap(env?['fields'])?[token.substring(6)];
  if (token.startsWith('rating.')) return asMap(env?['externalRatings'])?[token.substring(7)];
  return null;
}

/// `mf439IsProtected`.
bool fieldProtected(Map<String, dynamic> item, String token) {
  if (token.startsWith('legacy.')) return asMap(item['richMetadataManual'])?[token.substring(7)] == true;
  final meta = asMap(item['universalMetadata']);
  return asMap(meta?['locks'])?[token] == true || asMap(asMap(meta?['provenance'])?[token])?['source'] == 'manual';
}

class FieldSource {
  FieldSource(this.provider, this.recordId, this.recordTitle, this.evidence, this.confidence,
      {this.year = 0, this.format = '', this.matchedName = ''});
  final String provider, recordId, recordTitle, evidence;
  final double confidence;

  /// The source record as the review shows it: its year, format and the
  /// name of it that matched the title (when not its main title).
  final int year;
  final String format, matchedName;
}

class FieldOption {
  FieldOption(this.value, this.confidence);
  final Object value;
  final List<FieldSource> sources = [];
  double confidence;
}

class FieldProposal {
  FieldProposal({
    required this.token,
    required this.label,
    required this.options,
    required this.original,
    required this.hasOriginal,
    required this.isProtected,
    required this.disagree,
    required this.same,
    required this.selected,
    required this.status,
    this.ratingUpdate = false,
  });
  final String token, label, status;
  final List<FieldOption> options;
  final Object? original;
  final bool hasOriginal, isProtected, disagree, same;

  /// 7.0.0 (website v566): an automatic external rating that recovery found a
  /// different (newer) value for. Saving it replaces the old value.
  final bool ratingUpdate;
  bool selected;
  int choice = 0;
}

/// Website v566 `mf566RatingSame`.
bool ratingSame(Object? a, Object? b) {
  final x = asMap(a), y = asMap(b);
  if (x == null || y == null) return false;
  return jsNum(x['score']) == jsNum(y['score']) && jsNum(x['scale']) == jsNum(y['scale']) && jsNumOrNull(x['votes']) == jsNumOrNull(y['votes']);
}

/// provenance.via of ratings saved by Details Recovery (website v566).
const String kRecoveryVia = 'recovery';

class MetadataPreview {
  MetadataPreview(this.titleId, this.title, this.proposals, this.errors, this.providers, [this.records = const [], this.names = const []]);
  final String titleId, title;

  /// v565: names in other languages from confident records (added on apply).
  final List<TitleName> names;
  final List<FieldProposal> proposals;
  final List<(String, String)> errors;
  final List<String> providers;

  /// The source records the values come from.
  final List<FieldSource> records;
  int get ready => proposals.where((p) => p.selected).length;
}

String _label(String token) {
  if (token.startsWith('legacy.')) return kRecoveryFields[token.substring(7)]?.$1 ?? token;
  if (token.startsWith('field.')) return kUniversalFields[token.substring(6)]?.$1 ?? token;
  if (token.startsWith('rating.')) return '${kRatingMap[token.substring(7)]?.$2 ?? token} rating';
  return token;
}

/// `mf439Proposals`.
/// [picked]: records the person chose with "Search manually" (evidence
/// "Picked by you"); existing and locked values are still never replaced.
MetadataPreview metadataProposals(Map<String, dynamic> item, List<Map<String, dynamic>> results,
    {double minimumConfidence = 0.94, bool picked = false}) {
  final bucket = <String, Map<String, FieldOption>>{};
  final errors = <(String, String)>[];
  final records = <FieldSource>[];
  final wanted = titleVariants(item).map(normTitle).where((n) => n.isNotEmpty).toSet();
  final names = <TitleName>[];
  for (final row in results) {
    final ev = picked ? (confidence: 1.0, reason: 'Picked by you') : metadataEvidence(item, row);
    // v565 (mf439Discover): keep the names of records found with confidence.
    if (!picked && ev.confidence >= minimumConfidence) {
      for (final raw in asList(row['names'])) {
        final n = asMap(raw);
        final lang = jsStr(n?['lang']), text = cleanTitle(n?['text']);
        if (text.isEmpty || !kTitleLanguageCodes.contains(lang)) continue;
        names.add((lang: lang, text: text.length > 220 ? text.substring(0, 220) : text, source: jsStr(row['provider'])));
      }
    }
    if (ev.confidence < 0.7) {
      errors.add((jsStr(row['provider']), ev.reason));
      continue;
    }
    final matched = [row['title'], ...asList(row['aliases'])].map(jsStr).firstWhere((n) => wanted.contains(normTitle(n)), orElse: () => '');
    final source = FieldSource(jsStr(row['provider']), jsStr(row['recordId']), jsStr(row['title']), ev.reason, ev.confidence,
        year: jsNum(row['year']).toInt(),
        format: jsStr(asMap(row['legacy'])?['mediaFormat']).isNotEmpty ? jsStr(asMap(row['legacy'])?['mediaFormat']) : jsStr(row['format']),
        matchedName: matched == jsStr(row['title']) ? '' : matched);
    records.add(source);
    for (final (scope, values) in [('legacy', row['legacy']), ('field', row['fields']), ('rating', row['ratings'])]) {
      (asMap(values) ?? const {}).forEach((key, original) {
        final token = '$scope.$key';
        final value = fieldValue(token, original);
        if (!hasValue(value)) return;
        final choices = bucket.putIfAbsent(token, () => {});
        final fp = valueKey(value);
        final prev = choices[fp];
        if (prev != null) {
          prev.sources.add(source);
          if (source.confidence > prev.confidence) prev.confidence = source.confidence;
        } else {
          choices[fp] = FieldOption(value!, source.confidence)..sources.add(source);
        }
      });
    }
  }
  final proposals = <FieldProposal>[];
  bucket.forEach((token, map) {
    final options = map.values.toList();
    mergeSortBy(options, (a, b) => a.confidence != b.confidence ? (b.confidence > a.confidence ? 1 : -1) : b.sources.length - a.sources.length);
    final old = currentFieldValue(item, token);
    final present = hasValue(old is Map ? old['score'] : old);
    final prot = fieldProtected(item, token);
    final same = options.every((o) => valueKey(o.value) == valueKey(old));
    final disagree = options.length > 1;
    final auto = !present && !prot && !disagree && options.first.confidence >= minimumConfidence;
    // v566: an automatic rating with a different value can be updated.
    final update = token.startsWith('rating.') && present && !prot && !same && !ratingSame(options.first.value, old);
    proposals.add(FieldProposal(
      token: token,
      label: _label(token),
      options: options,
      original: old,
      hasOriginal: present && !update,
      isProtected: prot,
      disagree: disagree,
      same: same,
      selected: update ? !disagree && options.first.confidence >= 0.7 : !same && auto,
      status: update ? 'update' : prot ? 'protected' : same ? 'unchanged' : present ? 'existing' : disagree ? 'conflict' : auto ? 'ready' : 'review',
      ratingUpdate: update,
    ));
  });
  proposals.sort((a, b) => a.token == 'legacy.synopsis' ? -1 : b.token == 'legacy.synopsis' ? 1 : localeCompare(a.token, b.token));
  return MetadataPreview(jsStr(item['id']), cleanTitle(item['title']), proposals, errors, [...{...results.map((r) => jsStr(r['provider']))}], records, names);
}

/// `mf439Discover`: asks each source with up to five names, stopping at the
/// first confident record.
Future<({List<Map<String, dynamic>> results, List<(String, String)> failures})> discoverMetadata(
  Map<String, dynamic> item,
  List<String> providers,
  SourceLookup lookup, {
  double minimumConfidence = 0.94,
  StopToken? stop,
  void Function(String provider)? progress,
}) async {
  final results = <Map<String, dynamic>>[];
  final failures = <(String, String)>[];
  final variants = <String>[];
  for (final v in titleVariants(item)) {
    final t = v.trim();
    if (t.isNotEmpty && !variants.contains(t)) variants.add(t);
  }
  final names = variants.isEmpty ? [jsStr(item['title'])] : variants.take(5).toList();
  for (final provider in providers) {
    if (stop?.stopped == true) break;
    progress?.call(provider);
    final rows = <String, Map<String, dynamic>>{};
    for (final name in names.where((n) => n.isNotEmpty)) {
      if (stop?.stopped == true) break;
      try {
        final query = name == jsStr(item['title']) ? item : {...item, 'title': name};
        for (final row in await lookup(provider, query)) {
          final key = '${row['provider'] ?? provider}:${row['recordId'] ?? ''}';
          if (jsTruthy(row['recordId'])) rows.putIfAbsent(key, () => row);
        }
        if (rows.values.any((r) => metadataEvidence(item, r).confidence >= minimumConfidence)) break;
      } on RatingsStopped {
        rethrow;
      } catch (e) {
        failures.add((provider, '$e'.replaceFirst('Exception: ', '')));
        break;
      }
    }
    results.addAll(rows.values);
  }
  return (results: results, failures: failures);
}

/// `mf439Apply`: writes the selected proposals into [item] (in place). Never
/// replaces a value that is already there. Returns how many fields changed.
({int changed, int legacy, int fields, int ratings}) applyMetadata(Map<String, dynamic> item, MetadataPreview preview, int now,
    {bool automatic = false, double minimumConfidence = 0.94}) {
  if (jsStr(item['id']) != preview.titleId) return (changed: 0, legacy: 0, fields: 0, ratings: 0);
  var count = 0, legacy = 0, fields = 0, ratings = 0;
  final env = normalizedEnvelope(item['universalMetadata']);
  for (final prop in preview.proposals) {
    if (!prop.selected || prop.same || prop.isProtected || fieldProtected(item, prop.token)) continue;
    final choice = prop.choice < prop.options.length ? prop.options[prop.choice] : prop.options.first;
    final src = choice.sources.isEmpty ? null : choice.sources.first;
    if (src == null || src.confidence < 0.7) continue;
    if (automatic && (prop.hasOriginal || prop.disagree || src.confidence < minimumConfidence)) continue;
    if (prop.hasOriginal) continue;
    if (prop.ratingUpdate) {
      // v566: replace an automatic rating with the newer value recovery found.
      final key = prop.token.substring(7);
      final value = asMap(choice.value);
      if (value == null || ratingSame(value, asMap(env['externalRatings'])?[key])) continue;
      if (setRatingInEnvelope(env, key, value, source: src.provider, force: true, updatedAt: now)) {
        (env['provenance'] as Map<String, dynamic>)[prop.token] = {
          'source': src.provider,
          'verified': true,
          'recordId': src.recordId,
          'updatedAt': now,
          'via': kRecoveryVia,
        };
        ratings++;
        count++;
      }
      continue;
    }
    final current = currentFieldValue(item, prop.token);
    if (hasValue(current is Map ? current['score'] : current)) continue;
    var applied = false;
    if (prop.token.startsWith('legacy.')) {
      final key = prop.token.substring(7);
      if (!kRecoveryFields.containsKey(key)) continue;
      item[key] = jsonClone(choice.value);
      legacy++;
      count++;
      applied = true;
    } else if (prop.token.startsWith('field.')) {
      if (setFieldInEnvelope(env, prop.token.substring(6), choice.value, source: src.provider, updatedAt: now)) {
        fields++;
        count++;
        applied = true;
      }
    } else if (prop.token.startsWith('rating.')) {
      if (setRatingInEnvelope(env, prop.token.substring(7), asMap(choice.value)!, source: src.provider, force: false, updatedAt: now)) {
        ratings++;
        count++;
        applied = true;
      }
    }
    if (applied) {
      (env['provenance'] as Map<String, dynamic>)[prop.token] = {
        'source': src.provider,
        'verified': true,
        'recordId': src.recordId,
        'evidence': src.evidence,
        'updatedAt': now,
        // v566: ratings saved by recovery are marked, so a later refresh updates them.
        if (prop.token.startsWith('rating.')) 'via': kRecoveryVia,
      };
    }
  }
  if (count > 0) {
    item['universalMetadata'] = env;
    final m = jsNum(item['modifiedAt']);
    item['modifiedAt'] = m > now ? jsOut(m) : now;
    final history = asList(item['v439RecoveryHistory']);
    final kept = history.length > 24 ? history.sublist(history.length - 24) : List<dynamic>.of(history);
    final providers = <String>[];
    for (final p in preview.proposals.where((p) => p.selected)) {
      final opt = p.choice < p.options.length ? p.options[p.choice] : null;
      for (final s in opt?.sources ?? const <FieldSource>[]) {
        if (!providers.contains(s.provider)) providers.add(s.provider);
      }
    }
    kept.add({'at': now, 'legacy': legacy, 'fields': fields, 'ratings': ratings, 'providers': providers.take(20).toList()});
    item['v439RecoveryHistory'] = kept;
  }
  // v565: add the names this title doesn't have yet (never removes or edits one).
  final added = addTitleNames(item, preview.names);
  if (added > 0) {
    final m = jsNum(item['modifiedAt']);
    item['modifiedAt'] = m > now ? jsOut(m) : now;
  }
  return (changed: count > 0 ? count : added, legacy: legacy, fields: fields, ratings: ratings);
}

/// `mf439DescribeValue`: a field value as text.
String describeFieldValue(String token, Object? v) {
  if (v == null || v == '') return '—';
  if (token.startsWith('rating.') && v is Map) {
    final votes = v['votes'];
    return '${jsStr(v['score'])} / ${jsStr(v['scale'])}${votes != null ? ' · ${jsStr(votes)} votes' : ''}';
  }
  if (v is List) return v.map(jsStr).join(', ');
  return jsStr(v);
}

/// `String.prototype.localeCompare` for field tokens (ASCII): letters
/// compare case-insensitively, lowercase first on a tie.
int localeCompare(String a, String b) {
  final c = a.toLowerCase().compareTo(b.toLowerCase());
  if (c != 0) return c;
  return b.compareTo(a); // 'a' (97) sorts before 'A' (65)
}

num? _whole(num n) => n == n.truncateToDouble() ? n.toInt() : n;

/// `mf437Clean`.
Object? cleanUniversalField(Object? value, String type) {
  switch (type) {
    case 'list':
      final raw = value is List ? value : jsStr(value ?? '').split(',');
      final out = <String>[];
      for (final v in raw) {
        var s = jsStr(v ?? '').trim();
        if (s.length > 180) s = s.substring(0, 180);
        if (s.isNotEmpty && !out.contains(s)) out.add(s);
      }
      return out.length > 100 ? out.sublist(0, 100) : out;
    case 'number':
    case 'decimal':
      if (value == null || jsStr(value).trim().isEmpty) return null;
      final n = value is num ? value : num.tryParse(jsStr(value).trim());
      if (n == null || !n.isFinite || n < 0 || n > 1e9) return null;
      return type == 'number' ? n.floor() : _whole((n * 100).round() / 100);
    case 'url':
      final str = jsStr(value ?? '').trim();
      if (str.isEmpty) return '';
      final u = Uri.tryParse(str);
      if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) return '';
      var href = u.toString();
      if (u.path.isEmpty) href = u.replace(path: '/').toString();
      return href.length > 1200 ? href.substring(0, 1200) : href;
    default:
      final s = jsStr(value ?? '').trim();
      final max = type == 'multiline' ? 12000 : 800;
      return s.length > max ? s.substring(0, max) : s;
  }
}

/// `mf437SetField` with source 'manual' (the title editor): replaces the
/// value, records manual provenance and locks the field against recovery.
bool setFieldManually(Map<String, dynamic> env, String key, Object? value, int updatedAt) {
  final def = kUniversalFields[key];
  if (def == null) return false;
  final clean = cleanUniversalField(value, def.$2);
  final fields = env['fields'] as Map;
  if (jsonEncode(clean) == jsonEncode(fields[key])) return false;
  final token = 'field.$key';
  fields[key] = clean;
  (env['provenance'] as Map)[token] = {'source': 'manual', 'verified': false, 'updatedAt': updatedAt};
  (env['locks'] as Map)[token] = true;
  final u = jsNum(env['updatedAt']);
  env['updatedAt'] = u > updatedAt ? env['updatedAt'] : updatedAt;
  return true;
}

/// `mf437SetField` for a verified provider value (never replaces a value
/// that is there, never touches a locked field).
bool setFieldInEnvelope(Map<String, dynamic> env, String key, Object? value, {required String source, required int updatedAt}) {
  final def = kUniversalFields[key];
  if (def == null) return false;
  final clean = cleanUniversalField(value, def.$2);
  final token = 'field.$key';
  final locks = env['locks'] as Map;
  final fields = env['fields'] as Map;
  if (locks[token] == true) return false;
  final cur = fields[key];
  final present = cur != null && cur != '' && (cur is! List || cur.isNotEmpty);
  if (present) return false;
  if (jsonEncode(clean) == jsonEncode(cur)) return false;
  fields[key] = clean;
  (env['provenance'] as Map)[token] = {'source': source, 'verified': true, 'updatedAt': updatedAt};
  final u = jsNum(env['updatedAt']);
  env['updatedAt'] = u > updatedAt ? env['updatedAt'] : updatedAt;
  return true;
}
