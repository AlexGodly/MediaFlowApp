// Online title search for covers and totals, using the same sources as the
// website: Tenrai / Jikan (MyAnimeList), AniList, Kitsu, MangaDex, TVmaze,
// Open Library, iTunes, and through MediaFlow's provider gateway (keys stay on
// the server) TMDB, OMDb, Fanart.tv, EpisoDate, AnimeSchedule, MyAnimeList
// Official and Gutendex. Results only fill the
// editor; nothing is saved until you save the title.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class MetadataResult {
  MetadataResult(
      {required this.title,
      required this.source,
      this.coverUrl = '',
      this.total,
      this.year,
      this.subtitle = '',
      this.externalId,
      this.externalIdKey = '',
      this.linkedIds = const [],
      this.altTitles = const [],
      this.recordYear,
      this.idMatch = false});
  final String title, source, coverUrl, subtitle;
  final int? total, year;
  final String? externalId;

  /// The ID key the source reports for [externalId] (TMDB: tmdb / tmdb_tv).
  final String externalIdKey;

  /// Other IDs the source itself reports for the record, in the website's
  /// order (AniList's MAL ID, TVmaze's IMDb ID); used to link verified IDs.
  final List<(String, String)> linkedIds;

  /// The record's other names (AniList English/native/synonyms, Kitsu's
  /// titles…). Cover Recovery compares every one (website `mf424Titles`).
  final List<String> altTitles;

  /// The year the website's adapter reads for matching (AniList startDate),
  /// when it differs from [year].
  final int? recordYear;

  /// Found by a saved External ID (not by name).
  final bool idMatch;

  /// The record as the website's cover adapters hand it to `mf424Match`.
  Map<String, dynamic> get matchRecord => {'title': title, 'titles': altTitles, 'year': recordYear ?? year ?? 0};
}

Future<Object?> _getJson(Uri uri, {Map<String, dynamic>? post}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = post == null ? await client.getUrl(uri) : await client.postUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (post != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(post));
    }
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 12));
    return jsonDecode(body);
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<List<MetadataResult>> _anilist(String q, String type) async {
  const query = 'query(\$s:String,\$t:MediaType){Page(perPage:12){media(search:\$s,type:\$t){$_anilistFields}}}';
  final data = await _getJson(Uri.parse('https://graphql.anilist.co'), post: {'query': query, 'variables': {'s': q, 't': type}});
  return _anilistRows(data, type);
}

const _anilistFields = 'id idMal title{romaji english native} synonyms coverImage{extraLarge large} episodes chapters volumes seasonYear startDate{year} format';

List<MetadataResult> _anilistRows(Object? data, String type, {int? id, int? idMal}) {
  final media = (((data as Map?)?['data'] as Map?)?['Page'] as Map?)?['media'] as List? ?? const [];
  return [
    for (final m in media.whereType<Map>())
      MetadataResult(
        altTitles: [
          for (final t in [(m['title'] as Map?)?['romaji'], (m['title'] as Map?)?['english'], (m['title'] as Map?)?['native'], ...(m['synonyms'] as List? ?? const [])])
            if (t is String && t.isNotEmpty) t,
        ],
        recordYear: (m['startDate'] as Map?)?['year'] as int?,
        idMatch: (id != null && m['id'] == id) || (id == null && idMal != null && m['idMal'] == idMal),
        title: ((m['title'] as Map?)?['english'] ?? (m['title'] as Map?)?['romaji'] ?? '').toString(),
        subtitle: [m['format'], (m['title'] as Map?)?['romaji']].whereType<Object>().map((e) => '$e').where((e) => e.isNotEmpty).join(' · '),
        coverUrl: ((m['coverImage'] as Map?)?['extraLarge'] ?? (m['coverImage'] as Map?)?['large'] ?? '').toString(),
        total: (type == 'ANIME' ? m['episodes'] : m['chapters']) as int?,
        year: (m['seasonYear'] ?? (m['startDate'] as Map?)?['year']) as int?,
        source: 'AniList',
        externalId: '${m['id']}',
        linkedIds: [if (m['idMal'] != null && m['idMal'] != 0) ('mal', '${m['idMal']}')],
      ),
  ];
}

