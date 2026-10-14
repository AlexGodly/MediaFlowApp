import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_itemized_parity.dart';
import 'package:mediaflow_app/services/native_editing_workspace.dart';
import 'package:mediaflow_app/services/native_offline_projection_codec.dart';
import 'package:mediaflow_app/features/logging/native_itemized_draft_sheet.dart';

MediaFlowTitle title({bool duplicateIds = false,
    bool complete = false, bool noIds = false}) =>
    MediaFlowTitle.fromJson({
      'id': 't1', 'title': 'Example Title', 'categoryId': 'anime',
      'status': complete ? 'completed' : 'active',
      'priority': 'medium',
      'progress': complete ? 20 : 8, 'total': 20,
      'seasons': [
        {'id': noIds ? '' : 's1', 'name': 'Season One',
         'number': 1, 'progress': complete ? 10 : 3, 'total': 10},
        {'id': duplicateIds ? 's1' : noIds ? '' : 's2',
         'name': 'Season Two', 'number': 2,
         'progress': complete ? 10 : 5, 'total': 10},
      ],
    });

MediaFlowSession historic(String id, int number,
    {String season = 's1', bool repeat = false}) =>
    MediaFlowSession.fromJson({
      'id': id, 'date': '2026-10-13', 'status': 'logged',
      'xp': 20, 'titles': [{
        'libraryId': 't1', 'title': 'Example Title',
        'qty': 1, 'repeat': false,
        'v369Units': [{
          'id': 'unit-$id', 'number': number,
          'seasonId': season, 'durationSeconds': 123,
          'isRepeat': repeat, 'loggedAt': 1791892800000,
        }],
      }],
    });

MediaFlowCatalog catalog(MediaFlowTitle item,
    {List<MediaFlowSession> sessions = const []}) =>
    MediaFlowCatalog(library: [item], categories: const [],
      sessions: sessions, updatedAt: DateTime.utc(2026, 10, 14));

