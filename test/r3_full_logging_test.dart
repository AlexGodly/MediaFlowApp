import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/features/logging/r2_advanced_logging_drafts.dart';

MediaFlowTitle title({String id = 'one', String name = 'One',
    int progress = 3, int total = 12, bool seasons = false}) =>
    MediaFlowTitle(
      id: id, title: name, categoryId: 'anime', status: 'active',
      priority: 'high', progress: progress.toDouble(),
      total: total.toDouble(), rating: 8, coverUrl: '',
      tags: const [], description: '', addedAt: DateTime.utc(2026, 1, 1),
      seasons: seasons ? [
        const MediaFlowSeason('First', 3, 6, id: 's1'),
        const MediaFlowSeason('Second', 0, 6, id: 's2'),
      ] : const [],
    );

void main() {
  test('sparse Per Unit consumption does not invent progress', () {
    final item = title();
    final draft = R2DraftTitle(item.id);
    draft.toggleUnit(item, 4);
    draft.toggleUnit(item, 6);
    expect(draft.quantity, 2);
    expect(draft.previewProgress(item), 4);
    expect(draft.willReplaceDetailedUnits(item, 2), isTrue);
    draft.toggleUnit(item, 5);
    expect(draft.previewProgress(item), 6);
    draft.toggleUnit(item, 4);
    expect(draft.previewProgress(item), 3);
  });

  test('method switches retain timestamps and customized per-unit runtime', () {
    final item = title();
    final draft = R2DraftTitle(item.id);
    draft.setAmount(item, 3);
    final original = DateTime.utc(2026, 7, 15, 15, 19);
    draft.setUnitTime(5, original);
    draft.setUnitSeconds(5, 205);
    draft.chooseMethod(R2LoggingMethod.lastUnit);
    expect(draft.currentUnits[5], original);
    draft.chooseMethod(R2LoggingMethod.perUnit);
    expect(draft.secondsForUnit(5), 205);
    expect(draft.effectiveRuntimeSeconds, 24 * 60 * 2 + 205);
    draft.manualRuntime = true;
    draft.customTotalRuntimeSeconds = 4070;
    expect(draft.effectiveRuntimeSeconds, 4070);
    final review = draft.toLocalReview();
    expect(review['customTotalRuntimeSeconds'], 4070);
    expect((review['unitDurations'] as Map)['_whole_title']['5'], 205);
  });

  test('repeat has independent zero-based selection and never advances progress', () {
    final item = title(progress: 9, total: 12);
    final draft = R2DraftTitle(item.id)..isRepeat = true;
    expect(draft.startFor(item), 0);
    expect(draft.allowedQuantity(item), 12);
    draft.setAmount(item, 4);
    expect(draft.selectedNumbers, [1, 2, 3, 4]);
    expect(draft.previewProgress(item), 9);
    expect(draft.quantity, 4);
  });

  test('season selection keeps the other season and exact progress', () {
    final item = title(progress: 3, total: 12, seasons: true);
    final draft = R2DraftTitle(item.id);
    draft.chooseSeason('s1');
    draft.toggleUnit(item, 4);
    draft.toggleUnit(item, 5);
    expect(draft.previewProgress(item), 5);
    draft.chooseSeason('s2');
    draft.toggleUnit(item, 1);
    expect(draft.previewProgress(item), 6);
    expect(draft.quantity, 3);
    draft.chooseSeason('s1');
    expect(draft.selectedNumbers, [4, 5]);
  });

  test('bulk method never erases timestamps of unchanged contiguous units', () {
    final item = title();
    final draft = R2DraftTitle(item.id);
    draft.setAmount(item, 2);
    final early = DateTime.utc(2024, 2, 1);
    draft.setUnitTime(4, early);
    draft.setAmount(item, 4);
    expect(draft.currentUnits[4], early);
    draft.setAmount(item, 1);
    expect(draft.currentUnits[4], early);
    expect(draft.currentUnits.containsKey(5), isFalse);
  });

  test('logging controller sorts selected titles without changing data', () {
    final a = title(id: 'a', name: 'Zebra', progress: 7);
    final b = title(id: 'b', name: 'Alpha', progress: 2);
    final drafts = R2AdvancedLoggingDrafts();
    drafts.add(a);
    drafts.add(b);
    drafts.update(a.id, (entry) => entry.setAmount(a, 1));
    drafts.update(b.id, (entry) => entry.setAmount(b, 2));
    drafts.sortBy('title', {'a': a, 'b': b});
    expect(drafts.entries.map((e) => e.titleId), ['b', 'a']);
    expect(drafts.totalUnits, 3);
    drafts.sortBy('progress', {'a': a, 'b': b}, descending: true);
    expect(drafts.entries.first.titleId, 'a');
    expect(drafts.review().first['titleId'], 'a');
    drafts.clear();
    expect(drafts.titleCount, 0);
    drafts.dispose();
  });

  test('all draft operations are local and do not mutate Library model', () {
    final item = title();
    final drafts = R2AdvancedLoggingDrafts();
    drafts.add(item);
    drafts.update(item.id, (entry) => entry.setAmount(item, 2));
    expect(item.progress, 3);
    expect(drafts.review().single['titleId'], item.id);
    drafts.dispose();
  });
}
