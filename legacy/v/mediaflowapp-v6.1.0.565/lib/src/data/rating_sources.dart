// The rating sources the website's ratings engine and External ID finder ask
// (website v439 `mf439LookupPublic` / `mf439LookupGateway`, v555 Wikidata and
// ID search). Public sources are called directly from fixed endpoints; the
// others go through MediaFlow's provider gateway (the keys stay on the server).
// Every source keeps its own request spacing, like the website.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logic/ratings_engine.dart';
import '../util/js.dart';
import '../logic/title_names.dart' show scriptLang;
import 'metadata_search.dart' show providerGateway;

/// `x||null` for counts.
int? _countOrNull(Object? v) => v is num && v != 0 ? v.toInt() : null;

String _slice10(Object? v) {
  final s = jsStr(v);
  return s.length > 10 ? s.substring(0, 10) : s;
}

class _Cached {
  _Cached(this.data, this.until);
  final Object? data;
  final DateTime until;
}

class RatingSources {
  RatingSources._();
  static final RatingSources instance = RatingSources._();

  static const _publicGap = {
    'jikan': 1700, 'anilist': 1500, 'kitsu': 1700, 'tvmaze': 1100, 'openlibrary': 1600,
    'gutendex': 1800, 'itunes': 1200, 'steam': 1400, 'vndb': 1800, 'musicbrainz': 1500,
  };
  static const _hosts = {
    'jikan': 'api.jikan.moe', 'anilist': 'graphql.anilist.co', 'kitsu': 'kitsu.io', 'tvmaze': 'api.tvmaze.com',
    'openlibrary': 'openlibrary.org', 'gutendex': 'gutendex.com', 'itunes': 'itunes.apple.com',
    'steam': 'store.steampowered.com', 'vndb': 'api.vndb.org', 'musicbrainz': 'musicbrainz.org',
  };

  final Map<String, DateTime> _last = {};
  final Map<String, DateTime> _cooling = {};
  final Map<String, _Cached> _cache = {};
  final Map<String, WikiLinks?> _wikiCache = {};
  DateTime _wikiLast = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------- gateway status ----------

  Set<String>? _ready;
  DateTime _readyAt = DateTime.fromMillisecondsSinceEpoch(0);
  String statusError = '';

  /// Gateway sources set up on the server (`status`), refreshed every 10 minutes.
  Future<Set<String>> gatewayReady({bool force = false}) async {
    if (!force && _ready != null && DateTime.now().difference(_readyAt) < const Duration(minutes: 10)) return _ready!;
    final call = providerGateway;
    if (call == null) return _ready ?? <String>{};
    try {
      final reply = asMap(await call({'action': 'status'}));
      _ready = {
        for (final p in asList(reply?['providers']).map(asMap))
          if (p != null && p['configured'] == true && p['testable'] == true) jsStr(p['id']),
      };
      _readyAt = DateTime.now();
      statusError = '';
    } catch (e) {
      statusError = gatewayMessage(e);
    }
    return _ready ?? <String>{};
  }

  /// `mf555IdReason`: a readable reason for a source error.
  static String reason(Object raw) {
    final m = gatewayMessage(raw);
    if (RegExp(r'credential missing|not configured', caseSensitive: false).hasMatch(m)) {
      return 'Not set up: the API key for this site is missing in Supabase.';
    }
    if (RegExp(r'quota|limit reached', caseSensitive: false).hasMatch(m)) return 'Daily limit reached for this site. Try again tomorrow.';
    final wait = RegExp(r'wait\s+(\d+)', caseSensitive: false).firstMatch(m);
    if (wait != null) return 'Busy: wait ${wait[1]} seconds and try again.';
    if (RegExp(r'OMDb API key rejected', caseSensitive: false).hasMatch(m)) {
      return 'IMDb (OMDb) rejected the API key. Check the OMDB_API_KEY secret.';
    }
    if (RegExp(r'review pending', caseSensitive: false).hasMatch(m)) return 'This site is not available yet.';
    if (RegExp(r'sign in|session', caseSensitive: false).hasMatch(m)) return 'Sign in again to search this site.';
    if (RegExp(r'abort|timeout|network|fetch|socket|connection', caseSensitive: false).hasMatch(m)) {
      return 'Could not reach the site. Check your connection and try again.';
    }
    return m.isEmpty ? 'The site returned an error.' : (m.length > 140 ? m.substring(0, 140) : m);
  }