Future<List<MetadataResult>> _tvmaze(String q) async {
  final data = await _getJson(Uri.https('api.tvmaze.com', '/search/shows', {'q': q}));
  return [for (final r in (data as List? ?? const []).whereType<Map>()) if (r['show'] is Map) _tvmazeRow(r['show'] as Map)];
}

MetadataResult _tvmazeRow(Map show, {bool idMatch = false}) => MetadataResult(
      title: '${show['name'] ?? ''}',
      subtitle: [show['network'] is Map ? (show['network'] as Map)['name'] : null, show['type']].whereType<Object>().join(' · '),
      coverUrl: '${(show['image'] as Map?)?['original'] ?? (show['image'] as Map?)?['medium'] ?? ''}',
      year: int.tryParse('${show['premiered'] ?? ''}'.split('-').first),
      source: 'TVMaze',
      externalId: '${show['id']}',
      idMatch: idMatch,
      linkedIds: [
        if ((show['externals'] as Map?)?['imdb'] case final imdb? when '$imdb'.isNotEmpty) ('imdb', '$imdb'),
      ],
    );

Future<List<MetadataResult>> _openLibrary(String q) async {
  final data = await _getJson(Uri.https('openlibrary.org', '/search.json', {'q': q, 'limit': '12'}));
  return [
    for (final d in ((data as Map?)?['docs'] as List? ?? const []).whereType<Map>())
      MetadataResult(
        title: '${d['title'] ?? ''}',
        subtitle: (d['author_name'] as List?)?.take(2).join(', ') ?? '',
        coverUrl: d['cover_i'] == null ? '' : 'https://covers.openlibrary.org/b/id/${d['cover_i']}-L.jpg',
        total: d['number_of_pages_median'] as int?,
        year: d['first_publish_year'] as int?,
        source: 'Open Library',
        externalId: '${d['key'] ?? ''}',
      ),
  ];
}

Future<List<MetadataResult>> _itunes(String q, String entity) async {
  final data = await _getJson(Uri.https('itunes.apple.com', '/search', {'term': q, 'entity': entity, 'limit': '12'}));
  return [
    for (final r in ((data as Map?)?['results'] as List? ?? const []).whereType<Map>())
      MetadataResult(
        title: '${r['trackName'] ?? r['collectionName'] ?? ''}',
        subtitle: '${r['artistName'] ?? r['primaryGenreName'] ?? ''}',
        coverUrl: '${r['artworkUrl100'] ?? ''}'.replaceAll('100x100', '600x600'),
        total: entity == 'album' ? r['trackCount'] as int? : 1,
        year: int.tryParse('${r['releaseDate'] ?? ''}'.split('-').first),
        source: 'iTunes',
        externalId: '${r['trackId'] ?? r['collectionId'] ?? ''}',
      ),
  ];
}

/// Calls MediaFlow's provider gateway (the Supabase edge function
/// `mediaflow-api-gateway`) as the signed-in user and returns its JSON. Set by
/// the app at start-up; null (tests, signed out) skips the gateway sources.
typedef GatewayCall = Future<Object?> Function(Map<String, dynamic> body);
GatewayCall? providerGateway;

/// `mf559MediaKind`: which TMDB catalogue to search first.
String tmdbKind({required String categoryId, required String categoryName, Map<String, dynamic>? externalIds}) {
  final name = '$categoryId $categoryName'.toLowerCase();
  if (RegExp(r'^[1-9]\d*$').hasMatch('${externalIds?['tmdb_tv'] ?? ''}')) return 'tv';
  if (RegExp(r'movie|film').hasMatch(name)) return 'movie';
  if (RegExp(r'\btv\b|television|series|show').hasMatch(name)) return 'tv';
  return '';
}

/// The gateway's cover providers (website `MF434_COVER`) and their names.
const kGatewayCoverProviders = {
  'tmdb': 'TMDB', 'omdb': 'OMDb', 'fanart': 'Fanart.tv', 'animeschedule': 'AnimeSchedule',
  'malofficial': 'MyAnimeList Official', 'episodate': 'EpisoDate', 'gutendex': 'Gutendex',
};

