import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/features/logging/native_m53_completion_evidence_panel.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m30_shared_sync.dart';
import 'package:mediaflow_app/services/native_editing_workspace.dart';
import 'package:mediaflow_app/services/native_logging_parity_preview.dart';
import 'package:mediaflow_app/services/native_m51_task_handoff.dart';
import 'package:mediaflow_app/services/native_m52_task_draft_context.dart';
import 'package:mediaflow_app/services/native_m53_task_completion_evidence.dart';
import 'package:mediaflow_app/services/native_m54_transaction_readiness_audit.dart';

Map<String, dynamic> snapshot54({
  bool foreign = false,
  bool collection = false,
  bool traversed = false,
  int extra = 0,
}) => {
  'categories': [
    {'id': 'anime', 'name': 'Anime'},
    {'id': 'books', 'name': 'Books'},
  ],
  'library': [
    {'id': 'one', 'title': 'Episode One',
     'categoryId': foreign ? 'books' : 'anime',
     'status': 'active', 'progress': 2, 'total': 12},
    for (var i = 0; i < extra; i++)
      {'id': 'extra$i', 'title': 'Extra $i',
       'categoryId': 'anime', 'status': 'active',
       'progress': 0, 'total': 12},
  ],
  'sessions': <dynamic>[],
  'collections': collection ? [
    {'id': 'col', 'title': 'Episodes', 'titleIds': ['one']}
  ] : <dynamic>[],
  'orderPlan': {
    'collectionAssignments': collection ? [
      {'id': 'assign', 'collectionId': 'col', 'categoryId': 'anime',
       'traversedTitleIds': traversed ? ['one'] : <String>[]}
    ] : <dynamic>[],
  },
  'sessionActive': true,
  'currentTask': {
    'categoryId': 'anime', 'libraryId': 'one',
    'title': 'Episode One', 'low': 2, 'high': 4,
    'unit': 'episodes',
    if (collection) 'v287OrderSource': {
      'type': 'collection', 'categoryId': 'anime',
      'libraryId': 'one', 'assignmentId': 'assign',
    },
  },
};

NativeM52TaskDraftContext token54(MediaFlowCatalog data) {
  final handoff = NativeM51TaskHandoff(ownerId: 'account');
  handoff.request(data, currentOwnerId: 'account');
  final result = NativeM52TaskDraftContext.fromHandoff(
    handoff: handoff.inspect(data, currentOwnerId: 'account'),
    catalog: data, currentOwnerId: 'account');
  handoff.dispose();
  return result;
}

NativeM54TransactionAudit inspect54(
  MediaFlowCatalog data,
  NativeM52TaskDraftContext token, {
  NativeEditingWorkspace? workspace,
  String owner = 'account',
  NativeLoggingPreview? preview,
}) {
  final context = token.inspect(
    catalog: data, currentOwnerId: owner,
    forTitleId: 'one', workspace: workspace);
  final evidence = NativeM53TaskCompletionEvidence.evaluate(
    context: context, catalog: data, titleId: 'one',
    standardPreview: preview);
  return NativeM54TransactionAudit.inspect(
    catalog: data, titleId: 'one', evidence: evidence);
}

