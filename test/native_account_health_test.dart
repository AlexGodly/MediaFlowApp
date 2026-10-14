import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/services/native_account_health.dart';

MediaFlowTitle title(String id, String category) =>
    MediaFlowTitle.fromJson({
      'id': id, 'title': id, 'categoryId': category,
    });

MediaFlowCollection collection(List<String> ids) =>
    MediaFlowCollection.fromJson({
      'id': 'collection', 'title': 'Example', 'titleIds': ids,
    });

MediaFlowSession session(String linkedId) => MediaFlowSession.fromJson({
  'id': 'session', 'date': '2026-10-14',
  'titles': [
    {'title': 'Historical entry', 'libraryId': linkedId, 'qty': 1},
  ],
});

void main() {
  test('empty snapshot has no issues', () {
    final result = NativeAccountHealth.inspect(
      const MediaFlowCatalog(categories: [], library: []),
    );
    expect(result.hasWarnings, isFalse);
    expect(result.unresolvedReferences, 0);
    expect(result.libraryTitles, 0);
  });

  test('counts missing links and duplicate identifiers without modifying data',
      () {
    final data = MediaFlowCatalog(
      categories: [
        MediaFlowCategory.fromJson({'id': 'anime', 'name': 'Anime'}),
      ],
      library: [
        title('a', 'anime'),
        title('a', 'anime'),
        title('', 'missing-category'),
        title('b', 'missing-category'),
      ],
      personalOrderIds: const ['a', 'ghost', 'a'],
      collections: [
        collection(['a', 'ghost', 'a']),
      ],
      sessions: [
        session('a'),
        session('deleted-title'),
        session(''),
      ],
    );
    final report = NativeAccountHealth.inspect(data);
    expect(report.libraryTitles, 4);
    expect(report.duplicateLibraryIds, 1);
    expect(report.emptyLibraryIds, 1);
    expect(report.missingCategoryReferences, 2);
    expect(report.missingPersonalOrderReferences, 1);
    expect(report.duplicatePersonalOrderReferences, 1);
    expect(report.missingCollectionReferences, 1);
    // Collection.fromJson normalizes duplicate membership.
    expect(report.duplicateCollectionReferences, 0);
    expect(report.missingHistoryTitleReferences, 1);
    expect(report.unresolvedReferences, 5);
    expect(report.hasWarnings, isTrue);
    expect(data.library.length, 4);
    expect(data.personalOrderIds, ['a', 'ghost', 'a']);
  });

  test('valid references produce no false missing-link warnings', () {
    final data = MediaFlowCatalog(
      categories: [
        MediaFlowCategory.fromJson({'id': 'anime', 'name': 'Anime'}),
      ],
      library: [title('a', 'anime')],
      personalOrderIds: const ['a'],
      collections: [collection(['a'])],
      sessions: [session('a')],
    );
    final report = NativeAccountHealth.inspect(data);
    expect(report.hasWarnings, isFalse);
    expect(report.unresolvedReferences, 0);
    expect(report.historySessions, 1);
  });

  test('large synthetic account scans references without persisting data', () {
    final data = MediaFlowCatalog(
      categories: [
        MediaFlowCategory.fromJson({'id': 'anime', 'name': 'Anime'}),
      ],
      library: [
        for (var i = 0; i < 100000; i++) title('id-$i', 'anime'),
      ],
      personalOrderIds: [
        for (var i = 0; i < 100000; i++) 'id-$i',
      ],
    );
    final timer = Stopwatch()..start();
    final report = NativeAccountHealth.inspect(data);
    expect(report.libraryTitles, 100000);
    expect(report.personalOrderReferences, 100000);
    expect(report.hasWarnings, isFalse);
    // Timing is CI telemetry, not a real-device frame-rate guarantee.
    // ignore: avoid_print
    print('ACCOUNT_HEALTH_100K_BENCH inspect_ms=${timer.elapsedMilliseconds}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