/// Gateway providers that are configured and usable (website `status` action),
/// cached for 20 minutes. TMDB is assumed usable when the status is unknown.
Map<String, ({bool configured, bool testable})>? _gatewayStatus;
DateTime? _gatewayStatusAt;

Future<Map<String, ({bool configured, bool testable})>>? _gatewayStatusLoading;

Future<Map<String, ({bool configured, bool testable})>> gatewayStatus({bool refresh = false}) {
  final call = providerGateway;
  if (call == null) return Future.value(const {});
  final fresh = _gatewayStatusAt != null && DateTime.now().difference(_gatewayStatusAt!) < const Duration(minutes: 20);
  if (!refresh && fresh && _gatewayStatus != null) return Future.value(_gatewayStatus!);
  return _gatewayStatusLoading ??= _loadGatewayStatus(call).whenComplete(() => _gatewayStatusLoading = null);
}

Future<Map<String, ({bool configured, bool testable})>> _loadGatewayStatus(GatewayCall call) async {
  try {
    final data = await call({'action': 'status'});
    final rows = data is Map ? data['providers'] : null;
    final out = <String, ({bool configured, bool testable})>{};
    if (rows is List) {
      for (final r in rows.whereType<Map>()) {
        out['${r['id']}'] = (configured: r['configured'] == true, testable: r['testable'] == true);
      }
    }
    _gatewayStatus = out;
    _gatewayStatusAt = DateTime.now();
  } catch (_) {
    _gatewayStatus ??= const {};
    _gatewayStatusAt = DateTime.now();
  }
  return _gatewayStatus!;
}

Future<bool> _gatewayReady(String provider) async {
  final st = await gatewayStatus();
  if (st.isEmpty) return provider == 'tmdb';
  final p = st[provider];
  return p != null && p.configured && p.testable;
}

/// One provider's search through the gateway (website v434 `mf434Find` + v559).
/// A manual search asks for close matches too (`loose`), like the website's ID
/// finder; saved IDs are looked up first. Throws only when [rethrowErrors].
Future<List<MetadataResult>> searchGateway(String provider, String q,
    {String kind = '', Map<String, dynamic>? externalIds, bool rethrowErrors = false, bool checkReady = true}) async {
  final call = providerGateway;
  final title = q.length > 110 ? q.substring(0, 110).trim() : q;
  if (call == null || title.length < 2) return const [];
  if (checkReady && !await _gatewayReady(provider)) return const [];
  final ids = <String, String>{};
  externalIds?.forEach((k, v) {
    final value = '${v ?? ''}'.trim();
    if (RegExp(r'^[a-z][a-z0-9_]{0,32}$').hasMatch(k) && RegExp(r'^[\w.:-]{1,120}$').hasMatch(value)) ids[k] = value;
  });
  final body = <String, dynamic>{
    'action': 'search',
    'provider': provider,
    'title': title,
    'externalIds': ids,
    if (provider == 'tmdb') 'loose': true,
    if (provider == 'tmdb' && kind.isNotEmpty) 'kind': kind,
  };
  Object? data;
  try {
    data = await call(body);
  } catch (e) {
    // The gateway allows one request a second per account: wait and retry once.
    if (!RegExp(r'Please wait \d+ seconds?', caseSensitive: false).hasMatch('$e')) {
      if (rethrowErrors) rethrow;
      return const [];
    }
    final seconds = int.tryParse(RegExp(r'\d+').firstMatch('$e')?[0] ?? '') ?? 1;
    await Future<void>.delayed(Duration(milliseconds: (seconds * 1000 + 250).clamp(0, 5000)));
    try {
      data = await call(body);
    } catch (_) {
      if (rethrowErrors) rethrow;
      return const [];
    }
  }
  final rows = (data is Map ? data['results'] : null);
  if (rows is! List) return const [];
  final name = kGatewayCoverProviders[provider] ?? provider;
  final out = <MetadataResult>[];
  for (final raw in rows) {
    if (raw is! Map || raw['provider'] != provider) continue;
    final url = '${raw['url'] ?? ''}';
    final year = raw['year'] is num && (raw['year'] as num) > 0 ? (raw['year'] as num).toInt() : null;
    final tv = raw['externalIdKey'] == 'tmdb_tv';
    out.add(MetadataResult(
      title: '${raw['title'] ?? ''}',
      source: name,
      coverUrl: url.startsWith('https://') ? url : '',
      year: year,
      subtitle: [
        if (provider == 'tmdb') tv ? 'TV' : 'Movie',
        if (provider == 'tmdb' && raw['exact'] != true) 'similar title',
      ].join(' · '),
      externalId: '${raw['externalIdValue'] ?? ''}',
      externalIdKey: '${raw['externalIdKey'] ?? ''}',
    ));
  }
  // Exact matches and ones with a poster first.
  out.sort((a, b) {
    int score(MetadataResult r) => (r.subtitle.contains('similar') ? 0 : 2) + (r.coverUrl.isEmpty ? 0 : 1);
    return score(b) - score(a);
  });
  return out;
}

