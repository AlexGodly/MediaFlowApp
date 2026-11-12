// Imports from other services (website Exchange Hub: v40 + v158 metadata
// engine, with the v176 rich metadata, v178/095 manual-field protection,
// v252 seasons, v295 category fallbacks, v377 manual ID overrides and v378 ID
// normalization wrappers) — MyAnimeList XML, Simkl JSON (with its watched
// History), CSV and JSON from AniList, Letterboxd, Trakt, TV Time and the rest
// — and the Exchange export. test/exchange_import_golden_test.dart checks it
// against the website's own code.

import 'dart:convert';
import 'dart:math' as math;

import '../util/js.dart';
import 'rich_fields.dart' show safeText, dateValue, richManualMap;

/// `MF_EXCHANGE_SERVICES`.
const kExchangeServices = [
  ('anilist', 'AniList'), ('anisearch', 'AniSearch'), ('aniwatch', 'AniWatch'), ('betaseries', 'BetaSeries'),
  ('criticker', 'Criticker'), ('crunchyroll', 'Crunchyroll'), ('episodecalendar', 'EpisodeCalendar'), ('hianime', 'HiAnime'),
  ('imdb', 'IMDb'), ('letterboxd', 'Letterboxd'), ('livechart', 'LiveChart'), ('kitsu', 'Kitsu'), ('moviesfad', 'MoviesFad'),
  ('simkl', 'Simkl'), ('mal', 'MyAnimeList'), ('malxml', 'MAL-XML'), ('netflix', 'Netflix'), ('primewire', 'PrimeWire'),
  ('seriesfad', 'SeriesFad'), ('stremio', 'Stremio'), ('trakt', 'trakt'), ('tvtime', 'TV Time'), ('tviso', 'Tviso'),
  ('twee', 'Twee'), ('csv', 'Import .csv file'), ('json', 'Import .json file'),
];

/// `mfServiceName`.
String serviceName(String? id) {
  for (final s in kExchangeServices) {
    if (s.$1 == id) return s.$2;
  }
  return (id ?? '').isEmpty ? 'External service' : id!;
}

// ---- file records ----------------------------------------------------------------------

/// `mfCsvParse`.
List<Map<String, dynamic>> csvRecords(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var q = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i], n = i + 1 < text.length ? text[i + 1] : '';
    if (c == '"') {
      if (q && n == '"') {
        cell.write('"');
        i++;
      } else {
        q = !q;
      }
    } else if (c == ',' && !q) {
      row.add(cell.toString());
      cell.clear();
    } else if ((c == '\n' || c == '\r') && !q) {
      if (c == '\r' && n == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      cell.write(c);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    if (row.any((x) => x.trim().isNotEmpty)) rows.add(row);
  }
  if (rows.isEmpty) return [];
  final h = [
    for (final x in rows.first)
      x.trim().toLowerCase().replaceFirst(RegExp('^﻿'), '').replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), ''),
  ];
  return [
    for (final r in rows.skip(1)) {for (var i = 0; i < h.length; i++) h[i]: (i < r.length ? r[i] : '').trim()},
  ];
}

/// `mfFlattenJson`.
List<dynamic> flattenJson(Object? data) {
  if (data is List) return data;
  final out = <dynamic>[];
  final m = asMap(data);
  for (final k in const ['anime', 'shows', 'movies', 'items', 'entries', 'library', 'watchlist', 'history', 'data', 'results']) {
    if (m?[k] is List) {
      for (final x in m![k] as List) {
        out.add(x is Map ? {'__group': k, ...x.cast<String, dynamic>()} : x);
      }
    }
  }
  return out.isNotEmpty ? out : [data];
}

String _xmlText(String s) {
  var t = s.replaceAllMapped(RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'), (m) => m[1] ?? '');
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  return t
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
      .replaceAll('&amp;', '&')
      .trim();
}

/// `mfXmlRecords`: every anime / manga / item / entry / movie / show / series
/// element, as {child tag (lower case): text}.
List<Map<String, dynamic>> xmlRecords(String text) {
  final body = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  if (!RegExp(r'<[A-Za-z]').hasMatch(body)) throw const FormatException('The XML file could not be parsed.');
  final out = <Map<String, dynamic>>[];
  final block = RegExp(r'<(anime|manga|item|entry|movie|show|series)(\s[^>]*)?>([\s\S]*?)</\1\s*>', caseSensitive: false);
  for (final m in block.allMatches(body)) {
    final inner = m[3]!;
    final o = <String, dynamic>{};
    final child = RegExp(r'<([A-Za-z_][\w.:-]*)(\s[^>]*)?(?:/>|>([\s\S]*?)</\1\s*>)');
    var pos = 0;
    while (true) {
      final c = child.firstMatch(inner.substring(pos));
      if (c == null) break;
      o[c[1]!.toLowerCase()] = _xmlText(c[3] ?? '');
      pos += c.end;
    }
    out.add(o);
  }
  return out;
}

/// Records from a file, the way the website reads it (XML, CSV or JSON).
List<dynamic> fileRecords(String name, String text) {
  final n = name.toLowerCase();
  if (n.endsWith('.xml') || RegExp(r'^\s*<').hasMatch(text)) return xmlRecords(text);
  if (n.endsWith('.csv') || (!n.endsWith('.json') && text.contains(','))) return csvRecords(text);
  return flattenJson(jsonDecode(text));
}

// ---- helpers ---------------------------------------------------------------------------

/// `mfFirst`.
Object? _first(Map<String, dynamic>? o, List<String> keys) {
  for (final k in keys) {
    final v = o?[k];
    if (v != null && _jsString(v).trim().isNotEmpty) return v;
  }
  return null;
}

String _jsString(Object? v) {
  if (v == null) return '';
  if (v is double) return jsOut(v).toString();
  if (v is Map) return '[object Object]';
  if (v is List) return v.map(_jsString).join(',');
  return v.toString();
}

double _number(Object? v) {
  if (v is Map) return 0;
  if (v is List) return v.length == 1 ? _number(v.first) : 0;
  return jsNum(v);
}

/// `mfNormStatus`.
String normStatus(Object? value) {
  final v = _jsString(value).toLowerCase().replaceAll(RegExp(r'[ _-]+'), '');
  if (RegExp('completed|complete|watched|finished').hasMatch(v)) return 'completed';
  if (RegExp('watching|reading|current|inprogress').hasMatch(v)) return 'active';
  if (RegExp('hold|paused').hasMatch(v)) return 'paused';
  if (RegExp('drop').hasMatch(v)) return 'dropped';
  return 'planned';
}

const _animeServices = ['anilist', 'anisearch', 'aniwatch', 'hianime', 'livechart', 'kitsu', 'mal', 'malxml', 'crunchyroll'];

/// `mfGuessCategory` + the v295 fallback.
String _guessCategory(Map<String, dynamic> o, String service, Set<String> categoryIds) {
  final raw = _jsString(_first(o, const ['media_type', 'type', 'kind', 'format', 'category', 'list_type', 'content_type', '__group'])).toLowerCase();
  String id;
  if (RegExp('manga|manhwa|manhua|chapter').hasMatch(raw)) {
    id = RegExp('manhwa|manhua').hasMatch(raw) ? 'manhwa' : 'manga';
  } else if (RegExp('anime').hasMatch(raw) || _animeServices.contains(service)) {
    id = RegExp('movie|film').hasMatch(raw) ? 'animemovies' : 'backlog';
  } else if (RegExp('movie|film').hasMatch(raw) || const ['letterboxd', 'criticker', 'moviesfad'].contains(service)) {
    id = 'movies';
  } else if (RegExp('comic|issue').hasMatch(raw)) {
    id = 'comics';
  } else if (RegExp('animation|cartoon').hasMatch(raw)) {
    id = 'otheranim';
  } else {
    id = 'tv';
  }
  return _v295(id, categoryIds);
}

String _v295(String id, Set<String> categoryIds) {
  if (id == 'manhwa' && !categoryIds.contains('manhwa')) return 'manga';
  if (id == 'otheranim' && !categoryIds.contains('otheranim')) return 'tv';
  return id;
}

/// `v158SafeHttpUrl`.
String _safeHttpUrl(Object? value) {
  if (value == null || value is Map || value is List) return '';
  var s = _jsString(value).trim();
  if (s.isEmpty) return '';
  if (s.startsWith('//')) s = 'https:$s';
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) return '';
  final u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty) return '';
  // new URL(s).href: scheme and host lower case, '/' path when empty.
  final scheme = u.scheme.toLowerCase();
  final rest = s.substring(s.indexOf('//') + 2);
  final slash = rest.indexOf(RegExp(r'[/?#]'));
  final host = (slash < 0 ? rest : rest.substring(0, slash)).toLowerCase();
  final tail = slash < 0 ? '/' : (rest[slash] == '/' ? rest.substring(slash) : '/${rest.substring(slash)}');
  return '$scheme://$host${tail.replaceAll(' ', '%20')}';
}