void main() {
  test('v252 stable season IDs survive native typed projection', () {
    final item = title();
    expect(item.seasons.map((s) => s.id).toList(), ['s1', 's2']);
    expect(item.seasons[1].number, 2);
    expect(item.seasons[1].progress, 5);
  });

  test('v369 exact contiguous progress stops at missing episode', () {
    final result = NativeItemizedParity.calculate(
      title: title(), sessions: const [], seasonId: 's1',
      numbers: [4, 6], secondsPerUnit: 1200,
    );
    expect(result.consumed, 2);
    expect(result.afterSeasonProgress, 4);
    expect(result.beforeTitleProgress, 8);
    expect(result.afterTitleProgress, 9);
    expect(result.elapsedSeconds, 2400);
    expect(result.exactXp, null);
    expect(result.cloudWritable, false);
    expect(result.historyWritable, false);
  });

  test('archived v369 unit can close gap without double counting', () {
    final result = NativeItemizedParity.calculate(
      title: title(), sessions: [historic('previous', 5)],
      seasonId: 's1', numbers: [4, 6], secondsPerUnit: 900,
    );
    expect(result.afterSeasonProgress, 6);
    expect(result.afterTitleProgress, 11);
    expect(result.knownArchivedUnitCount, 1);
    expect(result.consumed, 2);
    expect(result.elapsedSeconds, 1800);
  });

  test('archived v369 repeat unit does not advance progress', () {
    final result = NativeItemizedParity.calculate(
      title: title(), sessions: [historic('repeat', 5, repeat: true)],
      seasonId: 's1', numbers: [4, 6], secondsPerUnit: 0,
    );
    expect(result.afterSeasonProgress, 4);
  });

  test('season ownership preserves unrelated season progress', () {
    final result = NativeItemizedParity.calculate(
      title: title(), sessions: [historic('other', 7, season: 's2')],
      seasonId: 's1', numbers: [4, 5], secondsPerUnit: 1200,
    );
    expect(result.afterSeasonProgress, 5);
    expect(result.afterTitleProgress, 10);
  });

  test('completed title repeat preserves both season and aggregate', () {
    final item = title(complete: true);
    final result = NativeItemizedParity.calculate(
      title: item, sessions: const [], seasonId: 's2',
      numbers: [1, 2, 3], secondsPerUnit: 60, repeat: true,
    );
    expect(result.consumed, 3);
    expect(result.afterSeasonProgress, 10);
    expect(result.afterTitleProgress, 20);
    expect(result.completionCandidate, false);
    expect(item.progress, 20);
  });

  test('strict inputs reject missing/duplicated IDs, bad totals, old units', () {
    void stage(MediaFlowTitle item, String id, List<int> units,
        {bool repeat = false}) => NativeItemizedParity.calculate(
      title: item, sessions: const [], seasonId: id,
      numbers: units, secondsPerUnit: 5, repeat: repeat,
    );
    expect(() => stage(title(noIds: true), 's1', [4]),
        throwsFormatException);
    expect(() => stage(title(duplicateIds: true), 's1', [4]),
        throwsFormatException);
    expect(() => stage(title(), 'wrong', [4]), throwsFormatException);
    expect(() => stage(title(), 's1', [3]), throwsFormatException);
    expect(() => stage(title(), 's1', [4, 4]), throwsFormatException);
    expect(() => stage(title(), 's1', [11]), throwsFormatException);
    expect(() => stage(title(), 's1', [4], repeat: true),
        throwsFormatException);
  });

  test('archived unit missing season ID quarantines projection', () {
    expect(() => NativeItemizedParity.calculate(
      title: title(), sessions: [historic('unknown', 5, season: '')],
      seasonId: 's1', numbers: [4], secondsPerUnit: 1,
    ), throwsFormatException);
  });

  test('lossy device cache retains safe evidence but is not cloud state', () {
    final item = title();
    final source = catalog(item, sessions: [historic('a', 5)]);
    final projection = NativeOfflineProjectionCodec.encode(source);
    final restored = NativeOfflineProjectionCodec.decode(projection);
    expect(restored.library.first.seasons.first.id, 's1');
    final u = restored.sessions.first.titles.first.units.first;
    expect(u.number, 5);
    expect(u.seasonId, 's1');
    expect(u.durationSeconds, 123);
    expect(u.loggedAt, isNotNull);
    expect(projection['format'], NativeOfflineProjectionCodec.format);
    expect(NativeCloudCapabilities.cloudWritesEnabled, false);
  });

  test('signed-in workspace isolates itemized drafts and blocks collisions',
      () {
    final data = catalog(title());
    final a = NativeEditingWorkspace(ownerId: 'a')..observe(data);
    final b = NativeEditingWorkspace(ownerId: 'b')..observe(data);
    a.stageItemizedLog(catalog: data, titleId: 't1', seasonId: 's1',
        numbers: [4, 5], secondsPerUnit: 60);
    expect(a.itemizedCount, 1);
    expect(a.pendingHistoryEntries, 1);
    expect(a.xpAwarded, 0);
    expect(b.itemizedCount, 0);
    expect(() => a.stageLog(catalog: data, titleId: 't1',
        amount: 1, minutes: 1, note: ''), throwsFormatException);
    final replacement = catalog(title());
    a.observe(replacement);
    expect(a.stale, true);
    a.discardAll();
    expect(a.hasDrafts, false);
    a.dispose();
    b.dispose();
  });

  test('100000 synthetic archived sessions remain read-only', () {
    final records = [
      for (var i = 0; i < 100000; i++)
        i == 99999 ? historic('last', 5) :
            MediaFlowSession.fromJson({'id': '$i', 'titles': const []}),
    ];
    final clock = Stopwatch()..start();
    final result = NativeItemizedParity.calculate(
      title: title(), sessions: records, seasonId: 's1',
      numbers: [4, 6], secondsPerUnit: 60,
    );
    expect(result.afterSeasonProgress, 6);
    expect(records.last.xp, 20);
    // ignore: avoid_print
    print('M22_ITEMIZED_100K_MS=${clock.elapsedMilliseconds}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('native season editor previews and stages only RAM draft',
      (tester) async {
    final item = title();
    final data = catalog(item);
    final w = NativeEditingWorkspace(ownerId: 'a')..observe(data);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(
        child: NativeItemizedDraftSheet(
          catalog: data, title: item, workspace: w,
        ),
      ),
    )));
    expect(find.byKey(const Key('itemized-season-selector')), findsOneWidget);
    expect(find.byKey(const Key('itemized-unit-numbers')), findsOneWidget);
    expect(find.textContaining('History submitted: 0'), findsOneWidget);
    await tester.ensureVisible(find.text('Keep local itemized draft'));
    await tester.tap(find.text('Keep local itemized draft'));
    await tester.pump();
    expect(w.itemizedCount, 1);
    expect(item.progress, 8);
    w.dispose();
  });
}