/// TMDB posters through the gateway.
Future<List<MetadataResult>> searchTmdb(String q, {String kind = '', Map<String, dynamic>? externalIds}) =>
    searchGateway('tmdb', q, kind: kind, externalIds: externalIds, checkReady: false);

// ---- MyAnimeList (Tenrai, Jikan), Kitsu, MangaDex (website mf424DiscoverKind) ----

List<MetadataResult> _malRows(Object? data, String source, {String? id}) {
  final d = (data as Map?)?['data'];
  final rows = id != null ? [d] : (d is List ? d : const []);
  return [
    for (final x in rows.whereType<Map>())
      if (id == null || '${x['mal_id']}' == id)
        MetadataResult(
          title: '${x['title_english'] ?? x['title'] ?? ''}',
          altTitles: [
            for (final t in [x['title'], x['title_english'], x['title_japanese'], ...((x['title_synonyms'] as List?) ?? const []),
              for (final o in ((x['titles'] as List?) ?? const [])) if (o is Map) o['title']])
              if (t is String && t.isNotEmpty) t,
          ],
          subtitle: [x['type'], x['title']].whereType<Object>().map((e) => '$e').where((e) => e.isNotEmpty).join(' · '),
          coverUrl: '${((x['images'] as Map?)?['jpg'] as Map?)?['large_image_url'] ?? ((x['images'] as Map?)?['webp'] as Map?)?['large_image_url'] ?? ((x['images'] as Map?)?['jpg'] as Map?)?['image_url'] ?? ''}',
          total: (x['episodes'] ?? x['chapters']) is int ? (x['episodes'] ?? x['chapters']) as int : null,
          year: x['year'] is int ? x['year'] as int : int.tryParse('${((x['aired'] ?? x['published']) as Map?)?['from'] ?? ''}'.split('-').first),
          source: source,
          externalId: '${x['mal_id']}',
          externalIdKey: 'mal',
          idMatch: id != null,
        ),
  ];
}

/// Tenrai (MAL, the website's first cover source) — Jikan when Tenrai is down.
Future<List<MetadataResult>> _mal(String q, String type, {String? id}) async {
  Uri uri(String host, String base) =>
      id != null ? Uri.https(host, '$base/$type/$id') : Uri.https(host, '$base/$type', {'q': q, 'limit': '8'});
  final tenrai = await _getJson(uri('api.tenrai.org', '/v1'));
  if (tenrai != null) return _malRows(tenrai, 'Tenrai', id: id);
  return _malRows(await _getJson(uri('api.jikan.moe', '/v4')), 'Jikan', id: id);
}