/// `v158ParseDateLike`.
int parseDateLike(Object? value) {
  if (value == null || value == '') return 0;
  if (value is num) {
    if (!value.isFinite) return 0;
    if (value > 1e12) return jsRound(value.toDouble()).toInt();
    if (value > 1e9) return jsRound(value * 1000.0).toInt();
    return 0;
  }
  if (value is Map || value is List) return 0;
  final s = _jsString(value).trim();
  if (s.isEmpty || s == '0' || s == '0000-00-00' || s == '0000-00-00 00:00:00') return 0;
  if (RegExp(r'^\d{10}$').hasMatch(s)) return int.parse(s) * 1000;
  if (RegExp(r'^\d{13}$').hasMatch(s)) return int.parse(s);
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    final n = localNoonMs(s);
    if (n != null) return n;
  }
  return _dateParse(s);
}

const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/// `Date.parse` for the forms exports use.
int _dateParse(String s) {
  // ISO 8601 with a time (a zone → that zone; none → local, like JS).
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?\s*(Z|[+-]\d{2}:?\d{2})?$', caseSensitive: false)
      .firstMatch(s);
  if (iso != null) {
    final norm = '${iso[1]}-${iso[2]}-${iso[3]}T${iso[4]}:${iso[5]}:${iso[6] ?? '00'}${iso[7] == null ? '' : '.${iso[7]}'}${(iso[8] ?? '').replaceAllMapped(RegExp(r'^([+-]\d{2})(\d{2})$'), (m) => '${m[1]}:${m[2]}')}';
    return DateTime.tryParse(norm)?.millisecondsSinceEpoch ?? 0;
  }
  // Date-only ISO forms are UTC in JS.
  final ym = RegExp(r'^(\d{4})(?:-(\d{2}))?$').firstMatch(s);
  if (ym != null) return DateTime.utc(int.parse(ym[1]!), int.parse(ym[2] ?? '1')).millisecondsSinceEpoch;
  // "Mar 4, 2021" / "4 Mar 2021" (local midnight, like JS).
  final a = RegExp(r'^([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})$').firstMatch(s);
  final b = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?,?\s+(\d{4})$').firstMatch(s);
  if (a != null || b != null) {
    final mon = _months.indexOf((a?[1] ?? b![2]!).toLowerCase());
    if (mon < 0) return 0;
    return DateTime(int.parse(a?[3] ?? b![3]!), mon + 1, int.parse(a?[2] ?? b![1]!)).millisecondsSinceEpoch;
  }
  // "2021/03/04" (local, like JS).
  final sl = RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})$').firstMatch(s);
  if (sl != null) return DateTime(int.parse(sl[1]!), int.parse(sl[2]!), int.parse(sl[3]!)).millisecondsSinceEpoch;
  return 0;
}

int _firstDate(Map<String, dynamic>? obj, List<String> keys) {
  for (final k in keys) {
    if (obj == null) continue;
    final ts = parseDateLike(obj[k]);
    if (ts > 0) return ts;
  }
  return 0;
}

/// `v158NestedObjects`.
List<Map<String, dynamic>> _nested(Map<String, dynamic> raw) {
  final out = <Map<String, dynamic>>[];
  void push(Object? x) {
    final m = x is Map ? asMap(x) : null;
    if (m != null && !out.any((o) => identical(o, m))) out.add(m);
  }

  push(raw);
  for (final k in const ['show', 'movie', 'media', 'anime', 'manga', 'item', 'node', 'entry', 'book', 'list_status', 'listStatus', 'user_data', 'userData', 'details']) {
    push(raw[k]);
  }
  return out;
}

/// `v158UrlFromImageValue`.
String _urlFromImage(Object? value) {
  if (value == null || value == '' || value == false || value == 0) return '';
  if (value is String) return _safeHttpUrl(value);
  final m = value is Map ? asMap(value) : null;
  if (m == null) return '';
  for (final k in const ['large_image_url', 'image_url', 'original', 'large', 'medium', 'small', 'url', 'src', 'href', 'poster', 'cover']) {
    final u = _safeHttpUrl(m[k]);
    if (u.isNotEmpty) return u;
  }
  for (final k in const ['jpg', 'webp', 'image', 'images', 'main_picture', 'poster', 'cover']) {
    final u = _urlFromImage(m[k]);
    if (u.isNotEmpty) return u;
  }
  return '';
}

/// `v158ExtractCoverUrl`.
String _coverUrl(Map<String, dynamic> raw) {
  for (final obj in _nested(raw)) {
    for (final k in const ['coverUrl', 'cover_url', 'cover', 'cover_image', 'coverImage', 'posterUrl', 'poster_url', 'poster', 'imageUrl', 'image_url',
      'series_image', 'anime_image', 'manga_image', 'main_picture', 'images', 'image', 'thumbnail_url', 'thumbnail']) {
      final u = _urlFromImage(obj[k]);
      if (u.isNotEmpty) return u;
    }
  }
  return '';
}

// ---- external IDs (v158 + v378) ---------------------------------------------------------

const kImportIdAliases = <String, List<String>>{
  'mal': ['mal', 'myanimelist', 'myanimelist_id', 'mal_id', 'series_animedb_id', 'series_mangadb_id', 'manga_mangadb_id'],
  'simkl': ['simkl', 'simkl_id'],
  'anilist': ['anilist', 'ani_list', 'anilist_id'],
  'tmdb': ['tmdb', 'tmdb_id', 'tmdbtv'],
  'imdb': ['imdb', 'imdb_id', 'imdbid'],
  'trakt': ['trakt', 'trakt_id'],
  'kitsu': ['kitsu', 'kitsu_id'],
  'isbn': ['isbn', 'isbn10', 'isbn13'],
};

/// `v378NormalizeId`.
String normalizeImportId(String key, Object? value) {
  var s = _jsString(value).trim();
  if (s.isEmpty || s == 'null' || s == '0') return '';
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(s)) {
    if (key == 'mal') {
      final m = RegExp(r'myanimelist\.net/(?:anime|manga)/(\d+)', caseSensitive: false).firstMatch(s);
      if (m == null) return '';
      s = m[1]!;
    } else if (key == 'imdb') {
      final m = RegExp(r'imdb\.com/title/(tt\d+)', caseSensitive: false).firstMatch(s);
      if (m == null) return '';
      s = m[1]!;
    } else {
      final u = Uri.tryParse(s);
      if (u == null) return '';
      final parts = u.path.split('/').where((p) => p.isNotEmpty).toList();
      s = parts.isEmpty ? '' : Uri.decodeComponent(parts.last);
    }
  }
  if (key == 'mal' || const ['simkl', 'anilist', 'tmdb', 'kitsu'].contains(key)) return RegExp(r'^[1-9]\d*$').hasMatch(s) ? s : '';
  if (key == 'imdb') return RegExp(r'^tt\d{7,12}$', caseSensitive: false).hasMatch(s) ? s.toLowerCase() : '';
  if (key == 'isbn') return RegExp(r'^[\dXx-]{10,20}$').hasMatch(s) ? s : '';
  return RegExp(r'^[\w.:-]{1,120}$').hasMatch(s) ? s : '';
}

/// `v378ExtractIds`.
Map<String, String> _extractIds(Map<String, dynamic> record) {
  final out = <String, String>{};
  final sources = <Map<String, dynamic>>[];
  for (final v in [
    record, record['externalIds'], record['ids'], record['show'], asMap(record['show'])?['ids'], record['movie'], asMap(record['movie'])?['ids'],
    record['anime'], asMap(record['anime'])?['ids'], record['media'], asMap(record['media'])?['ids'], record['node'], asMap(record['node'])?['ids'],
    record['item'], asMap(record['item'])?['ids'],
  ]) {
    final m = v is Map ? asMap(v) : null;
    if (m != null) sources.add(m);
  }
  for (final e in kImportIdAliases.entries) {
    for (final obj in sources) {
      var found = '';
      for (final alias in e.value) {
        if (obj[alias] != null) {
          found = normalizeImportId(e.key, obj[alias]);
          if (found.isNotEmpty) break;
        }
      }
      if (found.isNotEmpty) {
        out[e.key] = found;
        break;
      }
    }
  }
  return out;
}

