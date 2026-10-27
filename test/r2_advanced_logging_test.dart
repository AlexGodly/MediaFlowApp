import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/features/logging/r2_advanced_logging_drafts.dart';

MediaFlowTitle sampleTitle() => MediaFlowTitle(
  id: 'title-1', title: 'Example Anime', categoryId: 'anime',
  status: 'active', priority: 'high', progress: 6, total: 12,
  rating: 8.5, coverUrl: '', tags: const ['action'],
  addedAt: DateTime.utc(2026, 1, 1), description: '',
  seasons: [
    const MediaFlowSeason('Season One', 3, 6, id: 's1'),
    const MediaFlowSeason('Season Two', 0, 6, id: 's2'),
  ],
);

void main() {
  test('v504 steppers clamp and retain individual selected timestamps', () {
    final title = sampleTitle();
    final plan = R2DraftTitle(title.id);
    final earlier = DateTime.utc(2025, 4, 2, 14, 35);
    plan.setAmount(title, 3);
    expect(plan.selectedNumbers, [7, 8, 9]);
    plan.setUnitTime(8, earlier);
    plan.chooseMethod(R2LoggingMethod.lastUnit);
    plan.setLastUnit(title, 10);
    expect(plan.selectedNumbers, [7, 8, 9, 10]);
    plan.chooseMethod(R2LoggingMethod.perUnit);
    expect(plan.currentUnits[8], earlier);
    plan.setAmount(title, 99);
    expect(plan.selectedNumbers, [7, 8, 9, 10, 11, 12]);
    expect(plan.currentUnits[8], earlier);
  });

  test('per-season selections persist and quantity is aggregated', () {
    final title = sampleTitle();
    final plan = R2DraftTitle(title.id);
    plan.chooseSeason('s1');
    plan.setAmount(title, 2);
    expect(plan.selectedNumbers, [4, 5]);
    plan.chooseSeason('s2');
    plan.toggleUnit(title, 1, at: DateTime.utc(2026, 10, 18));
    expect(plan.selectedNumbers, [1]);
    expect(plan.quantity, 3);
    plan.chooseSeason('s1');
    expect(plan.selectedNumbers, [4, 5]);
  });

  test('safe account-local controller can reorder and clear its draft', () {
    final title = sampleTitle();
    final other = MediaFlowTitle(
      id: 'title-2', title: 'Example Book', categoryId: 'books',
      status: 'planned', priority: 'medium', progress: 0, total: 9,
      rating: null, coverUrl: '', tags: const [], seasons: const [],
      addedAt: null, description: '',
    );
    final drafts = R2AdvancedLoggingDrafts();
    drafts.add(title);
    drafts.add(title);
    drafts.add(other);
    expect(drafts.titleCount, 2);
    drafts.update(title.id, (entry) => entry.setAmount(title, 2));
    expect(drafts.totalUnits, 2);
    drafts.move(title.id, 1);
    expect(drafts.entries.first.titleId, other.id);
    expect(drafts.review().last['titleId'], title.id);
    drafts.clear();
    expect(drafts.totalUnits, 0);
    expect(drafts.entries, isEmpty);
    drafts.dispose();
  });

  test('repeat draft does not increase progress preview', () {
    final title = sampleTitle();
    final entry = R2DraftTitle(title.id);
    entry.setAmount(title, 2);
    expect(entry.previewProgress(title), 8);
    entry.isRepeat = true;
    expect(entry.previewProgress(title), 6);
  });

  test('cloud draft serializer uses website v285/v369 shape, () {
  final title = sampleTitle();
  final drafts = R2AdvancedLoggingDrafts();
  drafts.add(title);
  drafts.update(title.id, (entry) {
    entry.chooseSeason('s1');
    entry.setAmount(title, 2);
    entry.setUnitTime(4, DateTime.utc(2026, 10, 20, 12));
    entry.setUnitSeconds(4, 1500);
    entry.isRepeat = true;
  });

  final cloud = drafts.toV285CloudDraft({title.id: title});
  expect(cloud['categoryId'], 'anime');
  expect(cloud['amount'], 2);
  expect(cloud['updateLibrary'], isTrue);
  expect(cloud['v369Interface'], 'itemized');
  expect(cloud['v369CommitId'], startsWith('native-'));
  final entries = cloud['entries'] as List;
  final row = entries.single as Map;
  expect(row['libraryId'], title.id);
  expect(row['v369Itemized'], isTrue);
  expect(row['qty'], 2);
  final units = row['v369Units'] as List;
  expect(units, hasLength(2));
  expect((units.first as Map)['number'], 4);
  expect((units.first as Map)['isRepeat'], isTrue);
  expect((units.first as Map)['durationSeconds'], 1500);
  expect((units.first as Map)['loggedAt'],
      DateTime.utc(2026, 10, 20, 12).millisecondsSinceEpoch);
  drafts.dispose();
});

}