MetadataResult _kitsuRow(Map x, String type, {bool idMatch = false}) {
  final a = (x['attributes'] as Map?) ?? const {};
  final poster = (a['posterImage'] as Map?) ?? const {};
  return MetadataResult(
    title: '${a['canonicalTitle'] ?? ''}',
    altTitles: [for (final t in ((a['titles'] as Map?) ?? const {}).values) if (t is String && t.isNotEmpty) t],
    coverUrl: '${poster['original'] ?? poster['large'] ?? poster['medium'] ?? ''}',
    total: (a['episodeCount'] ?? a['chapterCount']) is int ? (a['episodeCount'] ?? a['chapterCount']) as int : null,
    year: int.tryParse('${a['startDate'] ?? ''}'.split('-').first),
    subtitle: '${a['subtype'] ?? ''}',
    source: 'Kitsu',
    externalId: '${x['id']}',
    externalIdKey: 'kitsu',
    idMatch: idMatch,
  );
}

Future<List<MetadataResult>> _kitsu(String q, String type) async {
  final data = await _getJson(Uri.https('kitsu.io', '/api/edge/$type', {'filter[text]': q, 'page[limit]': '8'}));
  return [for (final x in (((data as Map?)?['data'] as List?) ?? const []).whereType<Map>()) _kitsuRow(x, type)];
}

List<MetadataResult> _mangadexRows(Object? data, {String? id}) {
  final d = (data as Map?)?['data'];
  final rows = id != null ? [d] : (d is List ? d : const []);
  return [
    for (final x in rows.whereType<Map>())
      () {
        final attrs = (x['attributes'] as Map?) ?? const {};
        final cover = ((x['relationships'] as List?) ?? const []).whereType<Map>().where((r) => r['type'] == 'cover_art').firstOrNull;
        final file = (cover?['attributes'] as Map?)?['fileName'];
        final titles = [
          ...((attrs['title'] as Map?) ?? const {}).values,
          for (final o in ((attrs['altTitles'] as List?) ?? const [])) if (o is Map) ...o.values,
        ].whereType<String>().where((t) => t.isNotEmpty).toList();
        return MetadataResult(
          title: titles.isEmpty ? '' : titles.first,
          altTitles: titles,
          coverUrl: file == null ? '' : 'https://uploads.mangadex.org/covers/${x['id']}/$file',
          year: attrs['year'] is int ? attrs['year'] as int : null,
          subtitle: '${attrs['publicationDemographic'] ?? ''}',
          source: 'MangaDex',
          externalId: '${x['id']}',
          externalIdKey: 'mangadex',
          idMatch: id != null && '${x['id']}' == id,
        );
      }(),
  ];
}

Future<List<MetadataResult>> _mangadex(String q) async => _mangadexRows(await _getJson(
    Uri.https('api.mangadex.org', '/manga', {'title': q, 'limit': '8', 'includes[]': 'cover_art'})));

/// The cover sources the account has turned on (settings.v424Covers.enabled,
/// website default: Tenrai, Jikan, AniList, Kitsu, TVmaze, Open Library).
/// Gateway providers are used whenever they are configured.
const kDefaultCoverSources = ['tenrai', 'jikan', 'anilist', 'kitsu', 'tvmaze', 'openlibrary'];
Set<String> enabledCoverSources(Map<String, dynamic>? settings) {
  final v = (settings?['v424Covers'] as Map?)?['enabled'];
  final list = v is List ? [for (final x in v) '$x'] : kDefaultCoverSources;
  return {...list, 'itunes'};
}