/// `v158NormalizeExternalIds` (+ v378).
Map<String, dynamic> _externalIds(Map<String, dynamic> raw) {
  final objs = _nested(raw);
  Object? first(List<String> names) {
    for (final o in objs) {
      final ids = asMap(o['ids']) ?? const <String, dynamic>{};
      for (final n in names) {
        for (final v in [ids[n], o[n], o['${n}_id'], o['${n}Id']]) {
          if (v != null && _jsString(v).trim().isNotEmpty) return v;
        }
      }
    }
    return null;
  }

  final prior = <String, Object?>{
    'simkl': first(['simkl']),
    'mal': first(['mal', 'series_animedb', 'series_mangadb', 'manga_mangadb']),
    'anilist': first(['anilist', 'ani_list']),
    'tmdb': first(['tmdb', 'tmdbtv', 'tmdb_movie', 'tmdb_show']),
    'imdb': first(['imdb', 'imdbid', 'const']),
    'trakt': first(['trakt']),
    'kitsu': first(['kitsu']),
    'isbn': first(['isbn', 'isbn13', 'isbn10']),
  };
  if (prior['mal'] == null) {
    for (final o in objs) {
      final v = o['series_animedb_id'] ?? o['manga_mangadb_id'] ?? o['series_mangadb_id'];
      if (v != null && _jsString(v).trim().isNotEmpty) {
        prior['mal'] = v;
        break;
      }
    }
  }
  if (prior['imdb'] == null) {
    for (final o in objs) {
      final v = o['const'];
      if (v != null && _jsString(v).trim().isNotEmpty) {
        prior['imdb'] = v;
        break;
      }
    }
  }
  final mapped = _extractIds(raw);
  final out = <String, dynamic>{};
  for (final key in kImportIdAliases.keys) {
    final m = mapped[key] ?? '';
    final value = m.isNotEmpty ? m : normalizeImportId(key, prior[key]);
    if (value.isNotEmpty) out[key] = value;
  }
  return out;
}

// ---- category (v158 + v295) -------------------------------------------------------------

String _inferCategory(Map<String, dynamic> raw, String service, Set<String> categoryIds) {
  final objs = _nested(raw);
  final flat = <String, dynamic>{};
  for (final o in objs.reversed) {
    flat.addAll(o);
  }
  flat.addAll(raw);
  final group = _jsString(raw['__group']).toLowerCase();
  final mangaSignal = flat['manga_title'] != null ||
      flat['my_read_chapters'] != null ||
      flat['num_chapters_read'] != null ||
      group == 'manga' ||
      RegExp('manga|manhwa|manhua').hasMatch(_jsString(flat['manga_type']).toLowerCase());
  if (mangaSignal) {
    final t = _jsString(_or(flat['manga_type'], flat['type'], flat['format'])).toLowerCase();
    return _v295(RegExp('manhwa|manhua').hasMatch(t) ? 'manhwa' : 'manga', categoryIds);
  }
  final animeSignal = flat['anime_title'] != null || flat['series_animedb_id'] != null || group == 'anime' || _animeServices.contains(service);
  if (animeSignal) {
    final type = _jsString(_or(flat['series_type'], flat['anime_type'], flat['type'], flat['format'])).toLowerCase();
    if (RegExp('movie|film').hasMatch(type)) return 'animemovies';
    if (RegExp('currently airing|airing').hasMatch(_jsString(_or(flat['series_status'], flat['airing_status'])))) return 'seasonal';
    if (flat['airing'] == true || flat['is_airing'] == true || _number(flat['not_aired_episodes_count']) > 0) return 'seasonal';
    return 'backlog';
  }
  if (group == 'movies') return 'movies';
  if (group == 'shows') return 'tv';
  return _guessCategory(flat, service, categoryIds);
}

/// JS `a || b || c`.
Object? _or(Object? a, [Object? b, Object? c, Object? d]) {
  for (final v in [a, b, c, d]) {
    if (jsTruthy(v)) return v;
  }
  return d ?? c ?? b ?? a;
}

// ---- rich metadata (v176) ---------------------------------------------------------------

String _key(Object? v) => _jsString(v).toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

List<Map<String, dynamic>> _richSources(Map<String, dynamic> raw) {
  final out = <Map<String, dynamic>>[];
  void add(Object? x) {
    final m = x is Map ? asMap(x) : null;
    if (m != null && !out.any((o) => identical(o, m))) out.add(m);
  }

  for (final o in _nested(raw)) {
    add(o);
  }
  for (final k in const ['metadata', 'attributes', 'details', 'info', 'information', 'aired', 'broadcast', 'release', 'production', 'user_data', 'userData']) {
    add(raw[k]);
    for (final parent in out.take(12).toList()) {
      add(parent[k]);
    }
  }
  return out;
}

Object? _findValue(Map<String, dynamic> raw, List<String> names) {
  final wanted = names.map(_key).toSet();
  for (final obj in _richSources(raw)) {
    for (final e in obj.entries) {
      final v = e.value;
      if (wanted.contains(_key(e.key)) && v != null && !(v is String && v.trim().isEmpty)) return v;
    }
  }
  return null;
}

List<String> _list(Object? value) {
  if (value == null) return [];
  List<String> uniq(Iterable<String> xs) {
    final out = <String>[];
    for (final x in xs) {
      if (x.isNotEmpty && !out.contains(x)) out.add(x);
    }
    return out.length > 40 ? out.sublist(0, 40) : out;
  }

  if (value is String) {
    final s = value.trim();
    if (s.isEmpty) return [];
    if ((s.startsWith('[') && s.endsWith(']')) || (s.startsWith('{') && s.endsWith('}'))) {
      try {
        return _list(jsonDecode(s));
      } catch (_) {}
    }
    return uniq(s.split(RegExp(r'\s*(?:,|;|\||/)\s*')).map((x) => safeText(x, 120)));
  }
  if (value is List) {
    final rows = <String>[];
    for (final e in value) {
      if (e is String || e is num) {
        rows.add(safeText(_jsString(e), 120));
      } else if (e is Map) {
        final name = e['name'] ?? e['title'] ?? e['label'] ?? e['value'] ?? e['text'];
        if (name != null) rows.add(safeText(_jsString(name), 120));
      }
    }
    return uniq(rows);
  }
  if (value is Map) {
    final direct = value['name'] ?? value['title'] ?? value['label'] ?? value['value'] ?? value['text'];
    if (direct != null) return _list(direct);
    for (final k in const ['data', 'items', 'results', 'nodes', 'edges']) {
      if (value[k] != null) return _list(value[k]);
    }
  }
  return [];
}

int? _duration(Object? value) {
  if (value == null || value == '') return null;
  if (value is num) return value.isFinite && value > 0 ? jsRound(value.toDouble()).toInt() : null;
  final s = _jsString(value).toLowerCase().trim();
  if (s.isEmpty) return null;
  final hr = double.tryParse(RegExp(r'(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)').firstMatch(s)?[1] ?? '') ?? 0;
  final min = double.tryParse(RegExp(r'(\d+(?:\.\d+)?)\s*(?:m|min|mins|minute|minutes)').firstMatch(s)?[1] ?? '') ?? 0;
  if (hr != 0 || min != 0) return math.max(1, jsRound(hr * 60 + min).toInt());
  final n = double.tryParse(RegExp(r'\d+(?:\.\d+)?').firstMatch(s)?[0] ?? '');
  return n != null && n > 0 ? jsRound(n).toInt() : null;
}

double? _communityScore(Object? value) {
  final n = _number(value);
  if (!(n > 0)) return null;
  return jsRound((n > 10 ? n / 10 : n) * 100) / 100;
}

