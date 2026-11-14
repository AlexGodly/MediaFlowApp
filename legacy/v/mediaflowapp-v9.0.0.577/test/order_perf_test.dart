// 9.0.0: Personal Order with a 31k-title account (the owner's: 31,468
// titles). The Order model and every Collection queue must be ready in well
// under a frame budget's worth of seconds, and give the same queues as before.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/collections_logic.dart';
import 'package:mediaflow/src/logic/order_view.dart';
import 'package:mediaflow/src/logic/recommend.dart';
import 'package:mediaflow/src/state/models.dart';
import 'package:mediaflow/src/ui/widgets.dart' show memoFor;

Map<String, dynamic> bigState({int titles = 31468, int ordered = 12000}) {
  final cats = [for (var c = 0; c < 12; c++) <String, dynamic>{'id': 'c$c', 'name': 'Cat $c', 'unit': 'episodes'}];
  final library = [
    for (var i = 0; i < titles; i++)
      <String, dynamic>{'id': 't$i', 'title': 'Title $i', 'categoryId': 'c${i % 12}', 'progress': i % 7, 'status': i % 5 == 0 ? 'active' : 'planned'},
  ];
  final collections = [
    for (var k = 0; k < 6; k++) <String, dynamic>{'id': 'col$k', 'title': 'Collection $k', 'titleIds': [for (var i = k; i < 400; i += 6) 't$i']},
  ];
  return {
    'categories': cats,
    'library': library,
    'collections': collections,
    'sessions': <dynamic>[],
    'settings': <String, dynamic>{},
    'orderPlan': <String, dynamic>{
      'titleIds': [for (var i = 0; i < ordered; i++) 't${(i * 7) % titles}'],
      'viewMode': 'category',
      'collectionAssignments': [
        for (var k = 0; k < 6; k++)
          {'id': 'oca_$k', 'collectionId': 'col$k', 'categoryId': 'c${k * 2}', 'categoryRule': 'match', 'completedRule': 'skip', 'traversedTitleIds': <String>[], 'createdAt': k},
      ],
      'categoryQueues': <String, dynamic>{
        'c0': ['c:oca_0', 't:t0'],
      },
    },
  };
}

void main() {
  test('31k titles: the Order model and every queue are fast', () {
    final state = bigState();
    final view = AccountView(state);
    final sw = Stopwatch()..start();
    final byId = {for (final t in view.library) t.id: t};
    final p = state['orderPlan'] as Map<String, dynamic>;
    final model = OrderTitlesModel.build(p, byId);
    expect(model.titleIds.length, greaterThan(4000));
    expect(model.byCategory.length, 12);
    final searched = OrderTitlesModel.build(p, byId, query: 'title 12', status: 'active', sort: 'title');
    expect(searched.shown, isNotEmpty);
    final queues = orderQueues(state);
    sw.stop();
    expect(queues.length, 12);
    expect(sw.elapsedMilliseconds, lessThan(3000), reason: 'was minutes on a 31k-title account');
    // The plan itself is never changed by reading the queues.
    expect((p['categoryQueues'] as Map)['c0'], ['c:oca_0', 't:t0']);
  });

  test('queues are the same as the recommender reconciles them', () {
    final state = bigState(titles: 600, ordered: 300);
    final queues = {for (final q in orderQueues(state)) q.categoryId: q.tokens};
    final r = Recommender(state, now: 0);
    for (final cid in queues.keys) {
      expect(queues[cid], r.reconcileQueue(cid), reason: cid);
    }
    expect(queues['c0']!.first, 'c:oca_0', reason: 'the saved queue order is kept');
    expect(queues['c2']!.where((t) => t.startsWith('c:')), ['c:oca_1']);
  });

  test('a queue token move keeps working on a big Order', () {
    final state = bigState();
    final p = state['orderPlan'] as Map<String, dynamic>;
    final sw = Stopwatch()..start();
    orderMoveQueueToken(state, p, 'c2', 'c:oca_1', toIndex: 0);
    sw.stop();
    expect((p['categoryQueues'] as Map)['c2'].first, 'c:oca_1');
    expect(sw.elapsedMilliseconds, lessThan(1500));
  });

  test('memoFor keeps different types apart under one name (the Order crash)', () {
    final owner = Object();
    final a = memoFor<Map<String, int>>(owner, 'libraryById', () => {'x': 1});
    final b = memoFor<Map<String, String>>(owner, 'libraryById', () => {'x': 'y'});
    expect(a['x'], 1);
    expect(b['x'], 'y');
    expect(memoFor<Map<String, int>>(owner, 'libraryById', () => {'x': 2})['x'], 1, reason: 'still cached');
  });
}
