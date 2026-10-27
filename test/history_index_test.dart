import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/features/history/history_filter.dart';
import 'package:mediaflow_app/features/history/history_index.dart';

MediaFlowSession session(int i, DateTime now) => MediaFlowSession.fromJson({
  'id': 'session-$i',
  'categoryId': i.isEven ? 'anime' : 'manga',
  'status': i % 4 == 0 ? 'complete' : 'logged',
  'timestamp': now.subtract(Duration(hours: i * 3)).toIso8601String(),
  'note': 'note $i',
  'titles': [
    {'title': 'Title $i', 'qty': 1},
  ],
  'minutes': i % 80,
});

void main() {
  test('indexed History matches original filtering across date ranges', () {
    final now = DateTime(2026, 10, 14, 12);
    final sessions = List.generate(400, (i) => session(i, now));
    final index = MediaFlowHistoryIndex(sessions);
    for (final range in MediaFlowHistoryRange.values) {
      for (final query in ['', 'title 10', 'note 9']) {
        final filter = MediaFlowHistoryFilter(
          categoryId: 'anime',
          status: 'logged',
          search: query,
          range: range,
        );
        expect(
          index.query(filter, now: now).map((s) => s.id).toList(),
          filter.apply(sessions, now: now).map((s) => s.id).toList(),
          reason: 'Mismatch for $range and $query',
        );
      }
    }
  });

  test('query cache is bounded, immutable, and refresh-safe', () {
    final now = DateTime(2026, 10, 14, 12);
    final index = MediaFlowHistoryIndex(
      List.generate(120, (i) => session(i, now)),
    );
    final filter = const MediaFlowHistoryFilter(search: 'note 1');
    final first = index.query(filter, now: now);
    expect(identical(first, index.query(filter, now: now)), isTrue);
    for (var i = 0; i < 20; i++) {
      index.query(MediaFlowHistoryFilter(search: 'note $i'), now: now);
    }
    expect(index.cachedQueries, lessThanOrEqualTo(6));
    expect(() => first.clear(), throwsUnsupportedError);
    final updated = MediaFlowHistoryIndex([
      session(999, now),
    ]);
    expect(updated.length, 1);
  });

  test('50k synthetic History sessions preserve ordering and search', () {
    final now = DateTime(2026, 10, 14, 12);
    final sessions = List.generate(50000, (i) => session(i, now));
    final watch = Stopwatch()..start();
    final index = MediaFlowHistoryIndex(sessions);
    final results = index.query(
      const MediaFlowHistoryFilter(search: 'Title 4999'),
      now: now,
    );
    final initialMs = watch.elapsedMilliseconds;
    expect(results, isNotEmpty);
    expect(results.every((s) =>
        s.titles.any((title) => title.title.contains('4999'))), isTrue);
    watch.reset();
    for (var i = 0; i < 20; i++) {
      index.query(MediaFlowHistoryFilter(search: 'note $i'), now: now);
    }
    final repeatMs = watch.elapsedMilliseconds;
    // ignore: avoid_print
    print('HISTORY_50K_BENCH initial_ms=$initialMs '
        'twenty_queries_ms=$repeatMs');
    expect(index.cachedQueries, lessThanOrEqualTo(6));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