/// `v176ExtractRichMetadata`.
Map<String, dynamic> _richMetadata(Map<String, dynamic> raw, String service) {
  String text(List<String> names, int max) {
    final v = _findValue(raw, names);
    return v == null ? '' : safeText(_jsString(v), max);
  }
  final format = text(const ['media_format', 'mediaFormat', 'format', 'series_type', 'anime_type', 'manga_type', 'title_type', 'show_type', 'movie_type', 'content_type', 'kind'], 80);
  final synopsis = text(const ['synopsis', 'description', 'overview', 'summary', 'plot', 'storyline', 'about'], 6000);
  final genres = _list(_findValue(raw, const ['genres', 'genre', 'genre_names', 'genreNames']));
  final themes = _list(_findValue(raw, const ['themes', 'theme', 'theme_names', 'themeNames']));
  final studios = _list(_findValue(raw, const ['studios', 'studio', 'studio_names', 'studioNames', 'production_companies', 'productionCompanies', 'networks', 'network']));
  final producers = _list(_findValue(raw, const ['producers', 'producer', 'production', 'production_names', 'productionNames']));
  var mediaSource = text(const ['source_material', 'sourceMaterial', 'source_type', 'sourceType', 'original_source', 'originalSource', 'media_source', 'mediaSource'], 120);
  if (mediaSource.isEmpty) {
    final generic = text(const ['source'], 120);
    if (generic.isNotEmpty && _key(generic) != _key(service) && _key(generic) != _key(serviceName(service)) && !RegExp(r'^mediaflow$', caseSensitive: false).hasMatch(generic)) {
      mediaSource = generic;
    }
  }
  final demographic = _list(_findValue(raw, const ['demographics', 'demographic', 'target_demographic', 'targetDemographic', 'audience'])).join(', ');
  final durationMinutes = _duration(_findValue(raw, const ['duration_minutes', 'durationMinutes', 'runtime_minutes', 'runtimeMinutes', 'runtime', 'episode_duration', 'episodeDuration', 'duration']));
  final ageRating = text(const ['content_rating', 'contentRating', 'age_rating', 'ageRating', 'certification', 'mpaa_rating', 'mpaaRating', 'rating_classification'], 80);
  final releaseDate = dateValue(_findValue(raw, const ['release_date', 'releaseDate', 'released_at', 'releasedAt', 'premiered', 'first_air_date', 'firstAirDate', 'air_date', 'airDate']));
  var seasonLabel = text(const ['season_name', 'seasonName', 'season_label', 'seasonLabel', 'season'], 80);
  final seasonYear = text(const ['season_year', 'seasonYear'], 10);
  if (seasonLabel.isNotEmpty && seasonYear.isNotEmpty && !seasonLabel.contains(seasonYear)) seasonLabel = '$seasonLabel $seasonYear';
  final communityScore = _communityScore(_findValue(raw, const ['community_score', 'communityScore', 'average_score', 'averageScore', 'mean_score', 'meanScore', 'score_average', 'scoreAverage', 'imdb_rating', 'imdbRating', 'tmdb_rating', 'tmdbRating']));
  return {
    'mediaFormat': format, 'synopsis': synopsis, 'genres': genres, 'themes': themes, 'studios': studios, 'producers': producers,
    'mediaSource': mediaSource, 'demographic': demographic, 'durationMinutes': durationMinutes, 'ageRating': ageRating,
    'releaseDate': releaseDate, 'seasonLabel': seasonLabel, 'communityScore': communityScore,
  };
}

bool _hasRich(Map<String, dynamic> meta) => meta.values.any((v) => v is List ? v.isNotEmpty : (v != null && v != ''));

// ---- seasons (v252) ---------------------------------------------------------------------

int _n(Object? v, [int fallback = 0]) {
  final n = jsNumOrNull(v is Map || v is List ? double.nan : v);
  return n == null ? fallback : math.max(0, jsRound(n).toInt());
}

int? _seasonNumber(Object? v) {
  if (v == null || _jsString(v).trim().isEmpty) return null;
  final n = jsNumOrNull(v);
  return n == null ? null : math.max(0, jsRound(n).toInt());
}

String _seasonLabel(Map<String, dynamic> s, int index) {
  final name = cleanTitle(_jsString(_or(s['name'], s['title'], '')).trim());
  if (name.isNotEmpty) return name;
  final n = _seasonNumber(s['number']);
  if (n == 0) return 'Specials';
  if (n != null) return 'Season $n';
  return 'Season ${index + 1}';
}

Map<String, dynamic> _normalizeSeason(Object? raw, int index, String source, String Function() seasonId) {
  final row = asMap(raw) ?? const <String, dynamic>{};
  final number = _seasonNumber(row['number'] ?? row['season'] ?? row['season_number'] ?? row['seasonNumber']);
  final explicit = row['total'] ?? row['totalEpisodes'] ?? row['total_episodes'] ?? row['total_episodes_count'] ?? row['episodes_count'] ?? row['episode_count'];
  final total = explicit == null || _jsString(explicit).trim().isEmpty ? null : _n(explicit);
  var progress = _n(row['progress'] ?? row['watchedEpisodes'] ?? row['watched_episodes'] ?? row['watched_episodes_count'] ?? row['episodes_watched']);
  if (total != null && total > 0) progress = math.min(progress, total);
  final src = jsTruthy(row['source']) ? _jsString(row['source']) : (source.isEmpty ? 'manual' : source);
  return {
    'id': _jsString(_or(row['id'], row['seasonId'], row['season_id'])).isNotEmpty ? _jsString(_or(row['id'], row['seasonId'], row['season_id'])) : seasonId(),
    'number': number,
    'name': _seasonLabel({...row, 'number': number}, index),
    'progress': progress,
    'total': total != null && total > 0 ? total : (total == 0 ? 0 : null),
    'source': src,
    'manual': row['manual'] == true || src == 'manual',
    'synthetic': row['synthetic'] == true,
  };
}

List<Map<String, dynamic>> _sortSeasons(List<Map<String, dynamic>> rows) {
  final idx = [for (var i = 0; i < rows.length; i++) i];
  idx.sort((a, b) {
    final an = rows[a]['number'] as int?, bn = rows[b]['number'] as int?;
    if (an == null && bn == null) return a - b;
    if (an == null) return 1;
    if (bn == null) return -1;
    final d = an - bn;
    return d != 0 ? d : a - b;
  });
  return [for (final i in idx) rows[i]];
}

List<Map<String, dynamic>> _normalizeSeasons(Object? raw, String source, String Function() seasonId) {
  final out = <Map<String, dynamic>>[];
  final list = asList(raw);
  for (var i = 0; i < list.length; i++) {
    out.add(_normalizeSeason(list[i], i, source, seasonId));
  }
  return _sortSeasons(out);
}

({int progress, int? total}) _aggregate(List<Map<String, dynamic>> rows, String Function() seasonId) {
  var progress = 0, total = 0;
  for (final s in _normalizeSeasons(rows, 'manual', seasonId)) {
    progress += _n(s['progress']);
    total += s['total'] == null ? 0 : _n(s['total']);
  }
  return (progress: progress, total: total > 0 ? total : null);
}

List<Map<String, dynamic>> _reconcile(List<Map<String, dynamic>> seasons, Object? progress, Object? total, String source, String Function() seasonId, int now) {
  final rows = _normalizeSeasons(seasons, source, seasonId);
  final a = _aggregate(rows, seasonId);
  final wantedProgress = _n(progress);
  final wantedTotal = total == null || _jsString(total).trim().isEmpty ? null : _n(total);
  final missingProgress = math.max(0, wantedProgress - a.progress);
  final missingTotal = wantedTotal == null ? 0 : math.max(0, wantedTotal - (a.total ?? 0));
  if (missingProgress > 0 || missingTotal > 0) {
    final t = math.max(missingTotal, missingProgress);
    rows.add(_normalizeSeason({
      'id': 'v252-unassigned-$now-${seasonId().replaceAll(RegExp('[^a-z0-9]'), '').padRight(5, '0').substring(0, 5)}',
      'number': null, 'name': 'Unassigned', 'progress': missingProgress, 'total': t == 0 ? null : t,
      'source': source, 'synthetic': true, 'manual': false,
    }, rows.length, source, seasonId));
  }
  return _sortSeasons(rows);
}

int? _firstNumber(Map<String, dynamic> obj, List<String> keys) {
  for (final k in keys) {
    final v = obj[k];
    if (v != null && _jsString(v).trim().isNotEmpty) {
      final n = jsNumOrNull(v is Map || v is List ? double.nan : v);
      if (n != null) return math.max(0, jsRound(n).toInt());
    }
  }
  return null;
}

