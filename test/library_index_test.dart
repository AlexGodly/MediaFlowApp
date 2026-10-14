import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_index.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';

MediaFlowTitle title(int index) => MediaFlowTitle.fromJson({
  'id': 'title-$index',
  'title': 'Title ${index.toString().padLeft(6, '0')}',
  'categoryId': index.isEven ? 'anime' : 'manga',
  'status': index % 3 == 0 ? 'completed' : 'active',
  'priority': index % 5 == 0 ? 'high' : 'low',
  'progress': index % 30,
  'total': 30,
  'rating': (index % 10) + 1,
  'tags': ['genre-${index % 7}'],
});

void main() {
  test('Indexed filters match baseline behavior for all sort modes', () {
    final titles = List.generate(500, title);
    final index = MediaFlowLibraryIndex(titles);
    for (final sort in LibrarySort.values) {
      for (final search in ['', 'title 0002', 'genre-4']) {
        final filter = MediaFlowLibraryFilter(
          sort: sort,
          search: search,
          categoryId: 'anime',
          status: 'active',
          priority: 'low',
        );
        expect(
          index.query(filter).map((item) => item.id).toList(),
          filter.apply(titles).map((item) => item.id).toList(),
          reason: 'Mismatch for $sort and search $search',
        );
      }
    }
    expect(index.cachedSortCount, LibrarySort.values.length);
  });

  test('Repeated searches reuse sorted snapshots and bound result memory', () {
    final index = MediaFlowLibraryIndex(List.generate(120, title));
    final filter = const MediaFlowLibraryFilter(search: 'Title 00001');
    final first = index.query(filter);
    expect(identical(first, index.query(filter)), isTrue);
    expect(index.cachedSortCount, 1);
    for (var i = 0; i < 30; i++) {
      index.query(MediaFlowLibraryFilter(search: 'Title $i'));
    }
    expect(index.cachedQueryCount, lessThanOrEqualTo(8));
    expect(index.cachedSortCount, 1);
    expect(() => first.clear(), throwsUnsupportedError);
  });

  test('100,000 synthetic titles: filtering and paging correctness', () {
    const size = 100000;
    final generated = List.generate(size, title);
    final watch = Stopwatch()..start();
    final index = MediaFlowLibraryIndex(generated);
    final all = index.query(const MediaFlowLibraryFilter());
    expect(all.length, size);
    expect(all.first.title, 'Title 000000');
    expect(all.last.title, 'Title 099999');
    final matched = index.query(const MediaFlowLibraryFilter(
      search: 'Title 0999',
      categoryId: 'anime',
      status: 'active',
    ));
    expect(matched, isNotEmpty);
    expect(matched.every((item) => item.title.contains('Title 0999') &&
        item.categoryId == 'anime' && item.status == 'active'), isTrue);
    final visible = matched.skip(0).take(50).toList();
    expect(visible.length, lessThanOrEqualTo(50));
    final firstElapsed = watch.elapsedMilliseconds;
    watch.reset();
    for (var i = 0; i < 20; i++) {
      index.query(MediaFlowLibraryFilter(
        search: 'Title 0${i.toString().padLeft(2, '0')}',
      ));
    }
    final followupElapsed = watch.elapsedMilliseconds;
    // Timing is reported, NOT asserted: CI hardware varies significantly.
    // ignore: avoid_print
    print('LIBRARY_100K_BENCH first_index_and_query_ms=$firstElapsed '
        'twenty_followup_queries_ms=$followupElapsed '
        'cached_sorts=${index.cachedSortCount} '
        'cached_queries=${index.cachedQueryCount}');
    expect(index.cachedSortCount, 1);
    expect(index.cachedQueryCount, lessThanOrEqualTo(8));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
