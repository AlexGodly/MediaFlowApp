// Imports from other services, checked against the website's own code:
// test/fixtures/import-golden.json comes from
// tool/website_reference/generate_import_goldens.mjs (v158 engine with every
// wrapper, Simkl History, the Exchange rows).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/exchange_import.dart';

Object? _clone(Object? v) => jsonDecode(jsonEncode(v));

/// Generated ids (items, seasons) replaced by their order of appearance, and
/// numbers compared as numbers.
Object? _canon(Object? v, Map<String, String> ids) {
  if (v is Map) return {for (final e in v.entries) e.key: _canon(e.value, ids)};
  if (v is List) return [for (final x in v) _canon(x, ids)];
  if (v is String && RegExp(r'^(id_\d+|season-.*|v252-unassigned-.*)$').hasMatch(v)) {
    return ids.putIfAbsent(v, () => '#${ids.length}');
  }
  if (v is double && v == v.truncateToDouble()) return v.toInt();
  return v;
}

void main() {
  final g = (jsonDecode(File('test/fixtures/import-golden.json').readAsStringSync()) as Map).cast<String, dynamic>();
  final now = g['now'] as int;

  Map<String, dynamic> state() => {
        'categories': _clone(g['categories']),
        'library': _clone(g['library']),
        'completionTimeline': <dynamic>[],
        'sessions': <dynamic>[],
      };

  for (final raw in g['cases'] as List) {
    final c = (raw as Map).cast<String, dynamic>();
    test('import ${c['name']} writes what the website writes', () {
      final s = state();
      var n = 0;
      String uid() => 'id_${++n}';
      final service = c['service'] as String;
      final List<dynamic> records = switch (c['name']) {
        'csv' => csvRecords(c['csv'] as String),
        'json-trakt' => flattenJson(_clone(c['json'])),
        'simkl' => flattenJson(_clone(c['simkl'])),
        _ => _clone(c['records']) as List,
      };
      final r = mergeImportRecords(s, records, service, now: now, uid: uid);
      if (c['name'] == 'simkl') addSimklHistory(s, (_clone(c['simkl']) as Map).cast<String, dynamic>(), uid: uid);
      if (c['result'] != null) {
        final want = (c['result'] as Map).cast<String, dynamic>();
        expect({
          'added': r.added, 'updated': r.updated, 'skipped': r.skipped, 'covers': r.covers,
          'startDates': r.startDates, 'finishDates': r.finishDates, 'timestamps': r.timestamps,
        }, want, reason: 'counts');
      }
      final mine = <String, String>{}, theirs = <String, String>{};
      final libMine = _canon(_clone(s['library']), mine) as List, libTheirs = _canon(c['library'], theirs) as List;
      expect(libMine.length, libTheirs.length);
      for (var i = 0; i < libTheirs.length; i++) {
        expect(libMine[i], libTheirs[i], reason: '${c['name']} library[$i] ${(libTheirs[i] as Map)['title']}');
      }
      expect(_canon(_clone(s['completionTimeline']), mine), _canon(c['completionTimeline'], theirs), reason: 'timeline');
      if (c['sessions'] != null) {
        expect(_canon(_clone(s['sessions']), mine), _canon(c['sessions'], theirs), reason: 'Simkl History');
      }
    });
  }

  test('Exchange rows match the website', () {
    final rows = exchangeRows(state());
    expect(_canon(_clone(rows), {}), _canon(g['exchangeRows'], {}));
  });

  test('MAL XML is read like the browser reads it', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8" ?>
<myanimelist>
  <myinfo><user_name>me</user_name></myinfo>
  <anime>
    <series_animedb_id>52991</series_animedb_id>
    <series_title><![CDATA[Sousou no Frieren & Co]]></series_title>
    <series_type>TV</series_type>
    <my_start_date>2023-09-29</my_start_date>
    <my_tags></my_tags>
    <my_comments/>
  </anime>
  <manga><manga_title>Berserk &amp; More</manga_title><my_read_chapters>364</my_read_chapters></manga>
</myanimelist>''';
    final rows = xmlRecords(xml);
    expect(rows, [
      {'series_animedb_id': '52991', 'series_title': 'Sousou no Frieren & Co', 'series_type': 'TV', 'my_start_date': '2023-09-29', 'my_tags': '', 'my_comments': ''},
      {'manga_title': 'Berserk & More', 'my_read_chapters': '364'},
    ]);
  });

  test('IDs are normalized like v378', () {
    expect(normalizeImportId('mal', 'https://myanimelist.net/anime/52991/Sousou_no_Frieren'), '52991');
    expect(normalizeImportId('imdb', 'TT0903747'), 'tt0903747');
    expect(normalizeImportId('tmdb', '0'), '');
    expect(normalizeImportId('trakt', 'https://trakt.tv/shows/breaking-bad'), 'breaking-bad');
  });
}
