import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/logging/logging_screen.dart';
import 'package:mediaflow_app/features/logging/native_itemized_draft_sheet.dart';
import 'package:mediaflow_app/features/library/native_editing_sheet.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_editing_workspace.dart';
import 'package:mediaflow_app/services/native_logging_parity_preview.dart';
import 'package:mediaflow_app/services/native_m51_task_handoff.dart';
import 'package:mediaflow_app/services/native_m52_task_draft_context.dart';

Map<String,dynamic> fixture52({String taskId='a',
  bool seasons=false, int extra=0}) => {
  'categories':[{'id':'anime','name':'Anime'}],
  'library':[
    {'id':'a','title':'Alpha','categoryId':'anime',
      'status':'active','priority':'high',
      'progress':seasons?3:2,'total':seasons?10:12,
      'seasons':seasons?[
        {'id':'s1','name':'Season One','progress':2,'total':5},
        {'id':'s2','name':'Season Two','progress':1,'total':5},
      ]:<Object>[]},
    {'id':'b','title':'Beta','categoryId':'anime',
      'status':'active','priority':'medium','progress':0,'total':12},
    for(var i=0;i<extra;i++)
      {'id':'extra$i','title':'Extra $i','categoryId':'anime',
        'status':'active','progress':0,'total':10},
  ],
  'sessionActive':true,
  'currentTask':{
    'categoryId':'anime','libraryId':taskId,
    'title':'Exact saved recommendation','low':2,'high':4,
    'unit':seasons?'episodes':'units',
  },
};

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.catalog);
  final MediaFlowCatalog catalog;
  @override
  Future<MediaFlowCatalog> load() async=>catalog;
}

NativeM52TaskDraftContext contextFor(MediaFlowCatalog source,{
  String owner='owner'}) {
  final handoff=NativeM51TaskHandoff(ownerId:owner);
  handoff.request(source,currentOwnerId:owner);
  final v=handoff.inspect(source,currentOwnerId:owner);
  final ctx=NativeM52TaskDraftContext.fromHandoff(
    handoff:v,catalog:source,currentOwnerId:owner);
  handoff.dispose();
  return ctx;
}