Map<String, dynamic> _seasonFromImport(Object? raw, int index, String service, String Function() seasonId) {
  final row = asMap(raw) ?? const <String, dynamic>{};
  final episodes = row['episodes'] is List ? row['episodes'] as List : const [];
  var total = _firstNumber(row, const ['total', 'total_episodes', 'totalEpisodes', 'total_episodes_count', 'episodes_count', 'episode_count']);
  if (total == null && row['episodes'] is num) total = _n(row['episodes']);
  var progress = _firstNumber(row, const ['progress', 'watched', 'watched_episodes', 'watchedEpisodes', 'watched_episodes_count', 'episodes_watched']);
  if (progress == null && episodes.isNotEmpty) {
    progress = episodes.where((ep) {
      final e = asMap(ep);
      return e != null &&
          (e['watched'] == true || e['completed'] == true || e['seen'] == true || jsTruthy(e['watched_at']) || jsTruthy(e['watchedAt']) ||
              RegExp('watched|completed|seen', caseSensitive: false).hasMatch(_jsString(e['status'])));
    }).length;
  }
  progress ??= 0;
  if (total == null &&
      episodes.isNotEmpty &&
      episodes.any((ep) {
        final e = asMap(ep);
        return e != null &&
            (e['watched'] == false || e['completed'] == false || e['seen'] == false || RegExp('unwatched|planned|aired', caseSensitive: false).hasMatch(_jsString(e['status'])));
      })) {
    total = [episodes.length, for (final ep in episodes) _n(asMap(ep)?['episode'] ?? asMap(ep)?['number'] ?? asMap(ep)?['episode_number'])].reduce(math.max);
  }
  final number = row['season'] ?? row['number'] ?? row['season_number'] ?? row['seasonNumber'] ?? index + 1;
  return _normalizeSeason({
    'id': _or(row['id'], row['season_id'], row['seasonId']),
    'number': number,
    'name': _or(row['name'], row['title']),
    'progress': progress,
    'total': total,
    'source': 'import:$service',
    'manual': false,
  }, index, 'import:$service', seasonId);
}

List<Map<String, dynamic>> _importedSeasons(Map<String, dynamic> raw, String service, String Function() seasonId) {
  List? list;
  for (final o in [raw, raw['show'], raw['movie'], raw['media'], raw['anime'], raw['item']]) {
    final m = o is Map ? asMap(o) : null;
    if (m != null && m['seasons'] is List && (m['seasons'] as List).isNotEmpty) {
      list = m['seasons'] as List;
      break;
    }
  }
  if (list == null) return [];
  final rows = <Map<String, dynamic>>[];
  for (var i = 0; i < list.length; i++) {
    final s = _seasonFromImport(list[i], i, service, seasonId);
    if (_n(s['progress']) > 0 || _number(s['total']) > 0 || jsTruthy(s['name'])) rows.add(s);
  }
  return _sortSeasons(rows);
}

List<Map<String, dynamic>> _mergeSeasons(Object? existing, List<Map<String, dynamic>> incoming, String service, Object? progress, Object? total,
    String Function() seasonId, int now) {
  final out = _normalizeSeasons(existing, 'manual', seasonId);
  String key(Map<String, dynamic> s) => s['number'] != null ? 'n:${s['number']}' : 'name:${_jsString(s['name']).toLowerCase()}';
  final byKey = <String, int>{};
  for (var i = 0; i < out.length; i++) {
    byKey[key(out[i])] = i;
  }
  for (final inc in _normalizeSeasons(incoming, 'import:$service', seasonId)) {
    final k = key(inc);
    final idx = byKey[k];
    if (idx == null) {
      byKey[k] = out.length;
      out.add(inc);
      continue;
    }
    final local = out[idx];
    if (local['manual'] == true || local['source'] == 'manual') continue;
    out[idx] = {...local, ...inc, 'id': jsTruthy(local['id']) ? local['id'] : inc['id'], 'source': 'import:$service', 'manual': false};
  }
  return _reconcile(out, progress, total, 'import:$service', seasonId, now);
}

void _syncFromSeasons(Map<String, dynamic> item, String Function() seasonId) {
  final seasons = _normalizeSeasons(item['seasons'], jsTruthy(item['seasonSource']) ? _jsString(item['seasonSource']) : 'manual', seasonId);
  item['seasons'] = seasons;
  if (seasons.isEmpty) return;
  final a = _aggregate(seasons, seasonId);
  item['progress'] = a.progress;
  item['total'] = a.total;
  item['seasonViewEnabled'] = item['seasonViewEnabled'] != false;
  item['seasonsModifiedAt'] = jsOut(math.max(jsNum(item['seasonsModifiedAt']), jsNum(item['modifiedAt'])));
}

// ---- records ----------------------------------------------------------------------------

/// `v158NormalizeRecord` (+ v176 rich metadata + v252 seasons).
Map<String, dynamic>? normalizeImportRecord(Object? rawValue, String service, Set<String> categoryIds,
    {required String Function() seasonId, required int now}) {
  final raw = rawValue is Map ? asMap(rawValue) : null;
  if (raw == null) return null;
  final objs = _nested(raw);
  Object? firstTruthy(List<String> keys) {
    for (final k in keys) {
      if (jsTruthy(raw[k])) return raw[k];
    }
    return null;
  }

  final nested = asMap(firstTruthy(const ['show', 'movie', 'media', 'anime', 'manga', 'item', 'node', 'entry', 'book'])) ?? const <String, dynamic>{};
  final list = asMap(firstTruthy(const ['list_status', 'listStatus'])) ?? const <String, dynamic>{};
  final o = <String, dynamic>{...nested, ...list, ...raw};
  final title = cleanTitle(_jsString(_first(o, const ['title', 'name', 'series_title', 'manga_title', 'anime_title', 'movie_title', 'original_title', 'primary_title', 'canonical_title'])));
  if (title.isEmpty) return null;
  final progress = _number(_first(o, const ['progress', 'watched_episodes', 'watched_episodes_count', 'episodes_watched', 'episode', 'my_watched_episodes', 'chapters_read', 'my_read_chapters', 'num_episodes_watched', 'num_chapters_read', 'watched']));
  var totalN = _number(_first(o, const ['total', 'total_episodes', 'total_episodes_count', 'episodes_total', 'series_episodes', 'chapters_total', 'series_chapters', 'manga_chapters', 'num_episodes', 'num_chapters']));
  double? total = totalN == 0 ? null : totalN;
  final categoryId = _inferCategory(raw, service, categoryIds);
  if (categoryId == 'movies' || categoryId == 'animemovies') total = total ?? 1;
  final status = normStatus(_first(o, const ['status', 'list_status', 'my_status', 'state']));
  final ratingN = _number(_first(o, const ['rating', 'user_rating', 'your_rating', 'score', 'my_score']));
  final yearN = _number(_first(o, const ['year', 'release_year', 'title_year', 'start_year']));

  var startedAt = 0, completedAt = 0, sourceTimestamp = 0;
  const startKeys = ['start_date', 'started_at', 'startedAt', 'startdate', 'date_started', 'started', 'my_start_date', 'first_watched_at', 'first_read_at', 'watching_started_at'];
  const finishKeys = ['finish_date', 'finished_at', 'finishedAt', 'completed_at', 'completedAt', 'finishdate', 'date_completed', 'my_finish_date', 'last_watched_at', 'last_read_at', 'ended_at'];
  const timestampKeys = ['timestamp', 'created_at', 'createdAt', 'added_at', 'addedAt', 'date_added', 'added_to_watchlist_at', 'listed_at', 'list_added_at', 'my_last_updated', 'updated_at', 'updatedAt'];
  for (final obj in objs) {
    if (startedAt == 0) startedAt = _firstDate(obj, startKeys);
    if (completedAt == 0) completedAt = _firstDate(obj, finishKeys);
    if (sourceTimestamp == 0) sourceTimestamp = _firstDate(obj, timestampKeys);
  }
  if (service == 'simkl') {
    var first = 0, last = 0;
    for (final season in asList(raw['seasons'])) {
      for (final ep in asList(asMap(season)?['episodes'])) {
        final e = asMap(ep);
        final ts = parseDateLike(e?['watched_at'] ?? e?['watchedAt'] ?? e?['date']);
        if (ts == 0) continue;
        if (first == 0 || ts < first) first = ts;
        if (ts > last) last = ts;
      }
    }
    if (startedAt == 0) startedAt = first;
    if (completedAt == 0 && status == 'completed') completedAt = last;
  }
  if (status != 'completed') completedAt = 0;

  final record = <String, dynamic>{
    'title': title,
    'categoryId': categoryId,
    'progress': jsOut(math.max(0, progress)),
    'total': total == null ? null : jsOut(total),
    'status': status,
    'rating': ratingN == 0 ? null : jsOut(ratingN),
    'year': yearN == 0 ? null : jsOut(yearN),
    'externalIds': _externalIds(raw),
    'startedAt': startedAt == 0 ? null : startedAt,
    'completedAt': completedAt == 0 ? null : completedAt,
    'sourceTimestamp': sourceTimestamp == 0 ? null : sourceTimestamp,
    'coverUrl': _coverUrl(raw).isEmpty ? null : _coverUrl(raw),
  };
  final rich = _richMetadata(raw, service);
  if (_hasRich(rich)) record['richMetadata'] = rich;
  final seasons = _importedSeasons(raw, service, seasonId);
  if (seasons.isNotEmpty) record['seasons'] = _reconcile(seasons, record['progress'], record['total'], 'import:$service', seasonId, now);
  return record;
}