/// Searches the sources that fit a category ([unit] and media [type]), using
/// the cover sources in [enabled] (all of them when null). TMDB and the other
/// gateway providers are used when configured ([tmdbKind] picks movie or TV).
Future<List<MetadataResult>> searchMetadata(String query,
    {required String unit, String type = '', String kind = '', Map<String, dynamic>? externalIds, Set<String>? enabled}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  bool on(String id) => enabled == null || enabled.contains(id);
  Future<List<MetadataResult>> gw(String id) => searchGateway(id, q, kind: kind, externalIds: externalIds, checkReady: id != 'tmdb');
  final mal = on('tenrai') || on('jikan');
  final List<Future<List<MetadataResult>>> jobs;
  switch (unit) {
    case 'chapters':
      jobs = [if (mal) _mal(q, 'manga'), if (on('anilist')) _anilist(q, 'MANGA'), if (on('kitsu')) _kitsu(q, 'manga'), if (on('mangadex')) _mangadex(q)];
    case 'pages':
    case 'volumes':
      jobs = [
        if (on('openlibrary')) _openLibrary(q), gw('gutendex'),
        if (on('anilist')) _anilist(q, 'MANGA'), if (mal) _mal(q, 'manga'), if (on('mangadex')) _mangadex(q),
      ];
    case 'issues':
      jobs = [if (on('openlibrary')) _openLibrary(q)];
    case 'movies':
      jobs = [gw('tmdb'), gw('omdb'), gw('fanart'), _itunes(q, 'movie'), if (on('anilist')) _anilist(q, 'ANIME'), if (mal) _mal(q, 'anime')];
    case 'tracks':
    case 'albums':
      jobs = [_itunes(q, 'album')];
    default:
      jobs = type == 'reading'
          ? [if (on('openlibrary')) _openLibrary(q), gw('gutendex')]
          : [
              gw('tmdb'), gw('omdb'), gw('fanart'), gw('episodate'), gw('animeschedule'), gw('malofficial'),
              if (mal) _mal(q, 'anime'), if (on('anilist')) _anilist(q, 'ANIME'), if (on('kitsu')) _kitsu(q, 'anime'),
              if (on('tvmaze')) _tvmaze(q),
            ];
  }
  final results = await Future.wait(jobs.map((j) => j.catchError((_) => <MetadataResult>[])));
  return [for (final r in results) ...r.where((x) => x.title.isNotEmpty)];
}

/// Records found by the title's saved External IDs (website v424: "existing
/// IDs get first chance"): AniList / MyAnimeList, Kitsu, TVmaze / IMDb and an
/// Open Library ISBN cover. Each result is marked [MetadataResult.idMatch].
Future<List<MetadataResult>> lookupByIds(Map<String, dynamic>? externalIds, {required String unit}) async {
  String id(String k) => '${externalIds?[k] ?? ''}'.trim();
  final manga = const ['chapters', 'volumes'].contains(unit);
  final jobs = <Future<List<MetadataResult>>>[];
  final aid = int.tryParse(id('anilist')), mal = int.tryParse(id('mal'));
  if (aid != null || mal != null) {
    for (final type in manga ? const ['MANGA', 'ANIME'] : const ['ANIME', 'MANGA']) {
      jobs.add(() async {
        final q = 'query(\$id:Int,\$idMal:Int,\$type:MediaType){Page(perPage:8){media(id:\$id,idMal:\$idMal,type:\$type){$_anilistFields}}}';
        final data = await _getJson(Uri.parse('https://graphql.anilist.co'),
            post: {'query': q, 'variables': {'id': aid, 'idMal': aid != null ? null : mal, 'type': type}});
        return _anilistRows(data, type, id: aid, idMal: mal);
      }());
    }
  }
  if (mal != null) jobs.add(_mal('', manga ? 'manga' : 'anime', id: '$mal'));
  final mdex = id('mangadex');
  if (RegExp(r'^[0-9a-f-]{36}$').hasMatch(mdex)) {
    jobs.add((() async => _mangadexRows(
        await _getJson(Uri.https('api.mangadex.org', '/manga/$mdex', {'includes[]': 'cover_art'})), id: mdex))());
  }
  final kitsu = id('kitsu');
  if (RegExp(r'^\d+$').hasMatch(kitsu)) {
    jobs.add(() async {
      final data = await _getJson(Uri.https('kitsu.io', '/api/edge/${manga ? 'manga' : 'anime'}/$kitsu'));
      final x = (data as Map?)?['data'];
      if (x is! Map || '${x['id']}' != kitsu) return <MetadataResult>[];
      return [_kitsuRow(x, manga ? 'manga' : 'anime', idMatch: true)];
    }());
  }
  final tvmaze = id('tvmaze'), imdb = id('imdb');
  if (RegExp(r'^\d+$').hasMatch(tvmaze) || RegExp(r'^tt\d+$', caseSensitive: false).hasMatch(imdb)) {
    jobs.add(() async {
      final uri = tvmaze.isNotEmpty && RegExp(r'^\d+$').hasMatch(tvmaze)
          ? Uri.https('api.tvmaze.com', '/shows/$tvmaze')
          : Uri.https('api.tvmaze.com', '/lookup/shows', {'imdb': imdb});
      final show = await _getJson(uri);
      if (show is! Map) return <MetadataResult>[];
      final direct = tvmaze.isNotEmpty ? '${show['id']}' == tvmaze : (show['externals'] as Map?)?['imdb'] == imdb;
      return [_tvmazeRow(show, idMatch: direct)];
    }());
  }
  final isbn = id('isbn').replaceAll(RegExp(r'[^0-9Xx]'), '');
  if (RegExp(r'^(?:\d{13}|\d{9}[\dXx])$').hasMatch(isbn)) {
    jobs.add(Future.value([
      MetadataResult(
        title: '',
        source: 'Open Library',
        coverUrl: 'https://covers.openlibrary.org/b/isbn/$isbn-L.jpg?default=false',
        externalId: isbn,
        externalIdKey: 'isbn',
        idMatch: true,
      ),
    ]));
  }
  final results = await Future.wait(jobs.map((j) => j.catchError((_) => <MetadataResult>[])));
  return [for (final r in results) ...r];
}