void main(){
  test('exact owner/snapshot/title and current task are checked each time',(){
    final source=decodeMediaFlowState(fixture52());
    final token=contextFor(source);
    expect(token.inspect(catalog:source,currentOwnerId:'owner',
      forTitleId:'a').ready,true);
    expect(token.inspect(catalog:source,currentOwnerId:'wrong',
      forTitleId:'a').status,NativeM52ContextStatus.wrongOwner);
    expect(token.inspect(catalog:decodeMediaFlowState(fixture52()),
      currentOwnerId:'owner',forTitleId:'a').status,
      NativeM52ContextStatus.replacedSnapshot);
    expect(token.inspect(catalog:source,currentOwnerId:'owner',
      forTitleId:'b').status,NativeM52ContextStatus.differentTitle);
    expect(source.sessions,isEmpty);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('invalid source or title fails closed before token creation',(){
    final source=decodeMediaFlowState(fixture52());
    final handoff=NativeM51TaskHandoff(ownerId:'owner');
    addTearDown(handoff.dispose);
    expect(()=>NativeM52TaskDraftContext.fromHandoff(
      handoff:handoff.inspect(source,currentOwnerId:'owner'),
      catalog:source,currentOwnerId:'owner'),throwsStateError);
    handoff.request(source,currentOwnerId:'owner');
    final ready=handoff.inspect(source,currentOwnerId:'owner');
    expect(()=>NativeM52TaskDraftContext.fromHandoff(
      handoff:ready,catalog:source,currentOwnerId:''),throwsStateError);
    final other=decodeMediaFlowState(fixture52(taskId:'b'));
    expect(()=>NativeM52TaskDraftContext.fromHandoff(
      handoff:ready,catalog:other,currentOwnerId:'owner'),throwsStateError);
  });

  test('standard draft amount, method, timestamp and note survive task context',(){
    final source=decodeMediaFlowState(fixture52());
    final w=NativeEditingWorkspace(ownerId:'owner');
    addTearDown(w.dispose);
    w.observe(source);
    w.stageLog(catalog:source,titleId:'a',amount:3,
      minutes:44,note:'keep this note',
      mode:NativeLogInputMode.amount,
      date:DateTime.utc(2026,10,14,15,30));
    final previous=w.logDraft('a')!;
    final ctx=contextFor(source);
    final view=ctx.inspect(catalog:source,currentOwnerId:'owner',
      forTitleId:'a',workspace:w);
    expect(view.ready,true);
    expect(view.standard,same(previous));
    expect(view.itemized,isNull);
    expect(view.draftSummary,contains('3.0 consumed'));
    expect(w.logDraft('a'),same(previous));
    expect(w.logDraft('a')!.hypotheticalDate,previous.hypotheticalDate);
    expect(previous.note,'keep this note');
    expect(previous.minutes,44);
    expect(source.library.first.progress,2);
    expect(source.sessions,isEmpty);
    expect(w.xpAwarded,0);
  });

  test('itemized draft keeps exact seasons, unit numbers, runtime and repetition',(){
    final source=decodeMediaFlowState(fixture52(seasons:true));
    final w=NativeEditingWorkspace(ownerId:'owner');
    addTearDown(w.dispose);
    w.observe(source);
    w.stageItemizedLog(catalog:source,titleId:'a',
      seasonId:'s1',numbers:[3,4],secondsPerUnit:1500);
    final existing=w.itemizedDraft('a')!;
    final ctx=contextFor(source);
    final view=ctx.inspect(catalog:source,currentOwnerId:'owner',
      forTitleId:'a',workspace:w);
    expect(view.ready,true);
    expect(view.itemized,same(existing));
    expect(view.standard,isNull);
    expect(existing.seasonId,'s1');
    expect(existing.unitNumbers,[3,4]);
    expect(existing.elapsedSeconds,3000);
    expect(existing.beforeTitleProgress,3);
    expect(existing.afterTitleProgress,5);
    expect(source.library.first.progress,3);
    expect(source.library.first.seasons.first.progress,2);
    expect(source.sessions,isEmpty);
  });

  test('owner and stale workspaces never export draft details to other context',(){
    final source=decodeMediaFlowState(fixture52());
    final ctx=contextFor(source);
    final wrong=NativeEditingWorkspace(ownerId:'other');
    addTearDown(wrong.dispose);
    wrong.observe(source);
    expect(ctx.inspect(catalog:source,currentOwnerId:'owner',
      forTitleId:'a',workspace:wrong).status,
      NativeM52ContextStatus.workspaceMismatch);
    final w=NativeEditingWorkspace(ownerId:'owner');
    addTearDown(w.dispose);
    w.observe(source);
    w.stageLog(catalog:source,titleId:'a',amount:1,
      minutes:20,note:'keep');
    final existing=w.logDraft('a');
    w.observe(decodeMediaFlowState(fixture52()));
    final invalid=ctx.inspect(catalog:source,currentOwnerId:'owner',
      forTitleId:'a',workspace:w);
    expect(invalid.ready,false);
    expect(invalid.standard,isNull);
    expect(w.logDraft('a'),same(existing));
    expect(w.stale,true);
  });

  test('100k Library: token reuses exact snapshot and does not clone/mutate',(){
    final source=decodeMediaFlowState(fixture52(extra:99998));
    expect(source.library.length,100000);
    final token=contextFor(source);
    expect(identical(token.source,source),true);
    final v=token.inspect(catalog:source,currentOwnerId:'owner',
      forTitleId:'a');
    expect(v.ready,true);
    expect(v.hasExistingDraft,false);
    expect(source.sessions,isEmpty);
    expect(source.library.first.progress,2);
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('both logging sheets display same task target without prefill',(
      tester)async{
    tester.view.physicalSize=const Size(400,920);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source=decodeMediaFlowState(fixture52(seasons:true));
    final token=contextFor(source);
    final w=NativeEditingWorkspace(ownerId:'owner');
    addTearDown(w.dispose);
    w.observe(source);
    final title=source.library.first;
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeLogDraftSheet(catalog:source,title:title,
        workspace:w,taskContext:token,currentOwnerId:'owner'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m52-context-panel')),findsOneWidget);
    expect(find.textContaining('2–4 episodes'),findsOneWidget);
    expect(find.textContaining('No existing local draft'),findsOneWidget);
    expect(tester.widget<TextField>(
      find.byKey(const Key('native-log-draft-units')))
      .controller!.text,'1');
    expect(w.logCount,0);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeItemizedDraftSheet(catalog:source,title:title,
        workspace:w,taskContext:token,currentOwnerId:'owner'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m52-context-panel')),findsOneWidget);
    expect(find.textContaining('2–4 episodes'),findsOneWidget);
    expect(tester.widget<TextField>(
      find.byKey(const Key('itemized-unit-numbers')))
      .controller!.text,'3');
    expect(w.logCount,0);
    expect(source.sessions,isEmpty);
    expect(tester.takeException(),isNull);
  });

  testWidgets('existing season draft is preserved in itemized sheet',(
      tester)async{
    tester.view.physicalSize=const Size(420,880);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source=decodeMediaFlowState(fixture52(seasons:true));
    final token=contextFor(source);
    final w=NativeEditingWorkspace(ownerId:'owner');
    addTearDown(w.dispose);
    w.observe(source);
    w.stageItemizedLog(catalog:source,titleId:'a',seasonId:'s2',
      numbers:[2,3],secondsPerUnit:800);
    final original=w.itemizedDraft('a');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeItemizedDraftSheet(
        catalog:source,title:source.library.first,
        workspace:w,taskContext:token,currentOwnerId:'owner'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m52-existing-season')),findsOneWidget);
    expect(find.textContaining('Season Two'),findsWidgets);
    expect(tester.widget<TextField>(
      find.byKey(const Key('itemized-unit-numbers')))
      .controller!.text,'2, 3');
    expect(tester.widget<TextField>(
      find.byKey(const Key('itemized-seconds-per-unit')))
      .controller!.text,'800');
    expect(w.itemizedDraft('a'),same(original));
    expect(tester.takeException(),isNull);
  });

  testWidgets('Logging keeps task context after one-shot handoff is dismissed',(
      tester)async{
    tester.view.physicalSize=const Size(320,800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source=decodeMediaFlowState(fixture52());
    final handoff=NativeM51TaskHandoff(ownerId:'owner');
    addTearDown(handoff.dispose);
    handoff.request(source,currentOwnerId:'owner');
    final workspace=NativeEditingWorkspace(ownerId:'owner');
    addTearDown(workspace.dispose);
    workspace.observe(source);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:LoggingScreen(
      repository:_Repo(source),workspace:workspace,
      currentOwnerId:'owner',taskHandoff:handoff))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m51-handoff-card')),findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('m51-review-task-title')));
    await tester.tap(find.byKey(const Key('m51-review-task-title')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m52-details-context')),findsOneWidget);
    expect(handoff.hasRequest,false);
    expect(workspace.logCount,0);
    Navigator.of(tester.element(find.byKey(
      const Key('m52-details-context')))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m52-logging-context-card')),findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('m52-reopen-task-review')));
    await tester.tap(find.byKey(const Key('m52-reopen-task-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m52-details-context')),findsOneWidget);
    expect(workspace.logCount,0);
    expect(source.sessions,isEmpty);
    expect(tester.takeException(),isNull);
  });
}
