// The website's external ratings engine (v555 `mf555RatingsForTitle` and
// `mf555ApplyRatings`, on the v437 universal-metadata model and the v439 / v467
// / v547 provider rules). For one title, in this order:
//  1. Saved IDs first: every rating source that can look a title up by an ID
//     it already has is asked by ID.
//  2. Find missing IDs: Wikidata links MAL / AniList / IMDb / TMDB IDs, then
//     every source still missing is searched with every known name.
//  3. Recheck with the new IDs.
// Seasons without their own IMDb / TMDB entry share the whole show's rating.
// A saved ID is never replaced, conflicting IDs are ignored, name matches must
// be exact with a compatible year and type, and ambiguous matches are skipped.
//
// Pure logic: the network calls are passed in (lib/src/data/rating_sources.dart),
// so the writes can be compared with the website's (test/ratings_golden_test.dart).

import '../util/js.dart';

/// Thrown when a refresh is stopped.
class RatingsStopped implements Exception {
  @override
  String toString() => 'Stopped';
}

/// Lets a running refresh be stopped.
class StopToken {
  bool stopped = false;
  void stop() => stopped = true;
  void check() {
    if (stopped) throw RatingsStopped();
  }
}

// ---------- the website's tables ----------

/// `MF437_RATING_SOURCES`: key, label, default scale.
const kRatingSources = <(String, String, num)>[
  ('imdb', 'IMDb', 10), ('trakt', 'Trakt', 10),
  ('rottentomatoes_critics', 'Rotten Tomatoes · Critics', 100),
  ('rottentomatoes_audience', 'Rotten Tomatoes · Audience', 100),
  ('mal', 'MyAnimeList', 10), ('anilist', 'AniList', 100), ('kitsu', 'Kitsu', 100),
  ('tmdb', 'TMDB', 10), ('simkl', 'SIMKL', 10), ('anidb', 'AniDB', 10),
  ('tvmaze', 'TVmaze', 10), ('metacritic', 'Metacritic', 100),
  ('letterboxd', 'Letterboxd', 5), ('goodreads', 'Goodreads', 5),
  ('storygraph', 'The StoryGraph', 5), ('hardcover', 'Hardcover', 5),
  ('igdb', 'IGDB', 100), ('opencritic', 'OpenCritic', 100),
  ('steam', 'Steam · Positive reviews (%)', 100), ('backloggd', 'Backloggd', 5),
  ('vndb', 'VNDB', 10), ('mangaupdates', 'MangaUpdates', 10),
  ('rateyourmusic', 'Rate Your Music', 5), ('discogs', 'Discogs', 5),
  ('ifdb', 'IFDB', 5),
];
final Map<String, (String, String, num)> kRatingMap = {for (final r in kRatingSources) r.$1: r};

const kMediaTypes = [
  'unspecified', 'anime', 'manga', 'movie', 'tv', 'book', 'comic', 'game', 'visual_novel', 'music', 'interactive_fiction', 'other',
];

/// Public sources (`MF439_PUBLIC`) and gateway sources (`MF439_GATEWAY`).
const kPublicSources = ['jikan', 'anilist', 'kitsu', 'tvmaze', 'openlibrary', 'gutendex', 'itunes', 'steam', 'vndb', 'musicbrainz'];
const kGatewaySources = ['tmdb', 'omdb', 'malofficial', 'trakt', 'simkl', 'watchmode', 'animeschedule', 'metron', 'episodate', 'gutendex'];

/// `mf439Available`.
final List<String> kAvailableSources = {...kPublicSources, ...kGatewaySources}.toList();

/// `MF467_RATING_PROVIDERS`.
const kRatingProviders = {
  'jikan', 'anilist', 'kitsu', 'tvmaze', 'vndb', 'tmdb', 'omdb',
  'malofficial', 'trakt', 'simkl', 'watchmode', 'openlibrary', 'gutendex', 'itunes', 'steam', 'musicbrainz',
};

const _idLookup = <String, List<String>>{
  'jikan': ['mal'], 'malofficial': ['mal'], 'anilist': ['anilist', 'mal'], 'kitsu': ['kitsu'],
  'tvmaze': ['tvmaze'], 'omdb': ['imdb'], 'tmdb': ['tmdb', 'tmdb_tv'], 'watchmode': ['imdb'], 'vndb': ['vndb'],
};
const _primary = <String, List<String>>{
  'imdb': ['omdb', 'watchmode', 'simkl', 'trakt'], 'mal': ['jikan', 'malofficial', 'simkl'],
  'anilist': ['anilist'], 'kitsu': ['kitsu'], 'tmdb': ['tmdb'], 'trakt': ['trakt'], 'simkl': ['simkl'], 'tvmaze': ['tvmaze'],
  'metacritic': ['omdb'], 'rottentomatoes_critics': ['omdb'],
};
const _recordKeys = <String, List<String>>{
  'jikan': ['mal'], 'malofficial': ['mal'], 'anilist': ['anilist'], 'kitsu': ['kitsu'], 'tvmaze': ['tvmaze'],
  'omdb': ['imdb'], 'tmdb': ['tmdb', 'tmdb_tv'], 'trakt': ['trakt'], 'simkl': ['simkl'], 'watchmode': ['watchmode'], 'vndb': ['vndb'],
};
const _byType = <String, List<String>>{
  'video': ['jikan', 'malofficial', 'anilist', 'kitsu', 'tvmaze', 'omdb', 'tmdb', 'trakt', 'simkl', 'watchmode'],
  'reading': ['jikan', 'malofficial', 'anilist', 'kitsu', 'openlibrary', 'gutendex', 'vndb'],
  'playing': ['steam', 'vndb'],
  'listening': ['itunes', 'musicbrainz'],
};

