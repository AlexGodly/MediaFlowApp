// Personal Order: clear keeps the website's recovery copy (v142), restore,
// export → import round trip (matched by id, External IDs, then title +
// category), and moving titles in a big Order stays quick.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/collections_logic.dart';

Map<String, dynamic> _state() => {
      'categories': [
        {'id': 'anime', 'name': 'Anime'},
        {'id': 'books', 'name': 'Books'},
      ],
      'library': [
        {'id': 'a', 'title': 'Frieren', 'categoryId': 'anime', 'externalIds': {'mal': '52991'}},
        {'id': 'b', 'title': 'Dune', 'categoryId': 'books'},
        {'id': 'c', 'title': 'Mushishi', 'categoryId': 'anime'},
      ],
      'orderPlan': {
        'titleIds': ['c', 'a', 'b'],
        'viewMode': 'category',
        'categoryMode': 'custom',
        'categoryOrder': ['books', 'anime'],
        'hiddenCategories': ['books'],
      },
      'settings': <String, dynamic>{},
    };

void main() {
  test('clear keeps one recovery copy, restore brings it back', () {
    final s = _state();
    orderClear(s, 1000);
    final p = s['orderPlan'] as Map<String, dynamic>;
    expect(p['titleIds'], isEmpty);
    expect(p['lastClearedOrder'], {
      'titleIds': ['c', 'a', 'b'],
      'viewMode': 'category',
      'categoryMode': 'custom',
      'categoryOrder': ['books', 'anime'],
      'hiddenCategories': ['books'],
      'savedAt': 1000,
    });
    expect(orderRestoreLast(s, 2000), 3);
    final r = s['orderPlan'] as Map<String, dynamic>;
    expect(r['titleIds'], ['c', 'a', 'b']);
    expect(r['lastClearedOrder'], isNull);
    expect(r['modifiedAt'], 2000);
    expect(orderRestoreLast(s, 3000), 0);
  });

  test('export and import into another account match titles', () {
    final data = orderExport(_state(), DateTime.utc(2026, 11, 8));
    expect(data['format'], 'MediaFlowOrder');
    expect((data['titles'] as List).length, 3);
    final other = <String, dynamic>{
      'categories': [
        {'id': 'x-anime', 'name': 'anime'},
        {'id': 'x-books', 'name': 'Books'},
      ],
      'library': [
        {'id': 'z1', 'title': 'Something', 'categoryId': 'x-anime', 'externalIds': {'mal': '52991'}},
        {'id': 'z2', 'title': 'dune', 'categoryId': 'x-books'},
        {'id': 'z3', 'title': 'Other', 'categoryId': 'x-anime'},
      ],
      'orderPlan': {'titleIds': ['z3']},
    };
    final r = orderImport(other, data, 5000);
    expect(r.error, isNull);
    expect((r.imported, r.skipped), (2, 1));
    final p = other['orderPlan'] as Map<String, dynamic>;
    expect(p['titleIds'], ['z1', 'z2']);
    expect(p['categoryOrder'], ['x-books', 'x-anime']);
    expect(p['hiddenCategories'], ['x-books']);
    expect((p['lastClearedOrder'] as Map)['titleIds'], ['z3']);
    expect(orderImport(other, {'nope': 1}, 1).error, 'This is not a MediaFlow Order export.');
  });

  test('8.1.1: Collection assignments, queues and the queue view travel with the Order (website v287/v288)', () {
    final s = _state()
      ..['collections'] = [
        {'id': 'col1', 'title': 'Winter watchlist', 'description': 'cozy', 'titleIds': ['a', 'c']},
      ];
    (s['orderPlan'] as Map<String, dynamic>)
      ..['collectionAssignments'] = [
        {'id': 'as1', 'collectionId': 'col1', 'categoryId': 'anime', 'categoryRule': 'match', 'completedRule': 'skip', 'traversedTitleIds': [], 'createdAt': 1},
      ]
      ..['categoryQueues'] = {
        'anime': ['t:c', 'c:as1', 't:a'],
      }
      ..['v288QueueView'] = {'mode': 'cards'};
    final data = orderExport(s, DateTime.utc(2026, 11, 13));
    expect(data['formatVersion'], 5);
    expect(data['mediaFlowVersion'], websiteRelease);
    expect(((data['orderPlan'] as Map)['collectionAssignments'] as List).length, 1);
    expect((data['collections'] as List).single, {'id': 'col1', 'title': 'Winter watchlist', 'description': 'cozy'});

    final other = <String, dynamic>{
      'categories': [
        {'id': 'x-anime', 'name': 'Anime'},
        {'id': 'x-books', 'name': 'Books'},
      ],
      'library': [
        {'id': 'z1', 'title': 'Frieren', 'categoryId': 'x-anime', 'externalIds': {'mal': '52991'}},
        {'id': 'z2', 'title': 'Dune', 'categoryId': 'x-books'},
        {'id': 'z3', 'title': 'Mushishi', 'categoryId': 'x-anime'},
      ],
      'collections': [
        {'id': 'other-col', 'title': 'winter watchlist', 'titleIds': ['z1']},
      ],
      'orderPlan': <String, dynamic>{},
    };
    final r = orderImport(other, data, 5000);
    expect(r.error, isNull);
    final p = other['orderPlan'] as Map<String, dynamic>;
    final a = (p['collectionAssignments'] as List).single as Map;
    expect(a['collectionId'], 'other-col', reason: 'matched by title');
    expect(a['categoryId'], 'x-anime', reason: 'matched by name');
    expect(p['categoryQueues'], {
      'x-anime': ['t:z3', 'c:${a['id']}', 't:z1'],
    });
    expect(p['v288QueueView'], {'mode': 'cards'});
  });

  test('moving a title inside a category of a big Order is quick', () {
    final s = <String, dynamic>{
      'categories': [
        {'id': 'a'},
        {'id': 'b'},
      ],
      'library': [for (var i = 0; i < 50000; i++) {'id': 't$i', 'title': 'T$i', 'categoryId': i.isEven ? 'a' : 'b'}],
    };
    final p = <String, dynamic>{'titleIds': [for (var i = 0; i < 5000; i++) 't$i']};
    final sw = Stopwatch()..start();
    orderMoveTitle(p, s, 't4998', toPosition: 0, categoryId: 'a');
    sw.stop();
    expect((p['titleIds'] as List).first, 't4998');
    expect(sw.elapsedMilliseconds, lessThan(500));
  });
}
