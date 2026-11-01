// Online title search for covers and totals, using the same public sources as
// the website: AniList (anime, manga), TVMaze (TV), Open Library (books) and
// iTunes (movies, music). Results only fill the editor; nothing is saved until
// you save the title.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class MetadataResult {
  MetadataResult({required this.title, required this.source, this.coverUrl = '', this.total, this.year, this.subtitle = '', this.externalId});
  final String title, source, coverUrl, subtitle;
  final int? total, year;
  final String? externalId;
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
  const query = r'query($s:String,$t:MediaType){Page(perPage:12){media(search:$s,type:$t){id title{romaji english} coverImage{extraLarge large} episodes chapters volumes seasonYear startDate{year} format}}}';
  final data = await _getJson(Uri.parse('https://graphql.anilist.co'), post: {'query': query, 'variables': {'s': q, 't': type}});
  final media = (((data as Map?)?['data'] as Map?)?['Page'] as Map?)?['media'] as List? ?? const [];
  return [
    for (final m in media.whereType<Map>())
      MetadataResult(
        title: ((m['title'] as Map?)?['english'] ?? (m['title'] as Map?)?['romaji'] ?? '').toString(),
        subtitle: [m['format'], (m['title'] as Map?)?['romaji']].whereType<Object>().map((e) => '$e').where((e) => e.isNotEmpty).join(' · '),
        coverUrl: ((m['coverImage'] as Map?)?['extraLarge'] ?? (m['coverImage'] as Map?)?['large'] ?? '').toString(),
        total: (type == 'ANIME' ? m['episodes'] : m['chapters']) as int?,
        year: (m['seasonYear'] ?? (m['startDate'] as Map?)?['year']) as int?,
        source: 'AniList',
        externalId: '${m['id']}',
      ),
  ];
}

Future<List<MetadataResult>> _tvmaze(String q) async {
  final data = await _getJson(Uri.https('api.tvmaze.com', '/search/shows', {'q': q}));
  return [
    for (final r in (data as List? ?? const []).whereType<Map>())
      if (r['show'] is Map)
        MetadataResult(
          title: '${(r['show'] as Map)['name'] ?? ''}',
          subtitle: [(r['show'] as Map)['network'] is Map ? ((r['show'] as Map)['network'] as Map)['name'] : null, (r['show'] as Map)['type']]
              .whereType<Object>()
              .join(' · '),
          coverUrl: '${((r['show'] as Map)['image'] as Map?)?['original'] ?? ((r['show'] as Map)['image'] as Map?)?['medium'] ?? ''}',
          year: int.tryParse('${(r['show'] as Map)['premiered'] ?? ''}'.split('-').first),
          source: 'TVMaze',
          externalId: '${(r['show'] as Map)['id']}',
        ),
  ];
}

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

/// Searches the sources that fit a category ([unit] and media [type]).
Future<List<MetadataResult>> searchMetadata(String query, {required String unit, String type = ''}) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
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
      jobs = [_itunes(q, 'movie'), _anilist(q, 'ANIME')];
    case 'tracks':
    case 'albums':
      jobs = [_itunes(q, 'album')];
    default:
      jobs = type == 'reading' ? [_openLibrary(q)] : [_anilist(q, 'ANIME'), _tvmaze(q)];
  }
  final results = await Future.wait(jobs.map((j) => j.catchError((_) => <MetadataResult>[])));
  return [for (final r in results) ...r.where((x) => x.title.isNotEmpty)];
}