  /// The gateway's own error text from an exception (FunctionException details).
  static String gatewayMessage(Object e) {
    try {
      final details = (e as dynamic).details;
      final err = asMap(details)?['error'];
      if (err != null) return jsStr(err);
      if (details is String && details.isNotEmpty) return details;
    } catch (_) {}
    return '$e'.replaceFirst('Exception: ', '');
  }

  // ---------- spacing ----------

  Future<void> _space(String key, int gapMs, StopToken? stop) async {
    final last = _last[key];
    if (last != null) {
      final wait = gapMs - DateTime.now().difference(last).inMilliseconds;
      if (wait > 0) await _sleep(wait, stop);
    }
    _last[key] = DateTime.now();
  }

  static Future<void> _sleep(int ms, StopToken? stop) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      stop?.check();
      final left = end.difference(DateTime.now());
      await Future<void>.delayed(left < const Duration(milliseconds: 250) ? left : const Duration(milliseconds: 250));
    }
    stop?.check();
  }

  // ---------- public sources ----------

  Future<Object?> _fetch(String provider, Uri url, {Map<String, dynamic>? body, StopToken? stop}) async {
    if (url.scheme != 'https' || url.host != _hosts[provider]) throw Exception('Unapproved metadata endpoint');
    final cooling = _cooling[provider];
    if (cooling != null && cooling.isAfter(DateTime.now())) throw Exception('Provider cooling down temporarily');
    final key = '$provider:$url:${jsonEncode(body ?? const {})}';
    final hit = _cache[key];
    if (hit != null && hit.until.isAfter(DateTime.now())) return hit.data;
    await _space('public:$provider', _publicGap[provider] ?? 1500, stop);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = body == null ? await client.getUrl(url) : await client.postUrl(url);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'MediaFlowApp');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(milliseconds: 14500));
      if (res.statusCode == 429 || res.statusCode == 503) {
        final retry = int.tryParse(res.headers.value('retry-after') ?? '') ?? 60;
        _cooling[provider] = DateTime.now().add(Duration(seconds: retry.clamp(30, 300)));
        throw Exception('$provider is rate-limited; temporarily paused');
      }
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('$provider HTTP ${res.statusCode}');
      final text = await res.transform(utf8.decoder).join().timeout(const Duration(milliseconds: 14500));
      if (text.length > 1800000) throw Exception('Metadata response too large');
      final data = jsonDecode(text);
      if (_cache.length > 220) _cache.remove(_cache.keys.first);
      _cache[key] = _Cached(data, DateTime.now().add(const Duration(minutes: 15)));
      return data;
    } finally {
      client.close(force: true);
    }
  }

  static Uri _url(String base, Map<String, Object?> params) {
    final u = Uri.parse(base);
    final q = <String, String>{
      for (final e in params.entries)
        if (e.value != null && '${e.value}' != '') e.key: '${e.value}',
    };
    return q.isEmpty ? u : u.replace(queryParameters: q);
  }

  /// `mf439LookupPublic`.
  Future<List<Map<String, dynamic>>> lookupPublic(String provider, Map<String, dynamic> item, {StopToken? stop}) async {
    final variants = titleVariants(item);
    final title = variants.isEmpty ? '' : variants.first;
    final ids = asMap(item['externalIds']) ?? const {};
    final rows = <Map<String, dynamic>>[];
    if (title.length < 2) return rows;
    void pull(Map<String, dynamic> e) {
      if (jsStr(e['title']).isNotEmpty && jsStr(e['recordId']).isNotEmpty) rows.add(e);
    }

    List<dynamic> listOf(Object? d) => d is List ? d : (d == null ? const [] : [d]);

    switch (provider) {
      case 'jikan':
        final mal = RegExp(r'^\d{1,12}$').firstMatch(jsStr(ids['mal']))?[0];
        for (final kind in ['anime', 'manga']) {
          if (stop?.stopped == true) break;
          final url = mal != null
              ? Uri.parse('https://api.jikan.moe/v4/$kind/$mal')
              : _url('https://api.jikan.moe/v4/$kind', {'q': title, 'limit': 5, 'sfw': true});
          Object? d;
          try {
            d = await _fetch(provider, url, stop: stop);
          } catch (e) {
            if (mal != null) continue;
            rethrow;
          }
          for (final v in listOf(asMap(d)?['data']).take(5).map(asMap)) {
            if (v == null || !jsTruthy(v['mal_id'])) continue;
            final aired = asMap(v['aired'])?['from'] ?? asMap(v['published'])?['from'];
            final y = yearOf(aired);
            pull(sourceEntry(provider, v['mal_id'], v['title'], {
              'year': y,
              'aliases': stringList([v['title_english'], v['title_japanese'], ...asList(v['title_synonyms'])]),
              // v565: names in other languages (website mf439LookupPublic).
              'names': _names([('ja-Latn', v['title']), ('en', v['title_english']), ('ja', v['title_japanese'])]),
              'externalIds': {'mal': jsStr(v['mal_id'])},
              'legacy': {
                'synopsis': plainText(v['synopsis']),
                'genres': stringList(asList(v['genres']).map((z) => asMap(z)?['name']).toList()),
                'studios': stringList(asList(v['studios']).map((z) => asMap(z)?['name']).toList()),
                'year': y,
                'mediaFormat': jsStr(v['type']),
              },
              'fields': {
                'originalTitle': jsStr(v['title_japanese']),
                'animeSeason': jsTruthy(v['season']) ? jsStr(v['season']) : '',
                'episodeCount': _countOrNull(v['episodes']),
                'chapterCount': _countOrNull(v['chapters']),
                'volumeCount': _countOrNull(v['volumes']),
                'mangaAuthors': stringList(asList(v['authors']).map((z) => asMap(z)?['name']).toList()),
              },
              'ratings': {'mal': scoreOf(v['score'], 10, v['scored_by'])},
            }));
          }
        }
      case 'anilist':
        const gql = r'query($s:String,$id:Int,$idMal:Int){Page(perPage:7){media(search:$s,id:$id,idMal:$idMal){id idMal title{romaji english native} synonyms description(asHtml:false) genres averageScore meanScore popularity episodes chapters volumes startDate{year month day} season seasonYear studios(isMain:true){nodes{name}} staff(perPage:12){nodes{name{full}}} format}}}';
        final anilistId = int.tryParse(jsStr(ids['anilist']));
        final malId = anilistId == null ? int.tryParse(jsStr(ids['mal'])) : null;
        final d = await _fetch(provider, Uri.parse('https://graphql.anilist.co'), stop: stop, body: {
          'query': gql,
          'variables': {'s': title, if (anilistId != null) 'id': anilistId, if (malId != null) 'idMal': malId},
        });
        for (final v in asList(asMap(asMap(asMap(d)?['data'])?['Page'])?['media']).take(7).map(asMap)) {
          if (v == null || !jsTruthy(v['id'])) continue;
          final t = asMap(v['title']) ?? const {};
          final y = jsNum(asMap(v['startDate'])?['year']).toInt();
          pull(sourceEntry(provider, v['id'], _first([t['romaji'], t['english'], t['native']]), {
            'year': y,
            'aliases': stringList([t['english'], t['native'], ...asList(v['synonyms'])]),
            'names': _names([('ja-Latn', t['romaji']), ('en', t['english']), (scriptLang(t['native']).isEmpty ? 'ja' : scriptLang(t['native']), t['native'])]),
            'externalIds': {'anilist': jsStr(v['id']), if (jsTruthy(v['idMal'])) 'mal': jsStr(v['idMal'])},
            'legacy': {
              'synopsis': plainText(v['description']),
              'genres': stringList(v['genres']),
              'studios': stringList(asList(asMap(v['studios'])?['nodes']).map((z) => asMap(z)?['name']).toList()),
              'year': y,
              'mediaFormat': jsStr(v['format']),
            },
            'fields': {
              'originalTitle': jsStr(t['native']),
              'alternateTitles': stringList(v['synonyms']),
              'animeSeason': jsTruthy(v['season']) ? '${jsStr(v['season'])} ${jsTruthy(v['seasonYear']) ? jsStr(v['seasonYear']) : ''}' : '',
              'episodeCount': _countOrNull(v['episodes']),
              'chapterCount': _countOrNull(v['chapters']),
              'volumeCount': _countOrNull(v['volumes']),
              'creators': stringList(asList(asMap(v['staff'])?['nodes']).map((z) => asMap(asMap(z)?['name'])?['full']).toList()),
            },
            'ratings': {'anilist': scoreOf(v['averageScore'], 100)},
          }));
        }
      case 'kitsu':
        final known = jsStr(ids['kitsu']).trim();
        final kind = jsStr(asMap(item['universalMetadata'])?['mediaType']).toLowerCase() == 'manga' ? 'manga' : 'anime';
        final url = known.isNotEmpty
            ? Uri.parse('https://kitsu.io/api/edge/$kind/${Uri.encodeComponent(known)}')
            : _url('https://kitsu.io/api/edge/$kind', {'filter[text]': title, 'page[limit]': 6});
        final d = await _fetch(provider, url, stop: stop);
        for (final v in listOf(asMap(d)?['data']).take(6).map(asMap)) {
          if (v == null) continue;
          final a = asMap(v['attributes']) ?? const {};
          final titles = asMap(a['titles']) ?? const {};
          final y = yearOf(a['startDate']);
          pull(sourceEntry(provider, v['id'], _first([a['canonicalTitle'], titles['en'], titles['en_jp']]), {
            'year': y,
            'aliases': stringList(titles.values.toList()),
            'names': _names([for (final e in titles.entries) (_kitsuLang[e.key] ?? '', e.value)]),
            'externalIds': {'kitsu': jsStr(v['id'])},
            'legacy': {'synopsis': plainText(a['synopsis']), 'year': y, 'mediaFormat': jsStr(a['subtype'])},
            'fields': {
              'originalTitle': jsStr(titles['ja_jp']),
              'episodeCount': _countOrNull(a['episodeCount']),
              'chapterCount': _countOrNull(a['chapterCount']),
              'volumeCount': _countOrNull(a['volumeCount']),
            },
            'ratings': {'kitsu': scoreOf(a['averageRating'], 100, a['userCount'])},
          }));
        }
      case 'tvmaze':
        final stored = RegExp(r'^\d+$').firstMatch(jsStr(ids['tvmaze']))?[0];
        final url = stored != null ? Uri.parse('https://api.tvmaze.com/shows/$stored') : _url('https://api.tvmaze.com/search/shows', {'q': title});
        final d = await _fetch(provider, url, stop: stop);
        for (final wrap in listOf(d).take(8).map(asMap)) {
          final v = asMap(wrap?['show']) ?? wrap;
          if (v == null || !jsTruthy(v['id'])) continue;
          final imdb = asMap(v['externals'])?['imdb'];
          final y = yearOf(v['premiered']);
          pull(sourceEntry(provider, v['id'], v['name'], {
            'year': y,
            'externalIds': {'tvmaze': jsStr(v['id']), if (jsTruthy(imdb)) 'imdb': jsStr(imdb)},
            'legacy': {
              'synopsis': plainText(v['summary']),
              'genres': stringList(v['genres']),
              'year': y,
              'releaseDate': jsStr(v['premiered']),
              'mediaFormat': jsStr(v['type']),
              'ageRating': '',
            },
            'fields': {
              'networks': stringList([asMap(v['network'])?['name'], asMap(v['webChannel'])?['name']]),
              'releaseStatus': jsStr(v['status']),
              'originalLanguage': jsStr(v['language']),
            },
            'ratings': {'tvmaze': scoreOf(asMap(v['rating'])?['average'], 10)},
          }));
        }
      case 'openlibrary':
        final known = jsStr(_orV(ids['openlibrary_work'], ids['openlibrary']));
        final match = RegExp(r'OL\d+W', caseSensitive: false).firstMatch(known)?[0];
        final url = match != null
            ? Uri.parse('https://openlibrary.org/works/${match.toUpperCase()}.json')
            : _url('https://openlibrary.org/search.json', {'title': title, 'limit': 6, 'fields': 'key,title,first_publish_year,author_name,language,subject'});
        final d = asMap(await _fetch(provider, url, stop: stop));
        final list = d?['docs'] is List ? d!['docs'] as List : [d];
        for (final v in list.take(6).map(asMap)) {
          final work = RegExp(r'OL\d+W', caseSensitive: false).firstMatch(jsStr(v?['key'] ?? match))?[0];
          if (v == null || work == null) continue;
          final y = jsNum(v['first_publish_year']).toInt();
          Object? desc = v['description'] is Map ? (v['description'] as Map)['value'] : v['description'];
          // Search results have no synopsis: fetch it for the first two
          // exact-title works only (as the website does).
          if (!jsTruthy(desc) && rows.length < 2 && normTitle(v['title']) == normTitle(title)) {
            try {
              final detail = asMap(await _fetch(provider, Uri.parse('https://openlibrary.org/works/$work.json'), stop: stop));
              desc = detail?['description'] is Map ? (detail!['description'] as Map)['value'] : detail?['description'];
            } catch (_) {}
          }
          pull(sourceEntry(provider, work, v['title'], {
            'year': y,
            'externalIds': {'openlibrary_work': work},
            'legacy': {'synopsis': plainText(desc), 'year': y, 'genres': stringList(v['subject'])},
            'fields': {
              'authors': stringList(v['author_name']),
              'originalLanguage': asList(v['language']).isEmpty ? '' : jsStr(asList(v['language']).first),
              'keywords': stringList(v['subject']),
            },
          }));
        }
      case 'gutendex':
        final d = await _fetch(provider, _url('https://gutendex.com/books', {'search': title}), stop: stop);
        for (final v in asList(asMap(d)?['results']).take(6).map(asMap)) {
          if (v == null || !jsTruthy(v['id'])) continue;
          pull(sourceEntry(provider, v['id'], v['title'], {
            'externalIds': {'gutendex': jsStr(v['id'])},
            'legacy': {'genres': stringList(v['subjects'])},
            'fields': {
              'authors': stringList(asList(v['authors']).map((a) => asMap(a)?['name']).toList()),
              'originalLanguage': asList(v['languages']).isEmpty ? '' : jsStr(asList(v['languages']).first),
            },
          }));
        }
      case 'itunes':
        final d = await _fetch(provider, _url('https://itunes.apple.com/search', {'term': title, 'entity': 'album', 'limit': 9}), stop: stop);
        for (final v in asList(asMap(d)?['results']).take(9).map(asMap)) {
          if (v == null || !jsTruthy(v['collectionId'])) continue;
          final y = yearOf(v['releaseDate']);
          pull(sourceEntry(provider, v['collectionId'], v['collectionName'], {
            'year': y,
            'externalIds': {'apple_music_album': jsStr(v['collectionId'])},
            'fields': {
              'albumArtists': stringList([v['artistName']]),
              'trackCount': _countOrNull(v['trackCount']),
              'recordLabels': stringList([v['copyright']]),
              'releaseType': 'Album',
            },
            'legacy': {'year': y, 'releaseDate': _slice10(v['releaseDate']), 'genres': stringList([v['primaryGenreName']])},
          }));
        }
      case 'steam':
        final d = await _fetch(provider, _url('https://store.steampowered.com/api/storesearch/', {'term': title, 'l': 'english', 'cc': 'us'}), stop: stop);
        for (final v in asList(asMap(d)?['items']).take(8).map(asMap)) {
          if (v == null || !jsTruthy(v['id'])) continue;
          pull(sourceEntry(provider, v['id'], v['name'], {'externalIds': {'steam_app': jsStr(v['id'])}}));
        }
      case 'vndb':
        final valid = RegExp(r'^v\d+$', caseSensitive: false).firstMatch(jsStr(ids['vndb']))?[0];
        final d = await _fetch(provider, Uri.parse('https://api.vndb.org/kana/vn'), stop: stop, body: {
          'filters': valid != null ? ['id', '=', valid] : ['search', '=', title],
          'fields': 'title,alttitle,description,released,rating,votecount,platforms,length_minutes',
          'results': 7,
        });
        for (final v in asList(asMap(d)?['results']).take(7).map(asMap)) {
          if (v == null || !RegExp(r'^v\d+$').hasMatch(jsStr(v['id']))) continue;
          final y = yearOf(v['released']);
          pull(sourceEntry(provider, v['id'], v['title'], {
            'year': y,
            'aliases': stringList([v['alttitle']]),
            'externalIds': {'vndb': jsStr(v['id'])},
            'legacy': {'synopsis': plainText(v['description']), 'year': y, 'releaseDate': jsStr(v['released'])},
            'fields': {
              'originalTitle': jsStr(v['alttitle']),
              'ifPlatforms': stringList(v['platforms']),
              'platforms': stringList(v['platforms']),
              // Number(null) is 0 on the website; a missing key gives null.
              'mainStoryHours': v['length_minutes'] is num
                  ? ((v['length_minutes'] as num) / 60 * 100).round() / 100
                  : (v.containsKey('length_minutes') && v['length_minutes'] == null ? 0 : null),
            },
            'ratings': {'vndb': scoreOf(v['rating'], 100, v['votecount'])},
          }));
        }
      case 'musicbrainz':
        final d = await _fetch(
          provider,
          _url('https://musicbrainz.org/ws/2/release-group/', {'query': 'releasegroup:"${title.replaceAll('"', '')}"', 'fmt': 'json', 'limit': 7}),
          stop: stop,
        );
        for (final v in asList(asMap(d)?['release-groups']).take(7).map(asMap)) {
          if (v == null || !jsTruthy(v['id'])) continue;
          final y = yearOf(v['first-release-date']);
          pull(sourceEntry(provider, v['id'], v['title'], {
            'year': y,
            'externalIds': {'musicbrainz_release_group': jsStr(v['id'])},
            'fields': {
              'albumArtists': stringList(asList(v['artist-credit']).map((a) => asMap(asMap(a)?['artist'])?['name'] ?? asMap(a)?['name']).toList()),
              'releaseType': jsStr(v['primary-type']),
            },
            'legacy': {'releaseDate': jsStr(v['first-release-date']), 'year': y},
          }));
        }
    }
    // Ratings the source didn't give are left out (`mf439Score` → null).
    for (final r in rows) {
      (r['ratings'] as Map).removeWhere((_, v) => v == null);
    }
    return rows.length > 10 ? rows.sublist(0, 10) : rows;
  }

  static String _first(List<Object?> xs) => jsStr(xs.firstWhere(jsTruthy, orElse: () => ''));
  static Object? _orV(Object? a, Object? b) => jsTruthy(a) ? a : b;

  // ---------- gateway sources ----------

  Future<Object?> _gateway(String provider, Map<String, dynamic> body, StopToken? stop) async {
    final call = providerGateway;
    if (call == null) throw Exception('Sign in to use verified API providers.');
    await _space('gateway:$provider', 1300, stop);
    try {
      return await call(body);
    } catch (e) {
      // Older gateway: one request per source every 10 seconds.
      if (!RegExp(r'wait.*seconds', caseSensitive: false).hasMatch(gatewayMessage(e))) throw Exception(gatewayMessage(e));
      await _sleep(10500, stop);
      _last['gateway:$provider'] = DateTime.now();
      try {
        return await call(body);
      } catch (e2) {
        throw Exception(gatewayMessage(e2));
      }
    }
  }

  static Map<String, String> _cleanIds(Object? ids) {
    final out = <String, String>{};
    (asMap(ids) ?? const {}).forEach((k, v) {
      final s = jsStr(v).trim();
      if (RegExp(r'^[a-z][a-z0-9_]{0,32}$').hasMatch(k) && RegExp(r'^[\w.:-]{1,120}$').hasMatch(s)) out[k] = s;
    });
    return out;
  }

  /// `mf439LookupGateway` + `mf439TranslateGateway`.
  Future<List<Map<String, dynamic>>> lookupGateway(String provider, Map<String, dynamic> item, {StopToken? stop}) async {
    if (!kGatewaySources.contains(provider)) return const [];
    if (!(await gatewayReady()).contains(provider)) return const [];
    final variants = titleVariants(item);
    final reply = asMap(await _gateway(provider, {
      'action': 'metadata',
      'provider': provider,
      'title': variants.isEmpty ? '' : variants.first,
      'externalIds': _cleanIds(item['externalIds']),
      'year': item['year'] ?? '',
    }, stop));
    final out = <Map<String, dynamic>>[];
    for (final record in asList(reply?['results']).take(8).map(asMap)) {
      final row = _translate(provider, record);
      if (row != null) out.add(row);
    }
    return out;
  }

  static const _gatewayKeys = {
    'tmdb': ['tmdb', 'tmdb_tv'], 'omdb': ['imdb'], 'malofficial': ['mal'], 'trakt': ['trakt'], 'simkl': ['simkl'],
    'watchmode': ['watchmode'], 'animeschedule': ['animeschedule'], 'metron': ['metron_series'],
    'episodate': ['episodate'], 'gutendex': ['gutendex'],
  };

  static Map<String, dynamic>? _translate(String provider, Map<String, dynamic>? record) {
    if (record == null || record['provider'] != provider || record['verified'] != true || !jsTruthy(record['title'])) return null;
    final ids = asMap(record['ids']) ?? const <String, dynamic>{};
    final primary = (_gatewayKeys[provider] ?? const []).map((k) => ids[k]).firstWhere(jsTruthy, orElse: () => null);
    if (primary == null) return null;
    final raw = asMap(record['fields']) ?? const <String, dynamic>{};
    final legacy = <String, dynamic>{
      for (final k in ['synopsis', 'releaseDate', 'year', 'genres', 'mediaFormat'])
        if (raw.containsKey(k)) k: raw[k],
    };
    final ratings = <String, dynamic>{};
    (asMap(record['ratings']) ?? const {}).forEach((key, score) {
      final s = asMap(score);
      final source = key == 'rottenTomatoes' ? 'rottentomatoes_critics' : key;
      final scale = jsNumOrNull(s?['scale']);
      final value = jsNumOrNull(s?['value']);
      if (s?['value'] != null && scale != null && value != null) {
        ratings[source] = {'score': jsOut(value), 'scale': jsOut(scale), 'votes': s!['votes']};
      }
    });
    return sourceEntry(provider, primary, record['title'], {
      'year': yearOf(_orV(raw['year'], raw['releaseDate'])),
      'aliases': stringList(raw['alternateTitles']),
      'externalIds': {...ids},
      'legacy': legacy,
      'ratings': ratings,
    });
  }

  /// `mf555rLookup`: one source, by name or saved ID.
  Future<List<Map<String, dynamic>>> lookup(String provider, Map<String, dynamic> query, {StopToken? stop}) {
    stop?.check();
    if (kGatewaySources.contains(provider)) return lookupGateway(provider, query, stop: stop);
    return lookupPublic(provider, query, stop: stop);
  }

  /// The External ID finder's search on a gateway source (`search`, loose).
  Future<List<Map<String, dynamic>>> searchGateway(String provider, String name, Object? year, {StopToken? stop}) async {
    final reply = asMap(await _gateway(provider, {
      'action': 'search',
      'provider': provider,
      'title': name,
      'externalIds': <String, String>{},
      'year': year ?? '',
      'loose': true,
    }, stop));
    return [for (final r in asList(reply?['results']).map(asMap)) if (r != null) r];
  }

  // ---------- Wikidata ----------

  static const _wd = {'mal': 'P4086', 'anilist': 'P8729', 'imdb': 'P345', 'tmdb': 'P4947', 'tmdb_tv': 'P4983'};
  static final _wdValid = {
    'mal': RegExp(r'^\d{1,9}$'), 'anilist': RegExp(r'^\d{1,9}$'), 'imdb': RegExp(r'^tt\d{7,12}$'),
    'tmdb': RegExp(r'^\d{1,9}$'), 'tmdb_tv': RegExp(r'^\d{1,9}$'),
  };

  Future<Map<String, dynamic>?> _wikiFetch(Map<String, String> params, StopToken? stop) async {
    final wait = 900 - DateTime.now().difference(_wikiLast).inMilliseconds;
    if (wait > 0) await _sleep(wait, stop);
    _wikiLast = DateTime.now();
    final url = Uri.https('www.wikidata.org', '/w/api.php', {...params, 'format': 'json', 'origin': '*'});
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 9);
    try {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'MediaFlowApp');
      final res = await req.close().timeout(const Duration(seconds: 9));
      if (res.statusCode != 200) throw Exception('Wikidata HTTP ${res.statusCode}');
      return asMap(jsonDecode(await res.transform(utf8.decoder).join()));
    } finally {
      client.close(force: true);
    }
  }

  static List<Object?> _claims(Map<String, dynamic>? entity, String prop) => [
        for (final c in asList(asMap(entity?['claims'])?[prop]).map(asMap))
          if (c != null && c['rank'] != 'deprecated' && asMap(asMap(c['mainsnak'])?['datavalue'])?['value'] != null)
            asMap(asMap(c['mainsnak'])?['datavalue'])!['value'],
      ];

  static Map<String, String> _wikiIds(Map<String, dynamic>? entity) {
    final out = <String, String>{};
    _wd.forEach((key, prop) {
      final vals = _claims(entity, prop).map(jsStr).where(_wdValid[key]!.hasMatch).toSet();
      if (vals.length == 1) out[key] = vals.first; // several different values = ambiguous
    });
    return out;
  }

  /// `mf555rWikidata`.
  Future<WikiLinks?> wikidata(Map<String, String> ids, {StopToken? stop}) async {
    for (final key in ['mal', 'anilist', 'imdb', 'tmdb_tv', 'tmdb']) {
      final value = (ids[key] ?? '').trim();
      if (value.isEmpty || !_wdValid[key]!.hasMatch(value)) continue;
      final cacheKey = '$key:$value';
      if (_wikiCache.containsKey(cacheKey)) return _wikiCache[cacheKey];
      WikiLinks? result;
      try {
        final found = await _wikiFetch({'action': 'query', 'list': 'search', 'srsearch': 'haswbstatement:${_wd[key]}=$value', 'srlimit': '3'}, stop);
        final hits = [
          for (final h in asList(asMap(found?['query'])?['search']).map(asMap))
            if (RegExp(r'^Q\d+$').hasMatch(jsStr(h?['title']))) jsStr(h!['title']),
        ];
        if (hits.length == 1) {
          final ent = await _wikiFetch({'action': 'wbgetentities', 'ids': hits[0], 'props': 'claims'}, stop);
          final entity = asMap(asMap(ent?['entities'])?[hits[0]]);
          if (entity != null && _claims(entity, _wd[key]!).map(jsStr).contains(value)) {
            final own = _wikiIds(entity);
            Map<String, String>? parent;
            final parents = _claims(entity, 'P179').map((v) => jsStr(asMap(v)?['id'])).where((v) => RegExp(r'^Q\d+$').hasMatch(v)).toSet();
            if (parents.length == 1 && (!own.containsKey('imdb') || !own.containsKey('tmdb_tv'))) {
              final pe = await _wikiFetch({'action': 'wbgetentities', 'ids': parents.first, 'props': 'claims'}, stop);
              final p = asMap(asMap(pe?['entities'])?[parents.first]);
              if (p != null) parent = _wikiIds(p);
            }
            result = WikiLinks(hits[0], own, parent);
          }
        }
      } on RatingsStopped {
        rethrow;
      } catch (_) {
        result = null;
      }
      _wikiCache[cacheKey] = result;
      if (result != null) return result;
    }
    return null;
  }
}

/// v565: Kitsu's title keys as name languages (website mf439LookupPublic).
const _kitsuLang = {
  'en': 'en', 'en_us': 'en', 'en_jp': 'ja-Latn', 'ja_jp': 'ja', 'zh_cn': 'zh', 'zh_tw': 'zh',
  'ko_kr': 'ko', 'en_kr': 'ko-Latn', 'en_cn': 'zh-Latn',
};

/// Names with a language and text (empty ones left out), as the website's adapters return them.
List<Map<String, dynamic>> _names(List<(String, Object?)> pairs) => [
      for (final (lang, text) in pairs)
        if (lang.isNotEmpty && text is String && text.isNotEmpty) {'lang': lang, 'text': text},
    ];