void main() {
  test('all ten v410 side-effect prerequisites are accounted for', () {
    final data = decodeMediaFlowState(snapshot54());
    final workspace = NativeEditingWorkspace(ownerId: 'account')
      ..observe(data);
    addTearDown(workspace.dispose);
    workspace.stageLog(catalog: data, titleId: 'one',
      amount: 3, minutes: 30, note: 'test only');
    final draftBefore = workspace.logDraft('one');
    final report = inspect54(data, token54(data), workspace: workspace);
    expect(report.status, NativeM54AuditStatus.evidenceOnly);
    expect(report.indicativeQuantity, 3);
    expect(report.assignedCategoryId, 'anime');
    expect(report.actualCategoryId, 'anime');
    expect(report.mightSkipRecommendation, false);
    expect(report.checks.length, NativeM54Prerequisite.values.length);
    expect(report.verifiedReadOnlyCount, 1);
    expect(report.blockedCount, 9);
    expect(report.checks.map((e) => e.id).toSet(),
      NativeM54Prerequisite.values.toSet());
    expect(report.checks.first.satisfied, true);
    expect(report.checks.last.satisfied, false);
    expect(report.canCommit, false);
    expect(report.readyForProduction, false);
    expect(report.confirmedTaskCompleted, false);
    expect(data.sessions, isEmpty);
    expect(data.library.first.progress, 2);
    expect(workspace.logDraft('one'), same(draftBefore));
    expect(NativeCloudCapabilities.cloudWritesEnabled, false);
    expect(NativeCloudCapabilities.hasServerSideCas, false);
    expect(NativeM30Protocol.deployed, false);
  });

  test('no local consumption is not misreported as a valid transaction', () {
    final data = decodeMediaFlowState(snapshot54());
    final report = inspect54(data, token54(data));
    expect(report.status, NativeM54AuditStatus.noConsumption);
    expect(report.indicativeQuantity, isNull);
    expect(report.blockedCount, 9);
    expect(report.canCommit, false);
  });

  test('account changes, snapshot replacements and duplicate IDs block audit', () {
    final data = decodeMediaFlowState(snapshot54());
    final token = token54(data);
    expect(inspect54(data, token, owner: 'another').status,
      NativeM54AuditStatus.invalidContext);
    final refreshed = decodeMediaFlowState(snapshot54());
    expect(inspect54(refreshed, token).status,
      NativeM54AuditStatus.invalidContext);
    final input = snapshot54();
    (input['library'] as List).add(
      {'id': 'one', 'title': 'Duplicate', 'categoryId': 'anime'});
    final duplicate = decodeMediaFlowState(input);
    final manualEvidence = NativeM53TaskCompletionEvidence.evaluate(
      context: NativeM52ContextView(
        status: NativeM52ContextStatus.ready, message: 'synthetic',
        taskUnit: 'episodes', low: 2, high: 4),
      catalog: duplicate, titleId: 'one');
    final audit = NativeM54TransactionAudit.inspect(
      catalog: duplicate, titleId: 'one', evidence: manualEvidence);
    expect(audit.status, NativeM54AuditStatus.invalidContext);
    expect(audit.canCommit, false);
  });

  test('Force Queue foreign category predicts only possible skipped row', () {
    final data = decodeMediaFlowState(snapshot54(foreign: true));
    final workspace = NativeEditingWorkspace(ownerId: 'account')
      ..observe(data);
    addTearDown(workspace.dispose);
    workspace.stageLog(catalog: data, titleId: 'one',
      amount: 3, minutes: 25, note: '');
    final report = inspect54(data, token54(data), workspace: workspace);
    expect(report.status, NativeM54AuditStatus.categoryMismatch);
    expect(report.actualCategoryId, 'books');
    expect(report.assignedCategoryId, 'anime');
    expect(report.mightSkipRecommendation, true);
    expect(report.checks[3].finding, contains('skipped'));
    expect(data.sessions, isEmpty);
  });

  test('Collection source membership and traversed status are review-only', () {
    final data = decodeMediaFlowState(snapshot54(collection: true));
    final workspace = NativeEditingWorkspace(ownerId: 'account')
      ..observe(data);
    addTearDown(workspace.dispose);
    workspace.stageLog(catalog: data, titleId: 'one',
      amount: 2, minutes: 25, note: '');
    final report = inspect54(data, token54(data), workspace: workspace);
    expect(report.collectionSourceFinding,
      contains('Unique saved Collection membership'));
    expect(report.checks[7].satisfied, false);
    expect(data.collectionAssignments.single.traversedTitleIds, isEmpty);
    final traversed = decodeMediaFlowState(
      snapshot54(collection: true, traversed: true));
    final other = inspect54(traversed, token54(traversed));
    expect(other.collectionSourceFinding, contains('already traversed'));
    expect(traversed.collectionAssignments.single.traversedTitleIds,
      ['one']);
    expect(other.canCommit, false);
  });

  test('repeat consumption never implies Library progress or awards', () {
    final state = snapshot54();
    (state['library'] as List).first['progress'] = 12;
    (state['library'] as List).first['status'] = 'completed';
    final data = decodeMediaFlowState(state);
    final preview = NativeLoggingParityPreview.calculate(
      title: data.library.first, existingSessions: data.sessions,
      mode: NativeLogInputMode.amount, value: 3, minutes: 30,
      note: 'rewatch', repeat: true);
    final report = inspect54(data, token54(data), preview: preview);
    expect(report.status, NativeM54AuditStatus.evidenceOnly);
    expect(report.checks[6].finding, contains('Repeat units'));
    expect(report.checks[5].satisfied, false);
    expect(data.library.first.progress, 12);
    expect(data.sessions, isEmpty);
  });

  test('100k Library audit retains input and cannot construct a commit', () {
    final data = decodeMediaFlowState(snapshot54(extra: 99999));
    expect(data.library.length, 100000);
    final workspace = NativeEditingWorkspace(ownerId: 'account')
      ..observe(data);
    addTearDown(workspace.dispose);
    workspace.stageLog(catalog: data, titleId: 'one',
      amount: 3, minutes: 20, note: '');
    final report = inspect54(data, token54(data), workspace: workspace);
    expect(report.blockedCount, greaterThan(0));
    expect(report.readyForProduction, false);
    expect(data.library.length, 100000);
    expect(data.sessions, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('Logging presents expandable blocker audit without save action',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = decodeMediaFlowState(snapshot54());
    final token = token54(data);
    final workspace = NativeEditingWorkspace(ownerId: 'account')
      ..observe(data);
    addTearDown(workspace.dispose);
    workspace.stageLog(catalog: data, titleId: 'one',
      amount: 3, minutes: 20, note: '');
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(
        child: NativeM53CompletionEvidencePanel(
          taskContext: token, catalog: data, titleId: 'one',
          currentOwnerId: 'account', workspace: workspace)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m54-readiness-saved')), findsOneWidget);
    expect(find.textContaining('9 of 10 prerequisites blocked'),
      findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('m54-readiness-saved')));
    await tester.tap(find.text('Transaction readiness · blocked'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m54-no-write-saved')), findsOneWidget);
    expect(find.textContaining('Authoritative completion threshold'),
      findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(data.sessions, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