// ---- merge into the Library -------------------------------------------------------------

String titleKey(Object? value) => cleanTitle(_jsString(value))
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp("[’'`´]"), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

class _Index {
  final byExternal = <String, Map<String, dynamic>>{};
  final byTitle = <String, List<Map<String, dynamic>>>{};

  void add(Map<String, dynamic> item) {
    if (!jsTruthy(item['id'])) return;
    (asMap(item['externalIds']) ?? const {}).forEach((k, v) {
      if (v == null || _jsString(v).trim().isEmpty) return;
      byExternal.putIfAbsent('$k:${_jsString(v).trim().toLowerCase()}', () => item);
    });
    final tk = titleKey(item['title']);
    if (tk.isNotEmpty) {
      final arr = byTitle.putIfAbsent(tk, () => []);
      if (!arr.any((x) => identical(x, item))) arr.add(item);
    }
  }

  /// `v158FindImportItem`.
  Map<String, dynamic>? find(Map<String, dynamic> record) {
    for (final e in (asMap(record['externalIds']) ?? const {}).entries) {
      if (e.value == null || _jsString(e.value).trim().isEmpty) continue;
      final x = byExternal['${e.key}:${_jsString(e.value).trim().toLowerCase()}'];
      if (x != null) return x;
    }
    final candidates = byTitle[titleKey(record['title'])] ?? const [];
    final year = jsNum(record['year']);
    if (year != 0) {
      final sameYear = candidates.where((i) => !jsTruthy(i['year']) || jsNum(i['year']) == year).toList();
      if (sameYear.length == 1) return sameYear.first;
      final exact = sameYear.where((i) => jsNum(i['year']) == year).firstOrNull;
      if (exact != null) return exact;
    }
    final sameCategory = candidates.where((i) => jsStr(i['categoryId']) == jsStr(record['categoryId'])).toList();
    if (sameCategory.length == 1) return sameCategory.first;
    if (candidates.length == 1) return candidates.first;
    return null;
  }
}

/// What an import did.
class ImportResult {
  int added = 0, updated = 0, skipped = 0, covers = 0, startDates = 0, finishDates = 0, timestamps = 0, historyAdded = 0;
  String? error;

  String get summary => '$added added · $updated updated'
      '${historyAdded > 0 ? ' · $historyAdded History groups' : ''}'
      ' · $startDates start dates · $finishDates finish dates · $covers cover URLs'
      '${skipped > 0 ? ' · $skipped skipped' : ''}';
}

String _startSource(String service) => service == 'mal' || service == 'malxml' ? 'mal' : 'import:$service';

/// `v158MergeExchangeRecords` with every website wrapper, applied to [state].
///
/// [intoCategory] is the website's Advanced Import "one category" mode
/// (v169): every record goes to that category, matched titles move there too.
ImportResult mergeImportRecords(Map<String, dynamic> state, List<dynamic> records, String service,
    {required int now, required String Function() uid, Map<String, Map<String, dynamic>>? touchedOut, String? intoCategory}) {
  final result = ImportResult();
  final library = state['library'] is List ? (state['library'] as List) : (state['library'] = <dynamic>[]) as List;
  final categories = [for (final c in asList(state['categories'])) asMap(c)].whereType<Map<String, dynamic>>().toList();
  final categoryIds = {for (final c in categories) jsStr(c['id'])};
  final index = _Index();
  for (var i = 0; i < library.length; i++) {
    final m = asMap(library[i]);
    if (m == null) continue;
    if (library[i] is! Map<String, dynamic>) library[i] = m;
    index.add(m);
  }
  final touched = touchedOut ?? <String, Map<String, dynamic>>{};
  String seasonId() => 'season-${uid()}';

  for (final raw in records) {
    final r = normalizeImportRecord(raw, service, categoryIds, seasonId: seasonId, now: now);
    if (r == null) {
      result.skipped++;
      continue;
    }
    Map<String, dynamic>? existing;
    if (intoCategory != null) {
      r['categoryId'] = intoCategory;
      existing = index.find(r);
    }
    final outcome = _apply(r, service, index, touched, library, categories, now, uid, seasonId);
    if (intoCategory != null) {
      final item = existing ?? index.find(r);
      if (item != null) {
        item['categoryId'] = intoCategory;
        item['modifiedAt'] = now;
        touched[jsStr(item['id'])] = item;
        index.add(item);
      }
    }
    if (outcome == 'added') {
      result.added++;
    } else if (outcome == 'updated') {
      result.updated++;
    } else {
      result.skipped++;
    }
    if (r['coverUrl'] != null) result.covers++;
    if (r['startedAt'] != null) result.startDates++;
    if (r['completedAt'] != null) result.finishDates++;
    if (r['sourceTimestamp'] != null) result.timestamps++;
  }

  // v158SyncCompletionTimeline.
  if (touched.isNotEmpty) {
    final timeline = [for (final x in asList(state['completionTimeline'])) if (!touched.containsKey(jsStr(asMap(x)?['libraryId']))) x];
    for (final item in touched.values) {
      if (item['status'] == 'completed' && jsNum(item['completedAt']) > 0) {
        timeline.add({'libraryId': item['id'], 'title': cleanTitle(item['title']), 'categoryId': item['categoryId'], 'completedAt': jsOut(jsNum(item['completedAt']))});
      }
    }
    state['completionTimeline'] = timeline;
  }
  return result;
}

String _apply(Map<String, dynamic> record0, String service, _Index index, Map<String, Map<String, dynamic>> touched, List library,
    List<Map<String, dynamic>> categories, int now, String Function() uid, String Function() seasonId) {
  // v378: only valid IDs, never replacing a different saved ID or a manual one.
  final normalized = <String, dynamic>{};
  (asMap(record0['externalIds']) ?? const {}).forEach((k, v) {
    if (!kImportIdAliases.containsKey(k)) return;
    final value = normalizeImportId(k, v);
    if (value.isNotEmpty) normalized[k] = value;
  });
  final target0 = index.find(record0);
  final existing = asMap(target0?['externalIds']) ?? const <String, dynamic>{};
  for (final k in normalized.keys.toList()) {
    final previous = normalizeImportId(k, existing[k]);
    if (previous.isNotEmpty && previous != normalized[k]) {
      normalized.remove(k);
      continue;
    }
    final manual = asMap(target0?['v377ManualExternalIds']);
    if (manual != null && manual.containsKey(k)) normalized.remove(k);
  }
  final record = {...record0, 'externalIds': normalized};

  // v377: the target's manual ID overrides are re-applied afterwards.
  final target = index.find(record);
  final overrides = asMap(target?['v377ManualExternalIds']);
  // v178: a manually edited year is kept.
  final protectYear = asMap(target?['richMetadataManual'])?['year'] == true;
  final yearBefore = target?['year'];

  final out = _applyBase(record, service, index, touched, library, categories, now, uid);

  // v176 rich metadata (with the 095 manual protection).
  if (out != 'skipped' && record['richMetadata'] != null) {
    final item = index.find(record);
    if (item != null && _applyRich(item, asMap(record['richMetadata'])!)) {
      item['modifiedAt'] = now;
      touched[jsStr(item['id'])] = item;
      index.add(item);
    }
  }
  if (protectYear) {
    final item = index.find(record);
    if (item != null) {
      item['year'] = yearBefore;
      touched[jsStr(item['id'])] = item;
      index.add(item);
    }
  }
  // v252 seasons.
  final seasons = asList(record['seasons']).map(asMap).whereType<Map<String, dynamic>>().toList();
  if (seasons.isNotEmpty) {
    final item = index.find(record);
    if (item != null) {
      item['seasons'] = _mergeSeasons(item['seasons'], seasons, service, record['progress'], record['total'], seasonId, now);
      item['seasonSource'] = 'import:$service';
      item['seasonViewEnabled'] = true;
      item['seasonsModifiedAt'] = now;
      _syncFromSeasons(item, seasonId);
      item['modifiedAt'] = now;
      touched[jsStr(item['id'])] = item;
    }
  }
  if (target != null && overrides != null) {
    final ids = Map<String, dynamic>.of(asMap(target['externalIds']) ?? const {});
    overrides.forEach((k, v) {
      if (v == null || v == '') {
        ids.remove(k);
      } else {
        ids[k] = v;
      }
    });
    target['externalIds'] = ids;
  }
  return out;
}