/// `MF547_ID_RATING_MAP`: which ratings and sources each saved ID unlocks.
const kIdRatingMap = <String, (List<String>, List<String>)>{
  'imdb': (['imdb'], ['omdb']),
  'mal': (['mal'], ['jikan', 'malofficial']),
  'anilist': (['anilist'], ['anilist']),
  'kitsu': (['kitsu'], ['kitsu']),
  'tmdb': (['tmdb'], ['tmdb']),
  'tmdb_tv': (['tmdb'], ['tmdb']),
  'trakt': (['trakt'], ['trakt']),
  'simkl': (['simkl'], ['simkl']),
  'tvmaze': (['tvmaze'], ['tvmaze']),
  'vndb': (['vndb'], ['vndb']),
  'watchmode': ([], ['watchmode']),
  'animeschedule': ([], ['animeschedule']),
  'metron_series': ([], ['metron']),
  'episodate': ([], ['episodate']),
  'openlibrary_work': ([], ['openlibrary']),
  'gutendex': ([], ['gutendex']),
  'apple_music_album': ([], ['itunes']),
  'steam_app': ([], ['steam']),
  'musicbrainz_release_group': ([], ['musicbrainz']),
};

/// `V377_ID_PROVIDERS` (with the v437 additions): every ID key a title can
/// save, with its label.
const kIdKeys = <(String, String)>[
  ('mal', 'MyAnimeList'), ('simkl', 'SIMKL'), ('anilist', 'AniList'), ('tmdb', 'TMDB'), ('imdb', 'IMDb'), ('trakt', 'Trakt'),
  ('kitsu', 'Kitsu'), ('isbn', 'ISBN'), ('episodate', 'EpisoDate Show'), ('tvdb_series', 'TheTVDB Series'),
  ('tvdb_season', 'TheTVDB Season'), ('tvdb_episode', 'TheTVDB Episode'), ('tvdb_movie', 'TheTVDB Movie'),
  ('simkl_movie', 'SIMKL Movie'), ('simkl_show', 'SIMKL Show'), ('mangadex', 'MangaDex'),
  ('gcd_series', 'Grand Comics Database Series'), ('gcd_issue', 'Grand Comics Database Issue'),
  ('royalroad', 'Royal Road Fiction'), ('royalroad_rss', 'Royal Road RSS'), ('mangaupdates', 'MangaUpdates Series'),
  ('livechart', 'LiveChart Anime'), ('wikidata', 'Wikidata'), ('anidb', 'AniDB'), ('animeschedule', 'AnimeSchedule'),
  ('watchmode', 'Watchmode'), ('marvel_comic', 'Marvel Comic'), ('marvel_series', 'Marvel Series'),
  ('marvel_issue', 'Marvel Issue'), ('lccn', 'Library of Congress LCCN'), ('oclc', 'OCLC Control Number'),
  ('gnd', 'German National Library GND'), ('dnb', 'German National Library Record'), ('bnf', 'BnF Record'),
  ('doi', 'Crossref DOI'), ('comicvine_volume', 'Comic Vine Volume'), ('comicvine_issue', 'Comic Vine Issue'),
  ('comicvine_character', 'Comic Vine Character'), ('metron_series', 'Metron Series'), ('metron_issue', 'Metron Issue'),
  ('metron_publisher', 'Metron Publisher'), ('hardcover_book', 'Hardcover Book'), ('hardcover_edition', 'Hardcover Edition'),
  ('openlibrary_work', 'Open Library Work'), ('openlibrary_edition', 'Open Library Edition'),
  ('inventaire_work', 'Inventaire Work'), ('inventaire_edition', 'Inventaire Edition'), ('gutendex', 'Gutendex Book'),
  ('isbn10', 'ISBN-10'), ('isbn13', 'ISBN-13'), ('ean', 'EAN'), ('youtube_video', 'YouTube Video'),
  ('youtube_playlist', 'YouTube Playlist'), ('tmdb_tv', 'TMDB TV'), ('loc', 'Library of Congress Record'),
  ('crossref', 'Crossref Record'), ('fribb_mapping', 'Fribb Mapping Reference'),
  ('igdb', 'IGDB'), ('steam_app', 'Steam App'), ('gog', 'GOG'), ('rawg', 'RAWG'), ('mobygames', 'MobyGames'),
  ('giantbomb', 'Giant Bomb'), ('opencritic', 'OpenCritic'), ('howlongtobeat', 'HowLongToBeat'), ('vndb', 'VNDB'),
  ('itch', 'itch.io'), ('vgmdb', 'VGMdb'), ('musicbrainz_release', 'MusicBrainz Release'),
  ('musicbrainz_release_group', 'MusicBrainz Release Group'), ('musicbrainz_recording', 'MusicBrainz Recording'),
  ('musicbrainz_artist', 'MusicBrainz Artist'), ('discogs_release', 'Discogs Release'), ('discogs_master', 'Discogs Master'),
  ('spotify_album', 'Spotify Album'), ('apple_music_album', 'Apple Music Album'), ('ifdb', 'IFDB Interactive Fiction'),
  ('ifwiki', 'IFWiki'), ('opencritic_game', 'OpenCritic Game'),
];

/// ID keys the ratings engine may save (`V377_ID_PROVIDERS` + tmdb_tv, tvmaze, vndb, watchmode).
final Set<String> kSavableIdKeys = {for (final k in kIdKeys) k.$1, 'tmdb_tv', 'tvmaze', 'vndb', 'watchmode'};

// ---------- text helpers (v439) ----------

