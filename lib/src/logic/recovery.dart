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

import '../util/js.dart';
import 'library_logic.dart' show coverCredit, findTitle;
import 'ratings_engine.dart';

// ---------- shared ----------

/// `MF439_LEGACY_FIELDS`: the Library fields Metadata Recovery may fill.
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
      this.idMatch = false});
  final String url, provider, title, reason;
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
      final s => s.replaceAll(' ', ''),
    };

/// `mf424AsCandidate`'s externalIdKey for the app's sources.
String coverExternalIdKey(String provider) =>
    const {'anilist': 'anilist', 'tvmaze': 'tvmaze', 'openlibrary': 'openlibrary', 'jikan': 'mal', 'tenrai': 'mal', 'kitsu': 'kitsu'}[provider] ?? '';

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
  if (!token.startsWith('legacy.')) return null;
  final def = kRecoveryFields[token.substring(7)];
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
  FieldSource(this.provider, this.recordId, this.recordTitle, this.evidence, this.confidence);
  final String provider, recordId, recordTitle, evidence;
  final double confidence;
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
  });
  final String token, label, status;
  final List<FieldOption> options;
  final Object? original;
  final bool hasOriginal, isProtected, disagree, same;
  bool selected;
  int choice = 0;
}

class MetadataPreview {
  MetadataPreview(this.titleId, this.title, this.proposals, this.errors, this.providers);
  final String titleId, title;
  final List<FieldProposal> proposals;
  final List<(String, String)> errors;
  final List<String> providers;
  int get ready => proposals.where((p) => p.selected).length;
}

String _label(String token) {
  if (token.startsWith('legacy.')) return kRecoveryFields[token.substring(7)]?.$1 ?? token;
  if (token.startsWith('rating.')) return '${kRatingMap[token.substring(7)]?.$2 ?? token} rating';
  return token;
}

/// `mf439Proposals`.
MetadataPreview metadataProposals(Map<String, dynamic> item, List<Map<String, dynamic>> results, {double minimumConfidence = 0.94}) {
  final bucket = <String, Map<String, FieldOption>>{};
  final errors = <(String, String)>[];
  for (final row in results) {
    final ev = metadataEvidence(item, row);
    if (ev.confidence < 0.7) {
      errors.add((jsStr(row['provider']), ev.reason));
      continue;
    }
    final source = FieldSource(jsStr(row['provider']), jsStr(row['recordId']), jsStr(row['title']), ev.reason, ev.confidence);
    for (final (scope, values) in [('legacy', row['legacy']), ('rating', row['ratings'])]) {
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
    proposals.add(FieldProposal(
      token: token,
      label: _label(token),
      options: options,
      original: old,
      hasOriginal: present,
      isProtected: prot,
      disagree: disagree,
      same: same,
      selected: !same && auto,
      status: prot ? 'protected' : same ? 'unchanged' : present ? 'existing' : disagree ? 'conflict' : auto ? 'ready' : 'review',
    ));
  });
  proposals.sort((a, b) => a.token == 'legacy.synopsis' ? -1 : b.token == 'legacy.synopsis' ? 1 : a.token.compareTo(b.token));
  return MetadataPreview(jsStr(item['id']), cleanTitle(item['title']), proposals, errors, [...{...results.map((r) => jsStr(r['provider']))}]);
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
({int changed, int legacy, int ratings}) applyMetadata(Map<String, dynamic> item, MetadataPreview preview, int now,
    {bool automatic = false, double minimumConfidence = 0.94}) {
  if (jsStr(item['id']) != preview.titleId) return (changed: 0, legacy: 0, ratings: 0);
  var count = 0, legacy = 0, ratings = 0;
  final env = normalizedEnvelope(item['universalMetadata']);
  for (final prop in preview.proposals) {
    if (!prop.selected || prop.same || prop.isProtected || fieldProtected(item, prop.token)) continue;
    final choice = prop.choice < prop.options.length ? prop.options[prop.choice] : prop.options.first;
    final src = choice.sources.isEmpty ? null : choice.sources.first;
    if (src == null || src.confidence < 0.7) continue;
    if (automatic && (prop.hasOriginal || prop.disagree || src.confidence < minimumConfidence)) continue;
    if (prop.hasOriginal) continue;
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
    kept.add({'at': now, 'legacy': legacy, 'fields': 0, 'ratings': ratings, 'providers': providers.take(20).toList()});
    item['v439RecoveryHistory'] = kept;
  }
  return (changed: count, legacy: legacy, ratings: ratings);
}