/// `v158ApplyNormalizedRecord`.
String _applyBase(Map<String, dynamic> record, String service, _Index index, Map<String, Map<String, dynamic>> touched, List library,
    List<Map<String, dynamic>> categories, int now, String Function() uid) {
  var item = index.find(record);
  final svc = service.isEmpty ? 'import' : service;
  if (item != null) {
    item['progress'] = jsOut(math.max(jsNum(item['progress']), jsNum(record['progress'])));
    if (record['total'] != null && jsNum(record['total']) > 0) item['total'] = jsOut(jsNum(record['total']));
    item['status'] = jsTruthy(record['status']) ? record['status'] : (jsTruthy(item['status']) ? item['status'] : 'planned');
    item['rating'] = record['rating'] ?? item['rating'];
    item['year'] = jsTruthy(record['year']) ? record['year'] : (jsTruthy(item['year']) ? item['year'] : null);
    item['externalIds'] = {...?asMap(item['externalIds']), ...?asMap(record['externalIds'])};
    item['source'] = svc;
    final tags = <dynamic>[];
    for (final t in [...asList(item['tags']), serviceName(service)]) {
      if (!tags.contains(t)) tags.add(t);
    }
    item['tags'] = tags;
    if (record['startedAt'] != null) {
      item['startedAt'] = record['startedAt'];
      item['startedAtSource'] = _startSource(svc);
    }
    if (item['status'] == 'completed' && record['completedAt'] != null) item['completedAt'] = record['completedAt'];
    if (record['sourceTimestamp'] != null) {
      final ts = jsNum(record['sourceTimestamp']);
      item['sourceTimestamp'] = jsOut(ts);
      item['sourceTimestampSource'] = svc;
      final created = jsNum(item['createdAt']);
      item['createdAt'] = jsOut(math.min(created == 0 ? ts : created, ts));
    }
    if (jsStr(item['coverUrl']).trim().isEmpty && record['coverUrl'] != null) {
      item['coverUrl'] = jsStr(record['coverUrl']);
      item['coverSource'] = 'import:${service.isEmpty ? 'external' : service}';
    }
    item['modifiedAt'] = now;
    touched[jsStr(item['id'])] = item;
    index.add(item);
    return 'updated';
  }
  final createdAt = jsNum(record['sourceTimestamp']) == 0 ? now : jsNum(record['sourceTimestamp']).toInt();
  final catId = categories.any((c) => jsStr(c['id']) == jsStr(record['categoryId']))
      ? jsStr(record['categoryId'])
      : jsStr((categories.where((c) => c['enabled'] != false).firstOrNull ?? categories.firstOrNull)?['id'] ?? 'tv');
  item = <String, dynamic>{
    'id': uid(),
    'title': record['title'],
    'categoryId': catId.isEmpty ? 'tv' : catId,
    'progress': jsOut(math.max(0, jsNum(record['progress']))),
    'total': record['total'] == null ? null : jsOut(jsNum(record['total'])),
    'status': jsTruthy(record['status']) ? record['status'] : 'planned',
    'priority': 'medium',
    'estimatedMinutes': null,
    'tags': [serviceName(service)],
    'source': svc,
    'year': jsTruthy(record['year']) ? record['year'] : null,
    'rating': record['rating'],
    'externalIds': {...?asMap(record['externalIds'])},
    'startedAt': record['startedAt'],
    'startedAtSource': record['startedAt'] != null ? _startSource(svc) : null,
    'completedAt': record['status'] == 'completed' ? record['completedAt'] : null,
    'createdAt': createdAt,
    'modifiedAt': now,
    'sourceTimestamp': record['sourceTimestamp'],
    'sourceTimestampSource': record['sourceTimestamp'] != null ? svc : null,
    'coverUrl': record['coverUrl'],
    'coverSource': record['coverUrl'] != null ? 'import:${service.isEmpty ? 'external' : service}' : null,
  };
  library.add(item);
  touched[jsStr(item['id'])] = item;
  index.add(item);
  return 'added';
}

List<String> _mergeList(Object? a, Object? b) {
  final out = <String>[];
  for (final x in [...asList(a), ...asList(b)]) {
    final v = safeText(_jsString(x), 120);
    if (v.isNotEmpty && !out.contains(v)) out.add(v);
  }
  return out.length > 40 ? out.sublist(0, 40) : out;
}

/// `v176ApplyRichMetadata` as replaced by 095 (manual fields are kept).
bool _applyRich(Map<String, dynamic> item, Map<String, dynamic> meta) {
  final manual = richManualMap(item);
  var changed = false;
  for (final k in const ['genres', 'themes', 'studios', 'producers']) {
    if (manual[k] == true) continue;
    final merged = _mergeList(item[k], meta[k]);
    if (jsonEncode(merged) != jsonEncode(item[k] is List ? item[k] : const [])) {
      item[k] = merged;
      changed = true;
    }
  }
  for (final k in const ['mediaFormat', 'synopsis', 'mediaSource', 'demographic', 'ageRating', 'releaseDate', 'seasonLabel']) {
    if (manual[k] == true) continue;
    final value = safeText(_jsString(meta[k]), k == 'synopsis' ? 6000 : 160);
    if (value.isNotEmpty && value != jsStr(item[k])) {
      item[k] = value;
      changed = true;
    }
  }
  for (final k in const ['durationMinutes', 'communityScore']) {
    if (manual[k] == true) continue;
    final v = jsNumOrNull(meta[k]);
    if (meta[k] != null && v != null && v > 0 && jsNumOrNull(item[k]) != v) {
      item[k] = jsOut(v);
      changed = true;
    }
  }
  return changed;
}

// ---- Simkl watched History (App.importSimklJson) ----------------------------------------

/// Whether [data] is a Simkl backup.
bool isSimklBackup(Object? data) {
  final m = asMap(data);
  return m != null && (m['anime'] is List || m['shows'] is List || m['movies'] is List);
}

/// Adds Simkl's genuine watched_at History (one log per title per day).
int addSimklHistory(Map<String, dynamic> state, Map<String, dynamic> data, {required String Function() uid}) {
  final sessions = state['sessions'] is List ? state['sessions'] as List : (state['sessions'] = <dynamic>[]) as List;
  final seen = {for (final s in sessions) if (jsTruthy(asMap(s)?['importKey'])) jsStr(asMap(s)!['importKey'])};
  final categories = [for (final c in asList(state['categories'])) asMap(c)].whereType<Map<String, dynamic>>().toList();
  final categoryIds = {for (final c in categories) jsStr(c['id'])};
  final index = _Index();
  for (final x in asList(state['library'])) {
    final m = asMap(x);
    if (m != null) index.add(m);
  }
  var added = 0;
  for (final group in const ['anime', 'shows', 'movies']) {
    for (final src in asList(data[group])) {
      final sourceRec = asMap(src);
      if (sourceRec == null) continue;
      final raw = {'__group': group, ...sourceRec};
      final r = normalizeImportRecord(raw, 'simkl', categoryIds, seasonId: () => '', now: 0);
      final item = r == null ? null : index.find(r);
      if (item == null) continue;
      final media = asMap(sourceRec['show'] ?? sourceRec['movie'] ?? sourceRec['media']) ?? const <String, dynamic>{};
      final title = cleanTitle(item['title']);
      final simklId = jsStr(asMap(item['externalIds'])?['simkl'] ?? asMap(media['ids'])?['simkl']);
      final days = <String, ({int count, int ts})>{};
      for (final season in asList(sourceRec['seasons'])) {
        for (final ep in asList(asMap(season)?['episodes'])) {
          final e = asMap(ep);
          final ts = parseDateLike(e?['watched_at'] ?? e?['watchedAt']);
          if (ts == 0) continue;
          final day = isoDateUtc(ts);
          final old = days[day];
          days[day] = (count: (old?.count ?? 0) + 1, ts: math.max(old?.ts ?? ts, ts));
        }
      }
      for (final e in days.entries) {
        final ik = 'simkl:${simklId.isNotEmpty ? simklId : titleKey(title)}:${e.key}';
        if (seen.contains(ik)) continue;
        final cat = categories.where((c) => jsStr(c['id']) == jsStr(item['categoryId'])).firstOrNull;
        final amount = group == 'movies' ? 1 : e.value.count;
        final perUnit = jsNum(media['runtime']) != 0 ? jsNum(media['runtime']) : jsNum(cat?['minutesPerUnit']);
        sessions.add({
          'id': uid(),
          'timestamp': e.value.ts,
          'date': e.key,
          'categoryId': item['categoryId'],
          'targetAmount': amount,
          'actualAmount': amount,
          'minutes': math.max(0, jsRound(perUnit * amount).toInt()),
          'note': 'Imported from Simkl · $title',
          'status': 'complete',
          'unit': jsTruthy(cat?['unit']) ? cat!['unit'] : 'units',
          'xp': 0,
          'healthStatus': 'healthy',
          'titles': [
            {'title': title, 'libraryId': item['id'], 'qty': amount},
          ],
          'source': 'simkl',
          'importKey': ik,
        });
        seen.add(ik);
        added++;
      }
    }
  }
  return added;
}

