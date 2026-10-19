import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/features/logging/r2_advanced_logging_drafts.dart';
import 'package:mediaflow_app/services/native_logging_draft_cloud_store.dart';

void main() {
  test('itemized timestamps, seasons, runtimes and notes roundtrip', () {
    final original = R2DraftTitle('title-mental')
      ..seasonId = 'season-1'
      ..note = 'Watching episode 4'
      ..isRepeat = true
      ..manualRuntime = true
      ..customTotalRuntimeSeconds = 9000
      ..runtimeMinutes = 48
      ..whenWatched = DateTime.utc(2026, 10, 19, 17, 30);
    original.currentUnits[4] = DateTime.utc(2026, 10, 19, 20, 10);
    original.currentUnits[6] = DateTime.utc(2026, 10, 19, 21, 11);
    original.setUnitSeconds(6, 3260);
    original.chooseMethod(R2LoggingMethod.lastUnit);
    final restored = R2DraftTitle.fromLocalReview(
      original.toLocalReview().cast<String, dynamic>());
    expect(restored.titleId, original.titleId);
    expect(restored.method, R2LoggingMethod.lastUnit);
    expect(restored.seasonId, 'season-1');
    expect(restored.note, 'Watching episode 4');
    expect(restored.isRepeat, true);
    expect(restored.quantity, 2);
    expect(restored.currentUnits[4], DateTime.utc(2026, 10, 19, 20, 10));
    expect(restored.currentUnits[6], DateTime.utc(2026, 10, 19, 21, 11));
    expect(restored.secondsForUnit(6), 3260);
    expect(restored.manualRuntime, true);
    expect(restored.effectiveRuntimeSeconds, 9000);
  });

  test('draft restore validates entire payload before changing local draft', () {
    final drafts = R2AdvancedLoggingDrafts();
    drafts.restoreFromCloud({
      'format': NativeLoggingDraftCloudStore.format,
      'keepTitles': false,
      'entries': [R2DraftTitle('valid-1').toLocalReview()],
    });
    expect(drafts.titleCount, 1);
    expect(drafts.keepTitles, false);

    final malicious = R2DraftTitle('malformed').toLocalReview();
    malicious['units'] = {'_whole_title': {'3': 'not-a-timestamp'}};
    expect(() => drafts.restoreFromCloud({
      'format': NativeLoggingDraftCloudStore.format,
      'keepTitles': true,
      'entries': [R2DraftTitle('other').toLocalReview(), malicious],
    }), throwsFormatException);
    expect(drafts.entries.single.titleId, 'valid-1');
    expect(drafts.keepTitles, false);
  });

  test('no ambiguous duplicate title IDs or orphan durations', () {
    final row = R2DraftTitle('title-1').toLocalReview();
    final drafts = R2AdvancedLoggingDrafts();
    expect(() => drafts.restoreFromCloud({
      'format': NativeLoggingDraftCloudStore.format,
      'keepTitles': true,
      'entries': [row, row],
    }), throwsFormatException);

    final invalid = R2DraftTitle('title-2').toLocalReview();
    invalid['unitDurations'] = {'other-season': {'1': 80}};
    expect(() => R2DraftTitle.fromLocalReview(
        invalid.cast<String, dynamic>()), throwsFormatException);
  });

  test('cloud payload guards format and size before transport', () {
    final drafts = R2AdvancedLoggingDrafts();
    final payload = drafts.toCloudPayload();
    NativeLoggingDraftCloudStore.validate(payload);
    expect(payload['entries'], isEmpty);
    expect(() => NativeLoggingDraftCloudStore.validate({
      ...payload, 'format': 'incorrect',
    }), throwsFormatException);
    expect(() => NativeLoggingDraftCloudStore.validate({
      ...payload, 'entries': List.generate(301, (_) => <String, dynamic>{}),
    }), throwsFormatException);
  });

  test('revision response is strict and account snapshot is immutable by copy', () {
    final response = NativeCloudLoggingDraft.fromRow({
      'revision': 9,
      'draft_data': R2AdvancedLoggingDrafts().toCloudPayload(),
      'updated_at': '2026-10-19T00:00:00Z',
    });
    expect(response.revision, 9);
    expect(response.updatedAt, DateTime.utc(2026, 10, 19));
    expect(() => NativeCloudLoggingDraft.fromRow({
      'revision': 0,
      'draft_data': R2AdvancedLoggingDrafts().toCloudPayload(),
    }), throwsFormatException);
  });
}