const _entities = {'&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'"};

String _slice(String s, int max) => s.length > max ? s.substring(0, max) : s;

/// `mf439Plain`.
String plainText(Object? v, [int max = 6000]) {
  var s = v == null ? '' : jsStr(v);
  s = s.replaceAll(RegExp(r'<[^>]*>'), ' ');
  s = s.replaceAllMapped(RegExp(r'&(?:amp|lt|gt|quot|#39);'), (m) => _entities[m[0]] ?? m[0]!);
  s = s.replaceAll('\r', '').trim();
  return _slice(s, max);
}

/// Unicode NFKC for the characters titles actually contain (full-width
/// forms and compatibility spaces) — what `normalize('NFKC')` changes there.
String _nfkcLite(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      out.writeCharCode(r - 0xFEE0);
    } else if (r == 0x3000 || r == 0x00A0 || (r >= 0x2000 && r <= 0x200A) || r == 0x202F || r == 0x205F) {
      out.write(' ');
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString();
}

final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// `mf439Norm`.
String normTitle(Object? t) => _nfkcLite(plainText(t, 260)).toLowerCase().replaceAll(_nonWord, ' ').trim();

/// `mf439Year`.
int yearOf(Object? value) {
  final s = jsTruthy(value) ? jsStr(value is double && value == value.truncateToDouble() ? value.toInt() : value) : '';
  final head = s.length > 4 ? s.substring(0, 4) : s;
  final x = head.trim().isEmpty ? 0 : num.tryParse(head.trim());
  if (x == null || x != x.truncate()) return 0;
  final n = x.toInt();
  return n >= 1850 && n <= 2150 ? n : 0;
}

Object? _or(Object? a, Object? b) => jsTruthy(a) ? a : b;

/// `mf439TitleVariants`.
List<String> titleVariants(Map<String, dynamic> item) {
  final fields = asMap(asMap(item['universalMetadata'])?['fields']);
  final out = <String>[];
  for (final x in [item['title'], item['originalTitle'], item['titleEnglish'], item['titleRomaji'], ...asList(fields?['alternateTitles'])]) {
    final v = plainText(x, 220);
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out;
}

/// `mf439StringList`.
List<String> stringList(Object? xs, [int n = 35]) {
  final out = <String>[];
  for (final x in asList(xs)) {
    final v = plainText(x, 160);
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out.length > n ? out.sublist(0, n) : out;
}

/// `mf439Score`.
Map<String, dynamic>? scoreOf(Object? score, [num scale = 10, Object? votes]) {
  if (score == null || jsStr(score).trim().isEmpty) return null;
  final n = score is num ? score : num.tryParse(jsStr(score).trim());
  if (n == null || !n.isFinite || n < 0 || n > scale) return null;
  final v = votes == null ? null : (votes is num ? votes : num.tryParse(jsStr(votes)));
  final okVotes = v != null && v == v.truncate() && v >= 0 && v.abs() <= 9007199254740991;
  return {'score': _out(n), 'scale': _out(scale), 'votes': okVotes ? v.toInt() : null};
}

/// A JSON number as the website would write it (whole numbers without ".0").
num _out(num n) => n is double && n == n.truncateToDouble() && n.abs() < 9e15 ? n.toInt() : n;

/// `mf439Entry`: a source's record.
Map<String, dynamic> sourceEntry(String provider, Object? id, Object? title, [Map<String, dynamic> other = const {}]) => {
      'provider': provider,
      'recordId': _slice(jsStr(id), 110),
      'title': plainText(title, 220),
      'year': 0,
      'externalIds': <String, dynamic>{},
      'fields': <String, dynamic>{},
      'ratings': <String, dynamic>{},
      'legacy': <String, dynamic>{},
      ...other,
    };

// ---------- category helpers ----------

/// What the engine needs to know about the title's category.
class TitleKind {
  const TitleKind({this.unit = '', this.type = ''});
  final String unit, type;
}

bool _isMovie(Map<String, dynamic> item, TitleKind kind) {
  final unit = kind.unit.toLowerCase();
  final fmt = jsStr(_or(item['mediaFormat'], asMap(asMap(item['universalMetadata'])?['fields'])?['mediaFormat'])).toLowerCase();
  return unit == 'movies' || RegExp(r'\bmovie|film\b').hasMatch(fmt);
}

bool _isSeries(TitleKind kind) => kind.unit.toLowerCase() == 'episodes';

final _seasonMarker = RegExp(
  r'^(.{2,}?)(?:\s*[:\-–—]\s*|\s+)(?:season\s*\d+|\d+(?:st|nd|rd|th)\s+season|s\d{1,2}|part\s*\d+|cour\s*\d+|(?:the\s+)?final\s+season(?:\s*(?:part|cour)\s*\d+)?|第?\d+期|second season|third season|fourth season|fifth season)(?:\s*[:\-–—].*)?$',
  caseSensitive: false,
  dotAll: false,
);

/// `mf555rBaseShowName`: "Attack on Titan Season 3" → "Attack on Titan".
String? baseShowName(Object? title) {
  final t = jsStr(title).trim();
  if (t.contains('\n')) return null;
  final m = _seasonMarker.firstMatch(t);
  return m == null ? null : m[1]!.trim();
}

int _rowYear(Map<String, dynamic>? row) {
  final legacy = asMap(row?['legacy']);
  return yearOf(_or(row?['year'], _or(legacy?['year'], legacy?['releaseDate'])));
}

String _rowType(Map<String, dynamic>? row) {
  final keys = (asMap(row?['externalIds']) ?? const {}).keys.toList();
  if (keys.contains('tmdb_tv')) return 'series';
  if (row?['provider'] == 'tmdb' && keys.contains('tmdb')) return 'movie';
  final f = jsStr(_or(asMap(row?['legacy'])?['mediaFormat'], asMap(row?['fields'])?['mediaFormat'])).toLowerCase();
  if (RegExp(r'series|tv|show').hasMatch(f)) return 'series';
  if (RegExp(r'movie|film').hasMatch(f)) return 'movie';
  return '';
}

bool _idsConflict(Map<String, dynamic>? row, Map<String, String> ids) {
  for (final e in (asMap(row?['externalIds']) ?? const {}).entries) {
    final v = e.value;
    if (jsTruthy(v) && (ids[e.key] ?? '').isNotEmpty && ids[e.key]!.toLowerCase() != jsStr(v).toLowerCase()) return true;
  }
  return false;
}

String _idMatch(Map<String, dynamic>? row, Map<String, String> ids) {
  for (final k in _recordKeys[jsStr(row?['provider'])] ?? const <String>[]) {
    final v = asMap(row?['externalIds'])?[k];
    if (jsTruthy(v) && (ids[k] ?? '').isNotEmpty && ids[k]!.toLowerCase() == jsStr(v).toLowerCase()) return k;
  }
  return '';
}

/// `mf555rQuery`: what a source is asked.
Map<String, dynamic> lookupQuery(Map<String, dynamic> item, String title, Map<String, String> ids) => {
      'id': item['id'],
      'title': title,
      'categoryId': item['categoryId'],
      'year': item['year'],
      'releaseDate': item['releaseDate'],
      'externalIds': {...ids},
      'universalMetadata': {'mediaType': jsStr(asMap(item['universalMetadata'])?['mediaType']).isEmpty ? 'unspecified' : jsStr(asMap(item['universalMetadata'])?['mediaType'])},
    };

// ---------- the engine ----------

/// Asks one source about a title; returns its records (`mf555rLookup`).
typedef SourceLookup = Future<List<Map<String, dynamic>>> Function(String provider, Map<String, dynamic> query);

/// What Wikidata links for a title (`mf555rWikidata`).
class WikiLinks {
  WikiLinks(this.qid, this.ids, [this.parentIds]);
  final String qid;
  final Map<String, String> ids;
  final Map<String, String>? parentIds;
}

typedef WikiLookup = Future<WikiLinks?> Function(Map<String, String> ids);

class DiscoveredId {
  DiscoveredId(this.value, this.via);
  final String value, via;
  bool conflict = false;
}

class RatingsFound {
  RatingsFound(this.accepted, this.discovered, this.failures, this.names);
  final List<Map<String, dynamic>> accepted;
  final Map<String, DiscoveredId> discovered;
  final List<(String, String)> failures;
  final List<String> names;
}

final _idValue = RegExp(r'^[A-Za-z0-9_:.-]{1,120}$');
final _ascii = RegExp(r'^[\x00-\x7F]+$');

/// `mf555RatingsForTitle`.
Future<RatingsFound> ratingsForTitle(
  Map<String, dynamic> item, {
  required List<String> providers,
  required TitleKind kind,
  required SourceLookup lookup,
  WikiLookup? wikidata,
  StopToken? stop,
  void Function(String note)? progress,
}) async {
  final note = progress ?? (_) {};
  final savedIds = <String, String>{};
  (asMap(item['externalIds']) ?? const {}).forEach((k, v) {
    if (v != null && jsStr(v).trim().isNotEmpty) savedIds[k] = jsStr(v);
  });
  final ids = {...savedIds};
  final discovered = <String, DiscoveredId>{};
  final accepted = <Map<String, dynamic>>[];
  final done = <String>{};
  final failures = <(String, String)>[];
  final names = <String, String>{};
  void addName(Object? n) {
    final v = plainText(n, 220), k = normTitle(v);
    if (k.isNotEmpty && !names.containsKey(k)) names[k] = v;
  }

  for (final n in titleVariants(item)) {
    addName(n);
  }
  final fields = asMap(asMap(item['universalMetadata'])?['fields']);
  final itemYear = yearOf(_or(item['year'], _or(item['releaseDate'], fields?['releaseDate'])));
  final movie = _isMovie(item, kind), series = _isSeries(kind);

  void learn(Map<String, dynamic> row, String via) {
    addName(row['title']);
    for (final a in asList(row['aliases'])) {
      addName(a);
    }
    (asMap(row['externalIds']) ?? const {}).forEach((k, v) {
      final val = v == null ? '' : jsStr(v).trim();
      if (val.isEmpty || !_idValue.hasMatch(val)) return;
      if (savedIds.containsKey(k)) return;
      final d = discovered[k];
      if (d != null && d.value != val) {
        d.conflict = true;
        return;
      }
      discovered[k] ??= DiscoveredId(val, via);
      if ((ids[k] ?? '').isEmpty) ids[k] = val;
    });
  }

  void accept(Map<String, dynamic> row, String via) {
    accepted.add({...row, 'mf555Via': via});
    done.add(jsStr(row['provider']));
    learn(row, via);
  }

  Future<List<Map<String, dynamic>>> call(String provider, Map<String, dynamic> query) async {
    stop?.check();
    try {
      return await lookup(provider, query);
    } on RatingsStopped {
      rethrow;
    } catch (e) {
      stop?.check();
      failures.add((provider, _slice('$e'.replaceFirst('Exception: ', ''), 160)));
      return const [];
    }
  }

  bool canById(String p) => (_idLookup[p] ?? const []).any((k) => (ids[k] ?? '').isNotEmpty);

  // 1. Saved IDs first.
  for (final p in providers) {
    if (!canById(p)) continue;
    note('Checking $p by saved ID…');
    for (final row in await call(p, lookupQuery(item, jsStr(item['title']), ids))) {
      if (_idsConflict(row, savedIds)) continue;
      if (_idMatch(row, ids).isNotEmpty) {
        accept(row, 'saved-id');
        break;
      }
    }
  }

  // 2a. Wikidata links between MAL / AniList / IMDb / TMDB.
  WikiLinks? wiki;
  if (wikidata != null && ['mal', 'anilist', 'imdb', 'tmdb', 'tmdb_tv'].any((k) => (ids[k] ?? '').isNotEmpty)) {
    note('Linking IDs through Wikidata…');
    try {
      wiki = await wikidata(ids);
    } on RatingsStopped {
      rethrow;
    } catch (_) {
      stop?.check();
    }
    wiki?.ids.forEach((k, v) {
      if (savedIds.containsKey(k) && savedIds[k] != v) return;
      if (!savedIds.containsKey(k) && !discovered.containsKey(k)) {
        discovered[k] = DiscoveredId(v, 'wikidata');
        ids[k] = v;
      }
    });
  }

  // 2b. Search every missing source with every known name.
  List<String> ordered() {
    final list = names.values.toList();
    final asciiFirst = [...list.where(_ascii.hasMatch), ...list.where((n) => !_ascii.hasMatch(n))];
    return asciiFirst.length > 6 ? asciiFirst.sublist(0, 6) : asciiFirst;
  }

  Map<String, dynamic>? pickByName(List<Map<String, dynamic>> rows, Set<String> variantSet) {
    final hits = rows.where((row) {
      if (!jsTruthy(row['recordId']) || _idsConflict(row, savedIds)) return false;
      final rowNames = [row['title'], ...asList(row['aliases'])].map(normTitle);
      if (!rowNames.any(variantSet.contains)) return false;
      final y = _rowYear(row);
      if (itemYear != 0 && y != 0 && (itemYear - y).abs() > 1) return false;
      final type = _rowType(row);
      if (type.isNotEmpty && movie && type == 'series') return false;
      if (type.isNotEmpty && series && type == 'movie') return false;
      return true;
    });
    final distinct = <String, Map<String, dynamic>>{};
    for (final r in hits) {
      distinct['${r['provider']}:${r['recordId']}'] = r;
    }
    if (distinct.length == 1) return distinct.values.first;
    final sameYear = distinct.values.where((r) => itemYear != 0 && _rowYear(r) == itemYear).toList();
    return sameYear.length == 1 ? sameYear.first : null;
  }

  for (final p in providers) {
    if (done.contains(p) || canById(p)) continue;
    final variants = ordered();
    final known = names.keys.toSet();
    for (final v in variants) {
      note('Searching $p for “${_slice(v, 60)}”…');
      final row = pickByName(await call(p, lookupQuery(item, v, ids)), known);
      if (row != null) {
        accept(row, 'name');
        break;
      }
    }
  }

  // 3. Recheck: sources that can now be asked by a newly found ID.
  for (final p in providers) {
    if (done.contains(p) || !canById(p)) continue;
    note('Checking $p with newly found ID…');
    for (final row in await call(p, lookupQuery(item, jsStr(item['title']), ids))) {
      if (_idsConflict(row, savedIds)) continue;
      if (_idMatch(row, ids).isNotEmpty) {
        accept(row, 'new-id');
        break;
      }
    }
  }

  // Seasons: share the whole show's IMDb / TMDB rating.
  bool hasRating(String key) => accepted.any((r) => asMap(r['ratings'])?[key] != null);
  if (!movie) {
    final needImdb = !hasRating('imdb') && !savedIds.containsKey('imdb');
    final needTmdb = !hasRating('tmdb') && !savedIds.containsKey('tmdb_tv') && !savedIds.containsKey('tmdb');
    if (needImdb || needTmdb) {
      final parentIds = <String, String>{};
      final pIds = wiki?.parentIds;
      if ((pIds?['imdb'] ?? '').isNotEmpty && needImdb) parentIds['imdb'] = pIds!['imdb']!;
      if ((pIds?['tmdb_tv'] ?? '').isNotEmpty && needTmdb) parentIds['tmdb_tv'] = pIds!['tmdb_tv']!;
      final base = <String>[];
      for (final n in names.values) {
        final b = baseShowName(n);
        if (b != null && b.isNotEmpty && !base.contains(b)) base.add(b);
      }
      for (final (p, key) in [('omdb', 'imdb'), ('tmdb', 'tmdb_tv')]) {
        if (!providers.contains(p) || (key == 'imdb' ? !needImdb : !needTmdb)) continue;
        Map<String, dynamic>? row;
        if (parentIds[key] != null) {
          note('Checking the whole show on $p…');
          for (final r in await call(p, lookupQuery(item, jsStr(item['title']), {key: parentIds[key]!}))) {
            if (jsStr(asMap(r['externalIds'])?[key]).toLowerCase() == parentIds[key]!.toLowerCase()) {
              row = r;
              break;
            }
          }
        }
        for (final b in base.take(3)) {
          if (row != null) break;
          note('Searching $p for the whole show “${_slice(b, 60)}”…');
          final rows = (await call(p, lookupQuery({...item, 'year': 0}, b, const {}))).where((r) {
            if (!jsTruthy(r['recordId']) || normTitle(r['title']) != normTitle(b)) return false;
            if (_rowType(r) == 'movie') return false;
            final y = _rowYear(r);
            return itemYear == 0 || y == 0 || y <= itemYear;
          });
          final distinct = <String, Map<String, dynamic>>{};
          for (final r in rows) {
            distinct[jsStr(r['recordId'])] = r;
          }
          final list = distinct.values.toList();
          // Several shows with the same name: the most recent one that started before this season.
          mergeSortBy(list, (a, b) => _rowYear(b) - _rowYear(a));
          if (list.length == 1 ||
              (list.length > 1 && itemYear != 0 && _rowYear(list[0]) != 0 && _rowYear(list[0]) != _rowYear(list[1]))) {
            row = list[0];
          }
        }
        // The show's ID is not this season's ID: share the rating, don't save the ID.
        if (row != null) accepted.add({...row, 'externalIds': <String, dynamic>{}, 'mf555Via': 'whole-show'});
      }
    }
  }
  return RatingsFound(accepted, discovered, failures, names.values.toList());
}

/// A stable sort (JavaScript's Array.prototype.sort is stable).
void mergeSortBy<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}

// ---------- writing results (v437 + v555) ----------

/// `mf437Normalized`: the title's universal-metadata envelope.
Map<String, dynamic> normalizedEnvelope(Object? input) {
  final d = asMap(input) ?? const <String, dynamic>{};
  final out = <String, dynamic>{...d};
  final sv = jsNum(d['schemaVersion']);
  out['schemaVersion'] = _out(sv.isFinite && sv > 1 ? sv : 1);
  out['mediaType'] = kMediaTypes.contains(d['mediaType']) ? d['mediaType'] : 'unspecified';
  out['fields'] = {...?asMap(d['fields'])};
  out['externalRatings'] = {...?asMap(d['externalRatings'])};
  out['provenance'] = {...?asMap(d['provenance'])};
  out['locks'] = {...?asMap(d['locks'])};
  final u = jsNum(d['updatedAt']);
  out['updatedAt'] = _out(u.isFinite && u > 0 ? u : 0);
  return out;
}

/// `mf439IsProtected` for a rating.
bool _isProtected(Map<String, dynamic> item, String token) {
  final meta = asMap(item['universalMetadata']);
  return asMap(meta?['locks'])?[token] == true || asMap(asMap(meta?['provenance'])?[token])?['source'] == 'manual';
}

/// `mf439Value` for a rating token.
Map<String, dynamic>? ratingValue(String key, Object? input) {
  if (!kRatingMap.containsKey(key)) return null;
  final x = asMap(input);
  if (x == null || x['score'] == null) return null;
  final score = jsNumOrNull(x['score']) ?? double.nan, scale = jsNumOrNull(x['scale']) ?? double.nan;
  if (!score.isFinite || !scale.isFinite || scale <= 0 || scale > 100 || score < 0 || score > scale) return null;
  final votes = x['votes'] == null ? null : jsNumOrNull(x['votes']);
  final okVotes = votes != null && votes == votes.truncateToDouble() && votes >= 0 && votes <= 9007199254740991;
  return {'score': _out(score), 'scale': _out(scale), 'votes': okVotes ? votes.toInt() : null};
}

bool _sameJson(Map<String, dynamic> a, Map<String, dynamic> b) {
  for (final k in a.keys) {
    final x = a[k], y = b[k];
    if (x is num && y is num) {
      if (x != y) return false;
    } else if (x != y) {
      return false;
    }
  }
  return true;
}

/// `mf437SetRating` for a verified source.
bool setRatingInEnvelope(Map<String, dynamic> env, String key, Map<String, dynamic> rating,
        {required String source, required bool force, required int updatedAt}) =>
    _setRating(env, key, rating, source: source, force: force, updatedAt: updatedAt);

bool _setRating(Map<String, dynamic> env, String key, Map<String, dynamic> rating,
    {required String source, required bool force, required int updatedAt}) {
  final def = kRatingMap[key];
  if (def == null) return false;
  final token = 'rating.$key';
  final locks = env['locks'] as Map<String, dynamic>;
  if (locks[token] == true) return false;
  final score = rating['score'] == null || jsStr(rating['score']).trim().isEmpty ? null : jsNum(rating['score']);
  final scale = jsNum(rating['scale'] ?? def.$3);
  final votes = rating['votes'] == null || jsStr(rating['votes']).trim().isEmpty ? null : jsNum(rating['votes']);
  if ((score != null && !score.isFinite) || !scale.isFinite || scale <= 0 || scale > 100000 ||
      (score != null && (score < 0 || score > scale)) ||
      (votes != null && (votes != votes.truncateToDouble() || votes < 0))) {
    return false;
  }
  final ratings = env['externalRatings'] as Map<String, dynamic>;
  final existing = asMap(ratings[key]) ?? const <String, dynamic>{};
  if (existing['score'] != null && !force) return false;
  final next = {'score': score == null ? null : _out(score), 'scale': _out(scale), 'votes': votes == null ? null : _out(votes), 'url': ''};
  final prev = {
    'score': existing['score'],
    'scale': existing['scale'] ?? def.$3,
    'votes': existing['votes'],
    'url': jsTruthy(existing['url']) ? existing['url'] : '',
  };
  if (_sameJson(prev, next)) return false;
  ratings[key] = {...next, 'updatedAt': updatedAt, 'source': source};
  (env['provenance'] as Map<String, dynamic>)[token] = {'source': source, 'verified': true, 'updatedAt': updatedAt};
  final u = jsNum(env['updatedAt']);
  env['updatedAt'] = _out(u > updatedAt ? u : updatedAt);
  return true;
}

class RatingsWritten {
  const RatingsWritten(this.ratings, this.ids);
  final int ratings, ids;
  int get changed => ratings + ids;
}

/// `mf555ApplyRatings`: writes the found ratings and new IDs into [item]
/// (a Library title, changed in place) exactly as the website does.
RatingsWritten applyRatings(Map<String, dynamic> item, RatingsFound result, int now) {
  final env = normalizedEnvelope(item['universalMetadata']);
  var ratings = 0, idsWritten = 0;
  final byKey = <String, (Map<String, dynamic>, Map<String, dynamic>, int, int)>{};
  for (final row in result.accepted) {
    (asMap(row['ratings']) ?? const {}).forEach((key, value) {
      final valid = ratingValue(key, value);
      if (valid == null) return;
      final prio = (_primary[key] ?? const []).indexOf(jsStr(row['provider']));
      final rank = prio < 0 ? 99 : prio;
      final viaRank = row['mf555Via'] == 'whole-show' ? 1 : 0;
      final cur = byKey[key];
      if (cur == null || viaRank < cur.$4 || (viaRank == cur.$4 && rank < cur.$3)) byKey[key] = (row, valid, rank, viaRank);
    });
  }
  final extRatings = env['externalRatings'] as Map<String, dynamic>;
  final provenance = env['provenance'] as Map<String, dynamic>;
  for (final entry in byKey.entries) {
    final key = entry.key, row = entry.value.$1, value = entry.value.$2;
    final token = 'rating.$key';
    if (_isProtected(item, token)) continue;
    final existing = asMap(extRatings[key]), prov = asMap(provenance[token]);
    final has = existing != null && existing['score'] != null && jsStr(existing['score']).trim().isNotEmpty;
    final sameSource = prov != null &&
        prov['verified'] == true &&
        prov['source'] == row['provider'] &&
        (!jsTruthy(prov['recordId']) || jsStr(prov['recordId']) == jsStr(row['recordId']));
    if (has && !sameSource) continue;
    if (has &&
        jsNum(existing['score']) == jsNum(value['score']) &&
        jsNum(existing['scale']) == jsNum(value['scale']) &&
        (existing['votes'] == null ? null : jsNum(existing['votes'])) == (value['votes'] == null ? null : jsNum(value['votes']))) {
      continue;
    }
    if (_setRating(env, key, value, source: jsStr(row['provider']), force: has, updatedAt: now)) {
      provenance[token] = {
        'source': jsStr(row['provider']),
        'verified': true,
        'recordId': jsStr(row['recordId']),
        'updatedAt': now,
        if (row['mf555Via'] == 'whole-show') 'scope': 'whole-show',
      };
      ratings++;
    }
  }
  final ids = <String, dynamic>{...?asMap(item['externalIds'])};
  for (final e in result.discovered.entries) {
    final d = e.value;
    if (d.conflict || !kSavableIdKeys.contains(e.key)) continue;
    if (ids[e.key] != null && jsStr(ids[e.key]).trim().isNotEmpty) continue;
    ids[e.key] = d.value;
    idsWritten++;
  }
  if (ratings > 0) item['universalMetadata'] = env;
  if (idsWritten > 0) item['externalIds'] = ids;
  if (ratings + idsWritten > 0) {
    final m = jsNum(item['modifiedAt']);
    item['modifiedAt'] = m.isFinite && m > now ? _out(m) : now;
  }
  return RatingsWritten(ratings, idsWritten);
}

// ---------- which sources a title uses ----------

/// `mf439Preferences().enabled`.
List<String> enabledSources(Map<String, dynamic>? settings) {
  final data = asMap(asMap(settings)?['v439Metadata']);
  final enabled = data?['enabled'];
  if (enabled is List) return enabled.whereType<String>().toList();
  return [...kPublicSources, ...kGatewaySources];
}

/// `mf555rSourcesFor(item, mf467RatingProviders(item))`: the rating sources
/// for a title, best first. [gatewayReady] are the gateway sources set up on
/// the server (the gateway's status).
List<String> ratingSourcesFor(Map<String, dynamic> item, Map<String, dynamic>? settings, TitleKind kind, Set<String> gatewayReady) {
  final enabled = enabledSources(settings).toSet();
  final presets = asMap(asMap(settings)?['v453RecoveryPresets']);
  final preset = asMap(presets?[jsStr(item['categoryId'])])?['metadata'];
  final selected = preset is List ? preset.whereType<String>().toSet() : enabled;
  final all = kAvailableSources
      .where((id) => (!kGatewaySources.contains(id) || gatewayReady.contains(id)) && selected.contains(id))
      .toList();
  final ids = asMap(item['externalIds']) ?? const {};
  final saved = asMap(asMap(item['universalMetadata'])?['provenance']) ?? const {};
  const keyMap = {
    'jikan': ['mal'], 'malofficial': ['mal'], 'anilist': ['anilist'], 'kitsu': ['kitsu'], 'tvmaze': ['tvmaze'], 'vndb': ['vndb'],
    'tmdb': ['tmdb', 'tmdb_tv'], 'omdb': ['imdb'], 'trakt': ['trakt'], 'simkl': ['simkl'], 'watchmode': ['watchmode'],
  };
  final ranked = <(String, int, int)>[];
  var index = 0;
  for (final id in all.toSet()) {
    if (!enabled.contains(id) || !kRatingProviders.contains(id)) continue;
    final weight = (keyMap[id] ?? [id]).any((k) => jsTruthy(ids[k]))
        ? 4
        : saved.entries.any((e) => e.key.startsWith('rating.') && asMap(e.value)?['source'] == id && asMap(e.value)?['verified'] == true)
            ? 3
            : 0;
    ranked.add((id, index++, weight));
  }
  ranked.sort((a, b) => b.$3 != a.$3 ? b.$3 - a.$3 : a.$2 - b.$2);
  final providers = ranked.map((x) => x.$1).toList();
  final allowed = _byType[kind.type];
  return allowed == null ? providers : providers.where(allowed.contains).toList();
}

/// `mf555HasNoRatings`.
bool hasNoRatings(Map<String, dynamic> item) {
  final r = asMap(asMap(item['universalMetadata'])?['externalRatings']) ?? const {};
  return !r.values.any((x) => asMap(x)?['score'] != null && jsStr(asMap(x)!['score']).trim().isNotEmpty);
}

bool _scoreExists(Map<String, dynamic> item, String key) {
  final r = asMap(asMap(asMap(item['universalMetadata'])?['externalRatings'])?[key]);
  final s = r?['score'];
  return s != null && jsStr(s).trim().isNotEmpty && (jsNumOrNull(s)?.isFinite ?? false);
}

/// `mf547MissingRating`: the title still lacks a rating its sources could give.
bool missingRating(Map<String, dynamic> item, List<String> providers) {
  final saved = asMap(item['externalIds']) ?? const {};
  final ids = <String, String>{};
  for (final key in kIdRatingMap.keys) {
    final v = jsStr(saved[key]).trim();
    if (v.isNotEmpty) ids[key] = v;
  }
  if (ids.isEmpty) return providers.isNotEmpty;
  for (final e in kIdRatingMap.entries) {
    if ((e.key == 'tmdb' && ids.containsKey('tmdb_tv')) || (e.key == 'tmdb_tv' && ids.containsKey('tmdb'))) continue;
    if (!ids.containsKey(e.key) && e.value.$2.any(providers.contains)) return true;
  }
  for (final id in ids.keys) {
    final map = kIdRatingMap[id];
    if (map == null || !map.$2.any(providers.contains)) continue;
    if (map.$1.any((r) => !_scoreExists(item, r))) return true;
  }
  return false;
}

/// Ratings to show for a title: label, score text and source.
List<(String, String, String)> ratingRows(Map<String, dynamic> item) {
  final env = asMap(asMap(item['universalMetadata'])?['externalRatings']) ?? const {};
  final out = <(String, String, String)>[];
  for (final def in kRatingSources) {
    final r = asMap(env[def.$1]);
    final score = jsNumOrNull(r?['score']);
    if (score == null || !score.isFinite) continue;
    final scale = jsNumOrNull(r?['scale']) ?? def.$3.toDouble();
    String fmt(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(v * 10 == (v * 10).truncateToDouble() ? 1 : 2);
    final votes = jsNumOrNull(r?['votes']);
    out.add((
      def.$2,
      '${fmt(score)} / ${fmt(scale)}${votes != null && votes > 0 ? ' · ${_compact(votes)} votes' : ''}',
      jsStr(r?['source']),
    ));
  }
  return out;
}

String _compact(double n) {
  if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(n >= 1e7 ? 0 : 1)}M';
  if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(n >= 1e4 ? 0 : 1)}K';
  return n.toInt().toString();
}

// ---------- External IDs (v377 editor, v433 / v555 ID finder) ----------

/// `v377IdValid`.
bool idValid(String key, String value) {
  if (value.isEmpty) return true;
  if (value.length > (key == 'royalroad_rss' ? 512 : 120)) return false;
  if (key == 'royalroad_rss') {
    final u = Uri.tryParse(value);
    return u != null && u.scheme == 'https' && u.host.length > 3;
  }
  if (key == 'doi' || key == 'crossref') return RegExp(r'^10\.\d{4,9}/\S{1,100}$', caseSensitive: false).hasMatch(value);
  if (key == 'wikidata') return RegExp(r'^Q[1-9]\d*$', caseSensitive: false).hasMatch(value);
  if (key == 'mangadex') return RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$', caseSensitive: false).hasMatch(value);
  final compact = value.replaceAll(RegExp(r'[-\s]'), '');
  if (key == 'isbn10') return RegExp(r'^\d{9}[\dXx]$').hasMatch(compact);
  if (key == 'isbn13' || key == 'ean') return RegExp(r'^\d{13}$').hasMatch(compact);
  if (['mal', 'anilist', 'tmdb', 'kitsu', 'simkl'].contains(key)) return RegExp(r'^[1-9]\d*$').hasMatch(value);
  if (key == 'imdb') return RegExp(r'^tt\d{7,12}$', caseSensitive: false).hasMatch(value);
  if (key == 'isbn') return RegExp(r'^(?:[\dXx-]{10,20})$').hasMatch(value);
  return RegExp(r'^[\w.:-]+$').hasMatch(value);
}

final Set<String> _finderKeys = {for (final k in kIdKeys) k.$1, 'openlibrary', 'googlebooks', 'tvmaze', 'mal', 'imdb'};

/// `MF433_ALLOWED_ID_KEYS.has(key)`.
bool finderIdKey(String key) => _finderKeys.contains(key);

/// `mf433ValidId`: an ID the finder may offer.
bool finderIdValid(String key, String value) {
  if (!_finderKeys.contains(key) || value.trim().isEmpty) return false;
  if (RegExp(r'[\u0000-\u001f\u007f]').hasMatch(value)) return false;
  return idValid(key, value.trim());
}

String idLabel(String key) {
  for (final k in kIdKeys) {
    if (k.$1 == key) return k.$2;
  }
  return key.toUpperCase();
}

/// Saves edited External IDs the way the website's title editor does
/// (`App.saveLibraryModal` v377): changed IDs are set or removed, each change
/// is remembered in `v377ManualExternalIds` (null = cleared on purpose), and a
/// changed MAL ID drops the old `malId` / `mal_id` aliases. Returns false when
/// nothing changed. [edited] holds every ID field shown (key → value).
bool saveExternalIds(Map<String, dynamic> item, Map<String, String> edited, int now) {
  final oldIds = {...?asMap(item['externalIds'])};
  final manual = {...?asMap(item['v377ManualExternalIds'])};
  final nextIds = {...oldIds};
  var changed = false;
  edited.forEach((key, raw) {
    final value = raw.trim();
    if (jsStr(oldIds[key]).trim() != value) {
      if (value.isNotEmpty) {
        nextIds[key] = value;
      } else {
        nextIds.remove(key);
      }
      manual[key] = value.isEmpty ? null : value;
      changed = true;
    }
  });
  if (!changed) return false;
  item['externalIds'] = nextIds;
  if (manual.containsKey('mal')) {
    item.remove('malId');
    item.remove('mal_id');
  }
  if (manual.isNotEmpty) item['v377ManualExternalIds'] = manual;
  final m = jsNum(item['modifiedAt']);
  item['modifiedAt'] = m > now ? jsOut(m) : now;
  return true;
}