// ---- Exchange export (mfExportExchange) -------------------------------------------------

/// `new Date(x).toISOString()` (milliseconds, Z).
String _isoMs(DateTime d) => DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true).toIso8601String();

String _localDay(Object? ms) {
  final n = jsNum(ms);
  if (n <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(n.toInt());
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// `mfExchangeRows` (v158 round-trip fields + v252 seasons).
List<Map<String, dynamic>> exchangeRows(Map<String, dynamic> state) {
  final out = <Map<String, dynamic>>[];
  for (final x in asList(state['library'])) {
    final i = asMap(x) ?? const <String, dynamic>{};
    final ids = asMap(i['externalIds']);
    final ts = jsNum(i['sourceTimestamp']) != 0 ? jsNum(i['sourceTimestamp']) : jsNum(i['createdAt']);
    final seasons = _normalizeSeasons(i['seasons'], jsTruthy(i['seasonSource']) ? _jsString(i['seasonSource']) : 'manual', () => 'season-${out.length}');
    out.add({
      'title': cleanTitle(i['title']),
      'media_type': jsStr(i['categoryId']),
      'status': i['status'],
      'progress': jsOut(jsNum(i['progress'])),
      'total': i['total'] ?? '',
      'rating': i['rating'] ?? '',
      'year': i['year'] ?? '',
      'start_date': jsTruthy(i['startedAt']) ? _localDay(i['startedAt']) : '',
      'finish_date': jsTruthy(i['completedAt']) ? _localDay(i['completedAt']) : '',
      'timestamp': ts != 0 ? DateTime.fromMillisecondsSinceEpoch(ts.toInt(), isUtc: true).toIso8601String() : '',
      'cover_url': _safeHttpUrl(i['coverUrl']),
      'mal_id': ids?['mal'] ?? '',
      'anilist_id': ids?['anilist'] ?? '',
      'imdb_id': ids?['imdb'] ?? '',
      'tmdb_id': ids?['tmdb'] ?? '',
      'trakt_id': ids?['trakt'] ?? '',
      'simkl_id': ids?['simkl'] ?? '',
      'kitsu_id': ids?['kitsu'] ?? '',
      'isbn': ids?['isbn'] ?? '',
      'seasons': seasons,
    });
  }
  return out;
}

/// `v50SimklExport`.
Map<String, dynamic> simklExport(Map<String, dynamic> state, DateTime now) {
  const statuses = {'active': 'watching', 'planned': 'plantowatch', 'completed': 'completed', 'paused': 'hold', 'dropped': 'dropped'};
  String iso(Object? ms) => DateTime.fromMillisecondsSinceEpoch(jsNum(ms).toInt(), isUtc: true).toIso8601String();
  final out = <String, dynamic>{'source': 'MediaFlow', 'exported_at': _isoMs(now), 'anime': [], 'shows': [], 'movies': []};
  for (final x in asList(state['library'])) {
    final i = asMap(x);
    if (i == null) continue;
    final ids = asMap(i['externalIds']) ?? const <String, dynamic>{};
    final media = {
      'title': cleanTitle(i['title']),
      'year': jsTruthy(i['year']) ? i['year'] : null,
      'ids': {'simkl': ids['simkl'], 'mal': ids['mal'], 'anilist': ids['anilist'], 'tmdb': ids['tmdb'], 'imdb': ids['imdb']},
    };
    final rec = {
      'status': statuses[i['status']] ?? 'plantowatch',
      'watched_episodes_count': jsOut(jsNum(i['progress'])),
      'total_episodes_count': i['total'] == null ? null : jsOut(jsNum(i['total'])),
      'user_rating': jsOut(jsNum(i['rating'])),
      'added_to_watchlist_at': jsTruthy(i['createdAt']) ? iso(i['createdAt']) : null,
      'last_watched_at': jsTruthy(i['completedAt']) ? iso(i['completedAt']) : null,
    };
    final cat = jsStr(i['categoryId']);
    if (cat == 'movies') {
      (out['movies'] as List).add({'movie': media, ...rec});
    } else if (cat == 'tv' || cat == 'otheranimation') {
      (out['shows'] as List).add({'show': media, ...rec});
    } else if (const ['seasonal', 'backlog', 'animemovies'].contains(cat)) {
      (out['anime'] as List).add({'show': media, 'anime_type': cat == 'animemovies' ? 'movie' : 'tv', ...rec});
    }
  }
  return out;
}

String _csvEscape(Object? v) {
  final s = v == null ? '' : _jsString(v);
  return RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// `mfExportExchange`: the file name and contents for [service].
({String name, String content}) exchangeExport(Map<String, dynamic> state, String service, DateTime now) {
  final day0 = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  if (service == 'simkl') {
    return (name: 'mediaflow-simkl-$day0.json', content: const JsonEncoder.withIndent('  ').convert(simklExport(state, now)));
  }
  final rows = exchangeRows(state);
  final day = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  if (const ['mal', 'malxml', 'aniwatch', 'hianime', 'livechart'].contains(service)) {
    const sm = {'active': 'Watching', 'completed': 'Completed', 'paused': 'On-Hold', 'dropped': 'Dropped', 'planned': 'Plan to Watch'};
    final body = [
      for (final r in rows.where((r) => const ['seasonal', 'backlog', 'animemovies'].contains(r['media_type'])))
        '<anime><series_animedb_id>${jsTruthy(r['mal_id']) ? r['mal_id'] : 0}</series_animedb_id><series_title><![CDATA[${jsStr(r['title']).replaceAll(']]>', ']]]]><![CDATA[>')}]]></series_title><series_type>${r['media_type'] == 'animemovies' ? 'Movie' : 'TV'}</series_type><series_episodes>${jsTruthy(r['total']) ? r['total'] : 0}</series_episodes><my_watched_episodes>${r['progress']}</my_watched_episodes><my_start_date>${jsTruthy(r['start_date']) ? r['start_date'] : '0000-00-00'}</my_start_date><my_finish_date>${jsTruthy(r['finish_date']) ? r['finish_date'] : '0000-00-00'}</my_finish_date><my_status>${sm[r['status']] ?? 'Plan to Watch'}</my_status><my_score>${jsTruthy(r['rating']) ? r['rating'] : 0}</my_score></anime>',
    ].join('\n');
    return (name: 'mediaflow-$service-$day.xml', content: '<?xml version="1.0" encoding="UTF-8"?>\n<myanimelist>\n$body\n</myanimelist>');
  }
  if (const ['json', 'anilist', 'anisearch', 'kitsu', 'stremio', 'trakt'].contains(service)) {
    return (
      name: 'mediaflow-$service-$day.json',
      content: const JsonEncoder.withIndent('  ')
          .convert({'source': 'MediaFlow', 'target': serviceName(service), 'exportedAt': _isoMs(now), 'items': rows}),
    );
  }
  final h = rows.isNotEmpty ? rows.first.keys.toList() : const ['title', 'media_type', 'status', 'progress', 'total', 'rating', 'year'];
  final csv = [h.join(','), for (final r in rows) h.map((k) => _csvEscape(r[k])).join(',')].join('\r\n');
  return (name: 'mediaflow-$service-$day.csv', content: csv);
}
