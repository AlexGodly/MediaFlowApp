// Website v565 titles: a title's own unit and its names in every language.
// test/fixtures/titles-v565-golden.json comes from the real website file
// (tool/website_reference/generate_titles_v565_goldens.mjs).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/title_names.dart';
import 'package:mediaflow/src/logic/title_units.dart';
import 'package:mediaflow/src/state/models.dart';

Map<String, dynamic> _m(Object? v) => (jsonDecode(jsonEncode(v)) as Map).cast<String, dynamic>();

void main() {
  final g = (jsonDecode(File('test/fixtures/titles-v565-golden.json').readAsStringSync()) as Map).cast<String, dynamic>();
  const cats = {
    'hour': {'unit': 'sessions', 'minutesPerUnit': 60},
    'secs': {'unit': 'sessions', 'secondsPerUnit': 1500, 'minutesPerUnit': 99},
    'frac': {'unit': 'episodes', 'minutesPerUnit': 23.5},
    'none': {'unit': 'episodes'},
  };
  const items = {
    'plain': {'title': 'Plain'},
    'matches': {'title': 'Game', 'mf565Unit': 'matches', 'mf565SecondsPerUnit': 1200},
    'noRuntime': {'title': 'Game', 'mf565Unit': 'rounds'},
    'long': {'title': 'Long', 'mf565Unit': 'boss fights', 'mf565SecondsPerUnit': 5400},
    'odd': {'title': 'Odd', 'mf565Unit': 'laps', 'mf565SecondsPerUnit': 700},
    'spaces': {'title': 'S', 'mf565Unit': '  races  ', 'mf565SecondsPerUnit': 900.9},
  };

  test('units convert to the category exactly like the website', () {
    for (final raw in g['units'] as List) {
      final c = _m(raw);
      final item = _m(items[c['item']]), cat = _m(cats[c['cat']]);
      final why = '${c['item']} / ${c['cat']} / ${c['qty']}';
      expect(unitFactor(item, cat), closeTo((c['factor'] as num).toDouble(), 1e-12), reason: 'factor $why');
      expect(toCategoryAmount(item, cat, c['qty']), (c['amount'] as num).toDouble(), reason: 'amount $why');
      expect(titleUnit(item, cat), c['key'], reason: 'unit $why');
      expect(titleSecondsPerUnit(item, cat), c['seconds'], reason: 'seconds $why');
    }
  });

  test('custom units read as typed', () {
    for (final raw in g['labels'] as List) {
      final c = _m(raw);
      expect(unitLabel(c['unit'] as String, c['count'] as int), c['label'], reason: '${c['unit']} × ${c['count']}');
    }
  });

  test('names, shown name and search match the website', () {
    final prefSets = [
      for (final p in g['prefSets'] as List)
        (global: _m(p)['global'] as String, categories: _m(_m(p)['categories']).map((k, v) => MapEntry(k, v as String))),
    ];
    const queries = ['titan', 'aot', '巨人', 'eng', 'メイン', 'nothing', '', 'MAIN', 'same'];
    for (final raw in g['names'] as List) {
      final c = _m(raw);
      final item = _m(c['item']);
      expect([for (final n in titleNames(item)) {'lang': n.lang, 'text': n.text, 'source': n.source}], c['names'], reason: 'names of ${item['title']}');
      expect(nameSearchText(item), c['search']);
      expect([for (final p in prefSets) displayTitle(item, p)], c['shown'], reason: 'shown name of ${item['title']}');
      expect([for (final q in queries) nameMatches(item, q)], c['matches'], reason: 'search of ${item['title']}');
    }
    for (final raw in g['prefsRaw'] as List) {
      final c = _m(raw);
      final p = namePrefs({'mf565TitleNames': c['raw']});
      expect({'global': p.global, 'categories': p.categories}, c['prefs']);
    }
    for (final pair in g['scripts'] as List) {
      expect(scriptLang((pair as List)[0]), pair[1]);
    }
  });

  test('recovered names are added once, never duplicated', () {
    for (final raw in g['addCases'] as List) {
      final c = _m(raw);
      final item = _m(c['item']);
      final add = [
        for (final n in c['add'] as List) (lang: _m(n)['lang'] as String, text: _m(n)['text'] as String, source: (_m(n)['source'] ?? '') as String),
      ];
      expect(addTitleNames(item, add), c['added']);
      expect(jsonEncode(item), jsonEncode(c['after']));
    }
  });

  test('the title editor writes unit, runtime and names like the website', () {
    for (final raw in g['editCases'] as List) {
      final c = _m(raw);
      final item = _m(c['item']), data = _m(c['data']);
      final extras = TitleExtras(
        unit: data['unit'] as String,
        seconds: data['secs'] as int,
        names: [for (final n in data['names'] as List) (lang: _m(n)['lang'] as String, text: _m(n)['text'] as String, source: '')],
        lang: data['lang'] as String,
        exempt: data['exempt'] as bool,
      );
      expect(extras.writeTo(item, c['before'] as List, 1000), c['changed']);
      expect(jsonEncode(item), jsonEncode(c['after']), reason: jsonEncode(data));
    }
  });

  test('titles show the chosen name; the main title stays for matching', () {
    final view = AccountView(_m({
      'settings': {'mf565TitleNames': {'global': 'en', 'categories': {}}},
      'library': [
        {'id': 'a', 'title': 'Shingeki no Kyojin', 'titleEnglish': 'Attack on Titan', 'categoryId': 'anime'},
        {'id': 'b', 'title': 'Plain', 'categoryId': 'anime'},
      ],
    }));
    expect(view.library[0].title, 'Attack on Titan');
    expect(view.library[0].mainTitle, 'Shingeki no Kyojin');
    expect(view.library[1].title, 'Plain');
    expect(view.shownName('Shingeki no Kyojin'), 'Attack on Titan');
    expect(view.shownName('Unknown'), 'Unknown');
  });
}
