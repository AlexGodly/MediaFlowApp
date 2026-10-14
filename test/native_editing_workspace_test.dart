import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/features/library/native_editing_sheet.dart';
import 'package:mediaflow_app/features/settings/native_editing_review_panel.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_editing_workspace.dart';

MediaFlowCatalog sample({bool seasons = false, int count = 1}) =>
    MediaFlowCatalog(
      categories: [MediaFlowCategory.fromJson({
        'id': 'anime', 'name': 'Anime',
      })],
      library: [
        for (var i = 0; i < count; i++)
          MediaFlowTitle.fromJson({
            'id': 't-$i', 'title': 'Title $i', 'categoryId': 'anime',
            'status': 'active', 'priority': 'medium',
            'progress': 3, 'total': 12, 'rating': 7.5,
            'seasons': seasons
                ? [{'name': 'Season 1', 'progress': 3, 'total': 12}]
                : <Object>[],
          }),
      ],
      sessions: [
        MediaFlowSession.fromJson({
          'id': 'original-session', 'date': '2026-10-13',
          'xp': 250, 'minutes': 35,
        }),
      ],
      updatedAt: DateTime.utc(2026, 10, 14),
    );

void main() {
  test('title draft stays in memory and does not mutate original account', () {
    final source = sample();
    final w = NativeEditingWorkspace(ownerId: 'one')..observe(source);
    w.stageTitle(catalog: source, titleId: 't-0', priority: 'high',
        status: 'completed', progress: 10, rating: 9);
    expect(w.titleCount, 1);
    expect(w.titleDraft('t-0')?.statusSideEffectsUnverified, true);
    expect(source.library.single.status, 'active');
    expect(source.library.single.progress, 3);
    expect(source.sessions.single.xp, 250);
    expect(w.xpAwarded, 0);
    expect(NativeCloudCapabilities.cloudWritesEnabled, false);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, false);
    w.dispose();
  });

  test('invalid progress, rating, status and season aggregate edits block', () {
    final source = sample();
    final w = NativeEditingWorkspace(ownerId: 'one')..observe(source);
    void propose(String priority, double progress, double? rating) =>
        w.stageTitle(catalog: source, titleId: 't-0',
            priority: priority, status: 'active',
            progress: progress, rating: rating);
    expect(() => propose('invalid', 3, 8), throwsFormatException);
    expect(() => propose('high', -1, 8), throwsFormatException);
    expect(() => propose('high', 13, 8), throwsFormatException);
    expect(() => propose('high', double.nan, 8), throwsFormatException);
    expect(() => propose('high', 3, 11), throwsFormatException);
    expect(() => propose('high', 3, double.infinity), throwsFormatException);
    expect(() => w.stageTitle(catalog: source, titleId: 'missing',
        priority: 'high', status: 'active', progress: 3, rating: 8),
        throwsStateError);
    expect(w.titleCount, 0);
    final seasonal = sample(seasons: true);
    w.observe(seasonal);
    expect(() => w.stageTitle(catalog: seasonal, titleId: 't-0',
        priority: 'high', status: 'active', progress: 6, rating: 8),
        throwsFormatException);
    w.dispose();
  });

  test('logging drafts preview units and runtime without History/XP', () {
    final source = sample();
    final w = NativeEditingWorkspace(ownerId: 'owner')..observe(source);
    w.stageLog(catalog: source, titleId: 't-0',
        amount: 2, minutes: 25, note: 'two chapters');
    expect(w.logDraft('t-0')?.projectedProgress, 5);
    expect(w.pendingHistoryEntries, 1);
    expect(w.xpAwarded, 0);
    expect(source.sessions.length, 1);
    expect(source.library.single.progress, 3);
    expect(() => w.stageLog(catalog: source, titleId: 't-0',
        amount: 15, minutes: 10, note: ''), throwsFormatException);
    expect(() => w.stageLog(catalog: source, titleId: 't-0',
        amount: 0, minutes: 10, note: ''), throwsFormatException);
    expect(() => w.stageLog(catalog: source, titleId: 't-0',
        amount: 1, minutes: -1, note: ''), throwsFormatException);
    expect(w.logCount, 1);
    w.discardLog('t-0');
    final seasonal = sample(seasons: true);
    w.observe(seasonal);
    expect(() => w.stageLog(catalog: seasonal, titleId: 't-0',
        amount: 1, minutes: 10, note: ''), throwsFormatException);
    w.dispose();
  });

  test('title draft and logging draft cannot create inconsistent progress', () {
    final source = sample();
    final w = NativeEditingWorkspace(ownerId: 'owner')..observe(source);
    w.stageTitle(catalog: source, titleId: 't-0',
        priority: 'high', status: 'active', progress: 7, rating: 7.5);
    w.stageLog(catalog: source, titleId: 't-0',
        amount: 2, minutes: 10, note: '');
    expect(w.logDraft('t-0')!.projectedProgress, 9);
    expect(() => w.stageTitle(catalog: source, titleId: 't-0',
        priority: 'high', status: 'active', progress: 8, rating: 7.5),
        throwsFormatException);
    w.discardTitle('t-0');
    expect(w.hasDrafts, false);
    w.dispose();
  });

  test('refresh quarantine retains drafts but blocks new staging', () {
    final initial = sample();
    final refreshed = sample();
    final w = NativeEditingWorkspace(ownerId: 'one')..observe(initial);
    w.stageTitle(catalog: initial, titleId: 't-0',
        priority: 'high', status: 'active', progress: 3, rating: 7.5);
    w.observe(refreshed);
    expect(w.stale, true);
    expect(w.titleCount, 1);
    expect(() => w.stageTitle(catalog: refreshed, titleId: 't-0',
        priority: 'low', status: 'active', progress: 3, rating: 7.5),
        throwsStateError);
    w.discardAll();
    w.observe(refreshed);
    expect(w.stale, false);
    w.dispose();
  });

  test('signed-in account workspaces never share drafts', () {
    final source = sample();
    final first = NativeEditingWorkspace(ownerId: 'first')..observe(source);
    final second = NativeEditingWorkspace(ownerId: 'second')..observe(source);
    first.stageLog(catalog: source, titleId: 't-0',
        amount: 1, minutes: 5, note: '');
    expect(second.logCount, 0);
    first.discardAll();
    expect(first.logCount, 0);
    first.dispose();
    second.dispose();
  });

  test('100000 titles can be referenced without cloning whole cloud', () {
    final watch = Stopwatch()..start();
    final source = sample(count: 100000);
    final w = NativeEditingWorkspace(ownerId: 'scale')..observe(source);
    w.stageTitle(catalog: source, titleId: 't-99999',
        priority: 'high', status: 'active', progress: 3, rating: 7.5);
    expect(w.titleCount, 1);
    expect(source.library.length, 100000);
    expect(source.library.last.priority, 'medium');
    // ignore: avoid_print
    print('M20_100K_LOCAL_DRAFT_MS=${watch.elapsedMilliseconds}');
    w.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('title form can keep draft without modifying source',
      (tester) async {
    final source = sample();
    final w = NativeEditingWorkspace(ownerId: 'owner')..observe(source);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: NativeTitleDraftSheet(
        catalog: source, title: source.library.single, workspace: w,
      )),
    )));
    await tester.enterText(
        find.byKey(const Key('native-title-draft-rating')), '9');
    await tester.ensureVisible(find.text('Keep local title draft'));
    await tester.tap(find.text('Keep local title draft'));
    await tester.pump();
    expect(w.titleDraft('t-0')?.rating, 9);
    expect(source.library.single.rating, 7.5);
    w.dispose();
  });

  testWidgets('review panel confirms discard and shows no XP',
      (tester) async {
    final source = sample();
    final w = NativeEditingWorkspace(ownerId: 'owner')..observe(source);
    w.stageLog(catalog: source, titleId: 't-0',
        amount: 2, minutes: 10, note: '');
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(
        child: NativeEditingReviewPanel(workspace: w),
      ),
    )));
    expect(find.textContaining('Logging drafts: 1'), findsOneWidget);
    await tester.tap(find.text('Discard all local drafts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard drafts'));
    await tester.pumpAndSettle();
    expect(w.hasDrafts, false);
    w.dispose();
  });
}
