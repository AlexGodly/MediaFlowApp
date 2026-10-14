// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/features/library/native_editing_sheet.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_editing_workspace.dart';
import 'package:mediaflow_app/services/native_logging_parity_preview.dart';

MediaFlowTitle title({double progress = 3, double total = 12,
    String status = 'active', bool seasons = false}) =>
    MediaFlowTitle.fromJson({
      'id': 'anime-1', 'title': 'Original Title',
      'categoryId': 'anime', 'progress': progress, 'total': total,
      'status': status, 'priority': 'high',
      if (seasons) 'seasons': [
        {'name': 'Season 1', 'progress': 3, 'total': 12},
      ],
    });

MediaFlowSession session(String date, {String status = 'logged'}) =>
    MediaFlowSession.fromJson({
      'id': 'history-' + date, 'date': date, 'status': status,
      'xp': 50, 'actualAmount': 1,
    });

MediaFlowCatalog catalog(MediaFlowTitle item,
    {List<MediaFlowSession> sessions = const []}) => MediaFlowCatalog(
      library: [item], categories: const [], sessions: sessions,
      updatedAt: DateTime.utc(2026, 10, 14),
    );

void main() {
  test('v179 last-progress: current 3, input episode 7 consumes four', () {
    final original = title();
    final result = NativeLoggingParityPreview.calculate(
      title: original, existingSessions: const [],
      mode: NativeLogInputMode.lastProgress, value: 7,
      minutes: 45, note: 'final episode reached',
      date: DateTime.utc(2026, 10, 14),
    );
    expect(result.start, 3);
    expect(result.consumed, 4);
    expect(result.projectedLibraryProgress, 7);
    expect(result.projectedStatus, 'active');
    expect(result.historyProjection.quantity, 4);
    expect(result.historyProjection.minutes, 45);
    expect(result.historyProjection.date, '2026-10-14');
    expect(result.productionReady, false);
    expect(result.prospectiveXp, null);
    expect(original.progress, 3);
  });

  test('v179 input lower than progress has no consumption and is rejected', () {
    expect(() => NativeLoggingParityPreview.calculate(
      title: title(), existingSessions: const [],
      mode: NativeLogInputMode.lastProgress, value: 2,
      minutes: 5, note: '',
    ), throwsFormatException);
  });

  test('v179 clamps last progress to known total', () {
    final result = NativeLoggingParityPreview.calculate(
      title: title(), existingSessions: const [],
      mode: NativeLogInputMode.lastProgress, value: 40,
      minutes: 60, note: '',
    );
    expect(result.consumed, 9);
    expect(result.projectedLibraryProgress, 12);
    expect(result.wouldComplete, true);
    expect(result.projectedStatus, 'completed');
    expect(result.prospectiveXp, null);
  });

  test('v81 repeat preserves completed Library but counts History units', () {
    final original = title(progress: 12, status: 'completed');
    final result = NativeLoggingParityPreview.calculate(
      title: original, existingSessions: const [],
      mode: NativeLogInputMode.lastProgress, value: 5,
      minutes: 30, note: 'rewatch', repeat: true,
    );
    expect(result.start, 0);
    expect(result.consumed, 5);
    expect(result.projectedLibraryProgress, 12);
    expect(result.historyProjection.repeat, true);
    expect(result.wouldComplete, false);
    expect(original.progress, 12);
  });

  test('v120 completed check uses status or progress; not for active rewatch', () {
    expect(NativeLoggingParityPreview.isCompleted(
      title(progress: 12, status: 'active')), true);
    expect(NativeLoggingParityPreview.isCompleted(title()), false);
    expect(() => NativeLoggingParityPreview.calculate(
      title: title(), existingSessions: const [],
      mode: NativeLogInputMode.amount, value: 2,
      minutes: 10, note: '', repeat: true,
    ), throwsFormatException);
  });

  test('v149 streak day engine excludes skips, deduplicates same day', () {
    final days = [
      session('2026-10-10'), session('2026-10-11'),
      session('2026-10-11'), session('2026-10-12', status: 'skipped'),
      session('2026-10-13'),
    ];
    expect(NativeLoggingParityPreview.prospectiveStreak(
        days, '2026-10-12'), 3);
    expect(NativeLoggingParityPreview.prospectiveStreak(
        days, '2026-10-14'), 2);
    expect(NativeLoggingParityPreview.prospectiveStreak(
        days, '2026-10-15'), 1);
    expect(NativeLoggingParityPreview.streakMultiplier(1), 1);
    expect(NativeLoggingParityPreview.streakMultiplier(2), 1.10);
    expect(NativeLoggingParityPreview.streakMultiplier(7), 1.28);
    expect(NativeLoggingParityPreview.streakMultiplier(30), 1.49);
  });

  test('v369 contiguous progress stops at gap and ignores duplicate units', () {
    expect(NativeLoggingParityPreview.contiguousProgress(
      start: 3, unitNumbers: [4, 5, 7, 7, 9]), 5);
    expect(NativeLoggingParityPreview.contiguousProgress(
      start: 3, unitNumbers: [5, 4, 5, 6, 11], total: 6), 6);
    expect(NativeLoggingParityPreview.contiguousProgress(
      start: 4, unitNumbers: [2, 3, 5], total: 5), 5);
  });

  test('season aggregate and per-unit gaps cannot masquerade as safe log', () {
    expect(() => NativeLoggingParityPreview.calculate(
      title: title(seasons: true), existingSessions: const [],
      mode: NativeLogInputMode.amount, value: 1, minutes: 15, note: '',
    ), throwsFormatException);
  });

  test('M20 shared workspace persists nonuploadable last-progress plan', () {
    final data = catalog(title(), sessions: [session('2026-10-13')]);
    final workspace = NativeEditingWorkspace(ownerId: 'owner')..observe(data);
    workspace.stageLog(catalog: data, titleId: 'anime-1',
      amount: 7, minutes: 35, note: 'episode seven',
      mode: NativeLogInputMode.lastProgress,
      date: DateTime.utc(2026, 10, 14),
    );
    final draft = workspace.logDraft('anime-1')!;
    expect(draft.units, 4);
    expect(draft.projectedProgress, 7);
    expect(draft.prospectiveStreak, 2);
    expect(draft.indicativeStreakMultiplier, 1.10);
    expect(draft.hypotheticalXp, null);
    expect(workspace.xpAwarded, 0);
    expect(data.sessions.single.xp, 50);
    expect(NativeCloudCapabilities.cloudWritesEnabled, false);
    workspace.dispose();
  });

  test('100000 synthetic History rows do not mutate any real session', () {
    final records = [
      for (var i = 0; i < 100000; i++)
        session(i.isEven ? '2026-10-12' : '2026-10-13'),
    ];
    final timer = Stopwatch()..start();
    final streak = NativeLoggingParityPreview.prospectiveStreak(
      records, '2026-10-14',
    );
    expect(streak, 3);
    expect(records.length, 100000);
    expect(records.first.xp, 50);
    // Synthetic CI telemetry only, not device benchmarks.
    // ignore: avoid_print
    print('M21_HISTORY_100K_STREAK_MS=' + timer.elapsedMilliseconds.toString());
  }, timeout: const Timeout(Duration(minutes: 2)));
  testWidgets('native log form exposes mode and no-XP hypothetical panel',
      (tester) async {
    final original = title();
    final data = catalog(original);
    final workspace = NativeEditingWorkspace(ownerId: 'user')..observe(data);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: NativeLogDraftSheet(
        catalog: data, title: original, workspace: workspace,
      )),
    )));
    expect(find.byKey(const Key('native-log-mode')), findsOneWidget);
    expect(find.byKey(const Key('native-repeat-consumption')), findsOneWidget);
    expect(find.textContaining('Hypothetical History / XP'), findsOneWidget);
    expect(find.textContaining('Exact XP unavailable'), findsOneWidget);
    expect(workspace.logCount, 0);
    workspace.dispose();
  });
}