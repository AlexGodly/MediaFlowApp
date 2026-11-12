// Adding titles to a collection must not freeze the app (owner's report):
// 2,000 titles into a collection of a 50,000-title Library with 20,000 logs,
// through the same copy-on-write edit path the app uses.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/edit_op.dart';
import 'package:mediaflow/src/logic/collections_logic.dart';
import 'package:mediaflow/src/state/lazy_copy.dart';

void main() {
  test('2,000 titles into a collection of a 50k-title Library is quick', () {
    const day = 86400000;
    final now = DateTime(2026, 11, 8, 12).millisecondsSinceEpoch;
    final state = <String, dynamic>{
      'categories': [
        {'id': 'anime', 'name': 'Anime', 'unit': 'episodes', 'enabled': true},
      ],
      'library': [
        for (var i = 0; i < 50000; i++) {'id': 't$i', 'title': 'Title $i', 'categoryId': 'anime', 'progress': i % 12, 'total': 12},
      ],
      'sessions': [
        for (var i = 0; i < 20000; i++)
          {'id': 's$i', 'categoryId': 'anime', 'timestamp': now - (i % 900) * day, 'date': '2026-01-01', 'actualAmount': 1, 'minutes': 24, 'status': 'complete'},
      ],
      'collections': [
        {'id': 'c1', 'name': 'Favourites', 'titleIds': <String>[], 'order': <String>[], 'createdAt': now, 'updatedAt': now},
      ],
      'settings': <String, dynamic>{},
      'xpLedger': <String, dynamic>{},
    };
    final ids = [for (var i = 0; i < 2000; i++) 't${i * 25}'];
    var k = 0;
    String uid() => 'u${k++}';

    final sw = Stopwatch()..start();
    final copy = LazyStateCopy(state);
    final n = addCollectionTitles(copy, 'c1', ids, now, uid);
    final op = editFromStates(state, copy, now: now, label: 'Add titles to collection');
    op!.apply(state);
    sw.stop();
    expect(n, 2000);
    expect((collectionById(state, 'c1')!['titleIds'] as List).length, 2000);
    expect(copy.touched.contains('library'), isFalse, reason: 'the Library is only read, never copied');
    // ignore: avoid_print
    print('add 2,000 to a collection: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsedMilliseconds, lessThan(1500));

    // A second edit right after reuses the streak work.
    final sw2 = Stopwatch()..start();
    final copy2 = LazyStateCopy(state);
    removeCollectionTitles(copy2, 'c1', {'t0', 't25'}, now + 1, uid);
    editFromStates(state, copy2, now: now + 1)!.apply(state);
    sw2.stop();
    // ignore: avoid_print
    print('remove 2 from a collection: ${sw2.elapsedMilliseconds} ms');
    expect(sw2.elapsedMilliseconds, lessThan(800));
  });
}
