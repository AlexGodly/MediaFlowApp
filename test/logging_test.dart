import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/cloud/mediaflow_cloud.dart';
import 'package:mediaflow_app/logging/log_draft.dart';

CloudTitle title({int progress = 5}) => CloudTitle(
  id: 'title-1', title: 'Example Anime', categoryId: 'anime',
  status: 'active', progress: progress, total: 13,
  coverUrl: '', seasons: const [],
);

void main() {
  test('new app adds titles only to a local logging draft', () {
    final ctrl = LoggingDraftController();
    final original = title();
    ctrl.add(original);
    ctrl.add(original);
    expect(ctrl.length, 1);
    ctrl.edit(original.id, (entry) => entry.setQuantity(3));
    expect(ctrl.units, 3);
    expect(original.progress, 5);
    expect(ctrl.titles.single.projectedProgress, 8);
    ctrl.clear();
    expect(ctrl.length, 0);
    ctrl.dispose();
  });

  test('per-unit gaps never skip saved progress', () {
    final entry = TitleLogDraft(title());
    entry.toggle(6);
    entry.toggle(8);
    expect(entry.quantity, 2);
    expect(entry.projectedProgress, 6);
    entry.toggle(7);
    expect(entry.projectedProgress, 8);
    entry.toggle(6);
    expect(entry.projectedProgress, 5);
  });

  test('switches methods without deleting timestamps', () {
    final entry = TitleLogDraft(title());
    entry.setQuantity(3);
    final previous = entry.selected[7];
    entry.method = LoggingMethod.lastUnit;
    entry.setLast(9);
    entry.method = LoggingMethod.perUnit;
    expect(entry.selected[7], previous);
    expect(entry.quantity, 4);
  });

  test('repeats never increase saved Library progress', () {
    final entry = TitleLogDraft(title(progress: 12));
    entry.repeat = true;
    expect(entry.base, 0);
    entry.setQuantity(10);
    expect(entry.projectedProgress, 12);
  });

  test('review payload contains no account credentials or write intent', () {
    final entry = TitleLogDraft(title())..setQuantity(2);
    final json = entry.review();
    expect(json['libraryId'], 'title-1');
    expect(json['quantity'], 2);
    expect(json.containsKey('state_data'), isFalse);
  });
}
