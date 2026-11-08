// Edits copy only what they change (lib/src/state/lazy_copy.dart): editing one
// title of a very big Library must not copy or compare the others, and the
// result must be exactly what a full copy would give.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/edit_op.dart';
import 'package:mediaflow/src/state/lazy_copy.dart';
import 'package:mediaflow/src/util/js.dart';

void main() {
  Map<String, dynamic> account(int n) => {
        'library': [
          for (var i = 0; i < n; i++)
            {'id': 't$i', 'title': 'Title $i', 'progress': i, 'tags': ['a'], 'externalIds': {'mal': '$i'}},
        ],
        'settings': {'theme': 'x'},
      };

  test('changing one title of 100,000 only changes that title', () {
    final original = account(100000);
    final before = jsonEncode(original);
    final copy = LazyStateCopy(original);
    final lib = List<dynamic>.of(asList(copy['library']));
    final item = asMap(lib[500])!;
    item['progress'] = 9999;
    (item['tags'] as List).add('b');
    asMap(item['externalIds'])!['imdb'] = 'tt0000001';
    copy['library'] = lib;

    final sw = Stopwatch()..start();
    final op = editFromStates(original, copy, now: 1)!;
    expect(sw.elapsedMilliseconds, lessThan(3000));
    expect(jsonEncode(original), before, reason: 'the original is never changed');
    expect(op.changes.every((c) => c.path.contains('#t500')), isTrue);
    expect(op.changes.length, 3);

    // Applying the change gives the same account a full copy would.
    final full = jsonClone(original) as Map<String, dynamic>;
    final fl = full['library'] as List;
    (fl[500] as Map)['progress'] = 9999;
    ((fl[500] as Map)['tags'] as List).add('b');
    ((fl[500] as Map)['externalIds'] as Map)['imdb'] = 'tt0000001';
    op.apply(original);
    original.remove('savedAt'); // applying stamps the save time
    expect(jsonEncode(original), jsonEncode(full));
  });

  test('key order matches a plain map', () {
    final src = {'a': 1, 'b': 2, 'c': 3};
    final plain = Map<String, dynamic>.of(src);
    final cow = CowMap(src);
    for (final m in [plain, cow]) {
      m['b'] = 20; // stays in place
      m['d'] = 4; // appended
      m.remove('a');
      m['a'] = 10; // removed then added: moves to the end
    }
    expect(jsonEncode(cow), jsonEncode(plain));
    expect(src, {'a': 1, 'b': 2, 'c': 3});
  });

  test('snapshots share unchanged titles and copy changed ones', () {
    final original = account(10);
    final copy = LazyStateCopy(original);
    final lib = asList(copy['library']);
    expect((lib as CowList).pristine, isTrue);
    asMap(lib[3])!['title'] = 'Changed';
    final snap = lib.snapshot() as List;
    expect(identical(snap[0], (original['library'] as List)[0]), isTrue);
    expect((snap[3] as Map)['title'], 'Changed');
    expect(((original['library'] as List)[3] as Map)['title'], 'Title 3');
  });
}