/// The public providers the app calls directly, with the website's read-only
/// test request (`MF438_PUBLIC_PROBES`; Tenrai uses the same check as Jikan).
final List<({String id, String name, String media, Uri url, Map<String, dynamic>? post, bool Function(Object?) valid})>
    kPublicProviders = [
  (id: 'tenrai', name: 'Tenrai (MyAnimeList)', media: 'Anime, manga', url: Uri.parse('https://api.tenrai.org/v1/anime/1'), post: null,
      valid: (d) => (d as Map?)?['data'] is Map && ((d as Map)['data'] as Map)['mal_id'] != null),
  (id: 'jikan', name: 'Jikan (MyAnimeList)', media: 'Anime, manga', url: Uri.parse('https://api.jikan.moe/v4/anime/1'), post: null,
      valid: (d) => (d as Map?)?['data'] is Map && ((d as Map)['data'] as Map)['mal_id'] != null),
  (id: 'anilist', name: 'AniList', media: 'Anime, manga', url: Uri.parse('https://graphql.anilist.co'),
      post: {'query': 'query{Media(id:1,type:ANIME){id}}'},
      valid: (d) => ((((d as Map?)?['data'] as Map?)?['Media'] as Map?)?['id']) == 1),
  (id: 'kitsu', name: 'Kitsu', media: 'Anime, manga', url: Uri.parse('https://kitsu.io/api/edge/anime?page%5Blimit%5D=1'), post: null,
      valid: (d) => (d as Map?)?['data'] is List),
  (id: 'mangadex', name: 'MangaDex', media: 'Manga', url: Uri.parse('https://api.mangadex.org/manga?limit=1'), post: null,
      valid: (d) => (d as Map?)?['data'] is List),
  (id: 'tvmaze', name: 'TVmaze', media: 'TV', url: Uri.parse('https://api.tvmaze.com/shows/1'), post: null,
      valid: (d) => (d as Map?)?['id'] == 1),
  (id: 'openlibrary', name: 'Open Library', media: 'Books, comics', url: Uri.parse('https://openlibrary.org/works/OL45883W.json'), post: null,
      valid: (d) => '${(d as Map?)?['key'] ?? ''}'.startsWith('/works/')),
  (id: 'itunes', name: 'Apple iTunes Search', media: 'Music, movies', url: Uri.parse('https://itunes.apple.com/search?term=queen&entity=album&limit=1'),
      post: null, valid: (d) => (d as Map?)?['results'] is List),
];

/// Runs a public provider's test request. Null: passed; otherwise the problem.
Future<String?> testPublicProvider(String id) async {
  final p = kPublicProviders.where((p) => p.id == id).firstOrNull;
  if (p == null) return 'Unknown provider';
  final data = await _getJson(p.url, post: p.post);
  if (data == null) return 'No response (offline, or the service is down)';
  return p.valid(data) ? null : 'Unexpected response';
}
