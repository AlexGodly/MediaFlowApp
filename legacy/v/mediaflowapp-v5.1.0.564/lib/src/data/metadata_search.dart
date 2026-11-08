// Online title search for covers and totals, using the same sources as the
// website: TMDB (movies, TV, anime — through MediaFlow's provider gateway, so
// the TMDB key stays on the server), AniList (anime, manga), TVMaze (TV),
// Open Library (books) and iTunes (movies, music). Results only fill the
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

/// TMDB posters through the gateway (website v434 `mf434Find` + v559). A
/// manual search asks for close matches too (`loose`), like the website's ID
/// finder; saved TMDB IDs are looked up first.
Future<List<MetadataResult>> searchTmdb(String q, {String kind = '', Map<String, dynamic>? externalIds}) async {
  final call = providerGateway;
  final title = q.length > 110 ? q.substring(0, 110).trim() : q;
  if (call == null || title.length < 2) return const [];
  final ids = <String, String>{};
  externalIds?.forEach((k, v) {
    final value = '${v ?? ''}'.trim();
    if (RegExp(r'^[a-z][a-z0-9_]{0,32}$').hasMatch(k) && RegExp(r'^[\w.:-]{1,120}$').hasMatch(value)) ids[k] = value;
  });
  final body = <String, dynamic>{
    'action': 'search',
    'provider': 'tmdb',
    'title': title,
    'externalIds': ids,
    'loose': true,
    if (kind.isNotEmpty) 'kind': kind,
  };
  Object? data;
  try {
    data = await call(body);
  } catch (e) {
    // The gateway allows one TMDB request a second per account: wait and retry once.
    if (!RegExp(r'Please wait \d+ seconds?', caseSensitive: false).hasMatch('$e')) return const [];
    final seconds = int.tryParse(RegExp(r'\d+').firstMatch('$e')?[0] ?? '') ?? 1;
    await Future<void>.delayed(Duration(milliseconds: (seconds * 1000 + 250).clamp(0, 5000)));
    try {
      data = await call(body);
    } catch (_) {
      return const [];
    }
  }
  final rows = (data is Map ? data['results'] : null);
  if (rows is! List) return const [];
  final out = <MetadataResult>[];
  for (final raw in rows) {
    if (raw is! Map || raw['provider'] != 'tmdb') continue;
    final url = '${raw['url'] ?? ''}';
    final year = raw['year'] is num && (raw['year'] as num) > 0 ? (raw['year'] as num).toInt() : null;
    final tv = raw['externalIdKey'] == 'tmdb_tv';
    out.add(MetadataResult(
      title: '${raw['title'] ?? ''}',
      source: 'TMDB',
      coverUrl: url.startsWith('https://') ? url : '',
      year: year,
      subtitle: [tv ? 'TV' : 'Movie', if (raw['exact'] != true) 'similar title'].join(' · '),
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

/// Searches the sources that fit a category ([unit] and media [type]). TMDB is
/// used for movies, TV and anime ([tmdbKind] picks movie or TV first).
Future<List<MetadataResult>> searchMetadata(String query,
    {required String unit, String type = '', String kind = '', Map<String, dynamic>? externalIds}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final tmdb = searchTmdb(q, kind: kind, externalIds: externalIds);
  final List<Future<List<MetadataResult>>> jobs;
  switch (unit) {
    case 'chapters':
      jobs = [_anilist(q, 'MANGA')];
    case 'pages':
    case 'volumes':
      jobs = [_openLibrary(q), _anilist(q, 'MANGA')];
    case 'issues':
      jobs = [_openLibrary(q)];
    case 'movies':
      jobs = [tmdb, _itunes(q, 'movie'), _anilist(q, 'ANIME')];
    case 'tracks':
    case 'albums':
      jobs = [_itunes(q, 'album')];
    default:
      jobs = type == 'reading' ? [_openLibrary(q)] : [tmdb, _anilist(q, 'ANIME'), _tvmaze(q)];
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
  final kitsu = id('kitsu');
  if (RegExp(r'^\d+$').hasMatch(kitsu)) {
    jobs.add(() async {
      final data = await _getJson(Uri.https('kitsu.io', '/api/edge/${manga ? 'manga' : 'anime'}/$kitsu'));
      final x = (data as Map?)?['data'];
      if (x is! Map || '${x['id']}' != kitsu) return <MetadataResult>[];
      final a = (x['attributes'] as Map?) ?? const {};
      final poster = (a['posterImage'] as Map?) ?? const {};
      return [
        MetadataResult(
          title: '${a['canonicalTitle'] ?? ''}',
          altTitles: [for (final t in ((a['titles'] as Map?) ?? const {}).values) if (t is String && t.isNotEmpty) t],
          coverUrl: '${poster['original'] ?? poster['large'] ?? poster['medium'] ?? ''}',
          year: int.tryParse('${a['startDate'] ?? ''}'.split('-').first),
          source: 'Kitsu',
          externalId: kitsu,
          externalIdKey: 'kitsu',
          idMatch: true,
        ),
      ];
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
