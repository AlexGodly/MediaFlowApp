// The app's ratings engine must ask the same sources in the same order, accept
// the same records and save the title exactly as the website does. Fixtures:
// tool/website_reference/generate_ratings_goldens.mjs runs the website's own
// v555 code (mf555RatingsForTitle / mf555ApplyRatings) with stubbed sources.

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/records.dart' show jsStringify;
import 'package:mediaflow/src/logic/ratings_engine.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/ratings-golden.json').readAsStringSync()) as Map<String, dynamic>;

  for (final raw in fx['scenarios'] as List) {
    final sc = (raw as Map).cast<String, dynamic>();
    test('ratings engine: ${sc['name']}', () async {
      final calls = <List<Object?>>[];
      final answers = (sc['answers'] as Map? ?? const {}).cast<String, dynamic>();
      final wiki = sc['wiki'] as Map?;
      final cat = (sc['category'] as Map).cast<String, dynamic>();
      final item = (jsonDecode(jsonEncode(sc['item'])) as Map).cast<String, dynamic>();

      final found = await ratingsForTitle(
        item,
        providers: (sc['providers'] as List).cast<String>(),
        kind: TitleKind(unit: '${cat['unit'] ?? ''}', type: '${cat['type'] ?? ''}'),
        lookup: (provider, query) async {
          final ids = (query['externalIds'] as Map).cast<String, dynamic>();
          calls.add([provider, query['title'], ids]);
          final key = '$provider|${query['title']}|${jsonEncode(SplayTreeMap<String, dynamic>.of(ids))}';
          final a = answers[key];
          if (a is Map && a['error'] != null) throw Exception(a['error']);
          return [for (final r in (a as List? ?? const [])) (jsonDecode(jsonEncode(r)) as Map).cast<String, dynamic>()];
        },
        wikidata: (ids) async {
          calls.add(['wikidata', '', {...ids}]);
          if (wiki == null) return null;
          return WikiLinks(
            '${wiki['qid']}',
            (wiki['ids'] as Map).cast<String, String>(),
            (wiki['parent'] as Map?)?.cast<String, String>(),
          );
        },
      );
      final written = applyRatings(item, found, sc['now'] as int);
      final want = (sc['expected'] as Map).cast<String, dynamic>();

      expect(jsonEncode(calls), jsonEncode(want['calls']), reason: 'source calls');
      expect(
        [for (final r in found.accepted) [r['provider'], '${r['recordId']}', r['mf555Via']]],
        want['accepted'],
      );
      expect(
        {for (final e in found.discovered.entries) e.key: {'value': e.value.value, 'via': e.value.via, 'conflict': e.value.conflict}},
        want['discovered'],
      );
      expect([for (final f in found.failures) f.$1], want['failures']);
      expect([written.ratings, written.ids], want['written']);
      expect(jsStringify(item), want['itemJson'], reason: 'saved title must be byte-identical');
    });
  }

  test('whole-show names match the website', () {
    for (final pair in fx['baseShowNames'] as List) {
      expect(baseShowName(pair[0]), pair[1], reason: '${pair[0]}');
    }
  });

  test('title normalisation matches the website', () {
    for (final pair in fx['norms'] as List) {
      expect(normTitle(pair[0]), pair[1], reason: '${pair[0]}');
    }
    for (final pair in fx['years'] as List) {
      expect(yearOf(pair[0]), pair[1], reason: '${pair[0]}');
    }
  });

  test('saving edited IDs records manual overrides like the website', () {
    final item = <String, dynamic>{'id': 'x', 'externalIds': {'mal': '1', 'imdb': 'tt1234567'}, 'malId': 1, 'modifiedAt': 5};
    expect(saveExternalIds(item, {'mal': '2', 'imdb': 'tt1234567', 'tmdb': ''}, 100), isTrue);
    expect(item['externalIds'], {'mal': '2', 'imdb': 'tt1234567'});
    expect(item['v377ManualExternalIds'], {'mal': '2'});
    expect(item.containsKey('malId'), isFalse);
    expect(item['modifiedAt'], 100);
    expect(saveExternalIds(item, {'mal': '2'}, 200), isFalse);
  });
}
