import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/logging/native_m53_completion_evidence_panel.dart';
import 'package:mediaflow_app/features/logging/native_itemized_draft_sheet.dart';
import 'package:mediaflow_app/features/library/native_editing_sheet.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_editing_workspace.dart';
import 'package:mediaflow_app/services/native_itemized_parity.dart';
import 'package:mediaflow_app/services/native_logging_parity_preview.dart';
import 'package:mediaflow_app/services/native_m51_task_handoff.dart';
import 'package:mediaflow_app/services/native_m52_task_draft_context.dart';
import 'package:mediaflow_app/services/native_m53_task_completion_evidence.dart';

Map<String,dynamic> fixture53({
  double low=2,double high=4,String taskUnit='episodes',
  String titleCategory='anime',bool seasons=false,int extra=0,
}) => {
  'categories':[
    {'id':'anime','name':'Anime'},
    {'id':'books','name':'Books'},
  ],
  'library':[
    {'id':'a','title':'Alpha','categoryId':titleCategory,
      'status':'active','priority':'high',
      'progress':seasons?3:2,'total':seasons?10:12,
      if(seasons)'seasons':[
        {'id':'s1','name':'First Season','progress':2,'total':5},
        {'id':'s2','name':'Second Season','progress':1,'total':5},
      ]},
    for(var i=0;i<extra;i++)
      {'id':'x$i','title':'Synthetic $i','categoryId':'anime',
       'status':'active','progress':0,'total':12},
  ],
  'sessionActive':true,
  'currentTask':{
    'categoryId':'anime','libraryId':'a',
    'title':'Saved task title','low':low,'high':high,'unit':taskUnit,
  },
};

NativeM52TaskDraftContext token(MediaFlowCatalog catalog){
  final handoff=NativeM51TaskHandoff(ownerId:'owner');
  handoff.request(catalog,currentOwnerId:'owner');
  final ctx=NativeM52TaskDraftContext.fromHandoff(
    handoff:handoff.inspect(catalog,currentOwnerId:'owner'),
    catalog:catalog,currentOwnerId:'owner');
  handoff.dispose();
  return ctx;
}

NativeM53TaskCompletionEvidence evaluate({
  required MediaFlowCatalog catalog,
  required NativeM52TaskDraftContext contextToken,
  NativeEditingWorkspace? workspace,
  String owner='owner',
  NativeLoggingPreview? standard,
  NativeItemizedPreview? itemized,
})=>NativeM53TaskCompletionEvidence.evaluate(
  catalog:catalog,titleId:'a',
  context:contextToken.inspect(catalog:catalog,
    currentOwnerId:owner,forTitleId:'a',workspace:workspace),
  standardPreview:standard,itemizedPreview:itemized);

void main(){
  test('absent draft has no guessed quantity, task, XP or traversal',(){
    final c=decodeMediaFlowState(fixture53());
    final e=evaluate(catalog:c,contextToken:token(c));
    expect(e.status,NativeM53EvidenceStatus.noDraft);
    expect(e.source,NativeM53EvidenceSource.none);
    expect(e.bandProgress,isNull);
    expect(e.confirmedTaskCompleted,false);
    expect(e.canSubmit,false);
    expect(e.confirmedXp,isNull);
    expect(e.canAdvanceCollection,false);
    expect(e.canAwardRespect,false);
    expect(c.sessions,isEmpty);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('saved standard draft indicates below, inside, above range only',(){
    final c=decodeMediaFlowState(fixture53());
    final w=NativeEditingWorkspace(ownerId:'owner')..observe(c);
    addTearDown(w.dispose);
    final t=token(c);
    final cases={
      1.0:NativeM53EvidenceStatus.belowBand,
      2.0:NativeM53EvidenceStatus.withinBand,
      3.0:NativeM53EvidenceStatus.withinBand,
      4.0:NativeM53EvidenceStatus.withinBand,
      5.0:NativeM53EvidenceStatus.aboveBand,
    };
    for(final entry in cases.entries){
      w.stageLog(catalog:c,titleId:'a',amount:entry.key,
        minutes:40,note:'unchanged');
      final before=w.logDraft('a');
      final e=evaluate(catalog:c,contextToken:t,workspace:w);
      expect(e.status,entry.value);
      expect(e.amount,entry.key);
      expect(e.source,NativeM53EvidenceSource.standardDraft);
      expect(e.bandProgress,entry.key<4?entry.key/4:1);
      expect(e.explanation,contains('targetMid'));
      expect(e.confirmedTaskCompleted,false);
      expect(e.canSubmit,false);
      expect(w.logDraft('a'),same(before));
    }
    expect(w.logCount,1);
    expect(c.library.first.progress,2);
    expect(c.sessions,isEmpty);
  });

  test('itemized counts selected consumed units, not contiguous progress',(){
    final c=decodeMediaFlowState(fixture53(seasons:true));
    final w=NativeEditingWorkspace(ownerId:'owner')..observe(c);
    addTearDown(w.dispose);
    w.stageItemizedLog(catalog:c,titleId:'a',seasonId:'s1',
      numbers:[4,5],secondsPerUnit:1200);
    final before=w.itemizedDraft('a')!;
    expect(before.afterTitleProgress,3);
    expect(before.consumed,2);
    final e=evaluate(catalog:c,contextToken:token(c),workspace:w);
    expect(e.source,NativeM53EvidenceSource.itemizedDraft);
    expect(e.status,NativeM53EvidenceStatus.withinBand);
    expect(e.amount,2);
    expect(e.projectedLibraryProgress,3);
    expect(e.projectedLibraryCompletion,false);
    expect(w.itemizedDraft('a'),same(before));
    expect(c.sessions,isEmpty);
    expect(c.library.first.progress,3);
  });

  test('Force Queue foreign category never claims assigned task completion',(){
    final c=decodeMediaFlowState(fixture53(titleCategory:'books'));
    final w=NativeEditingWorkspace(ownerId:'owner')..observe(c);
    addTearDown(w.dispose);
    w.stageLog(catalog:c,titleId:'a',amount:3,
      minutes:12,note:'foreign category');
    final e=evaluate(catalog:c,contextToken:token(c),workspace:w);
    expect(e.status,NativeM53EvidenceStatus.differentCategory);
    expect(e.comparable,false);
    expect(e.bandProgress,isNull);
    expect(e.explanation,contains('skipped'));
    expect(e.confirmedTaskCompleted,false);
  });

  test('unknown or inconsistent target does not infer completion',(){
    for(final bounds in [[0.0,0.0],[4.0,2.0],
        [double.nan,4.0],[2.0,double.infinity]]){
      final c=decodeMediaFlowState(fixture53(low:bounds[0],high:bounds[1]));
      final w=NativeEditingWorkspace(ownerId:'owner')..observe(c);
      w.stageLog(catalog:c,titleId:'a',amount:3,
        minutes:12,note:'unknown target');
      final e=evaluate(catalog:c,contextToken:token(c),workspace:w);
      expect(e.status,NativeM53EvidenceStatus.unknownTarget);
      expect(e.bandProgress,isNull);
      expect(e.confirmedTaskCompleted,false);
      w.dispose();
    }
  });

  test('repeat draft retains consumed amount but not confirmed Library progress',(){
    final c=decodeMediaFlowState(fixture53());
    // A standard hypothetical preview is produced by the existing
    // calculations. This remains unsubmitted and cannot award XP.
    final projection=NativeLoggingParityPreview.calculate(
      title:c.library.first,existingSessions:c.sessions,
      mode:NativeLogInputMode.amount,value:3,
      minutes:22,note:'preview only');
    final e=evaluate(catalog:c,contextToken:token(c),
      standard:projection);
    expect(e.source,NativeM53EvidenceSource.standardPreview);
    expect(e.amount,3);
    expect(e.status,NativeM53EvidenceStatus.withinBand);
    expect(e.projectedLibraryProgress,5);
    expect(e.confirmedXp,isNull);
    expect(c.sessions,isEmpty);
  });

  test('workspace owner, snapshot replacement and conflicting previews fail shut',(){
    final c=decodeMediaFlowState(fixture53());
    final t=token(c);
    final wrong=evaluate(catalog:c,contextToken:t,owner:'other');
    expect(wrong.status,NativeM53EvidenceStatus.invalidContext);
    final newer=decodeMediaFlowState(fixture53());
    expect(evaluate(catalog:newer,contextToken:t).status,
      NativeM53EvidenceStatus.invalidContext);
    final std=NativeLoggingParityPreview.calculate(
      title:c.library.first,existingSessions:c.sessions,
      mode:NativeLogInputMode.amount,value:2,minutes:10,note:'');
    final second=NativeItemizedParity.calculate(
      title:c.library.first,sessions:c.sessions,
      seasonId:'',numbers:[3],secondsPerUnit:1000);
    expect(evaluate(catalog:c,contextToken:t,
      standard:std,itemized:second).status,
      NativeM53EvidenceStatus.invalidContext);
    expect(c.sessions,isEmpty);
  });

  test('100k Library evidence checks selected title without mutating source',(){
    final c=decodeMediaFlowState(fixture53(extra:99999));
    expect(c.library.length,100000);
    final t=token(c);
    final w=NativeEditingWorkspace(ownerId:'owner')..observe(c);
    addTearDown(w.dispose);
    w.stageLog(catalog:c,titleId:'a',amount:2,
      minutes:8,note:'100k');
    final e=evaluate(catalog:c,contextToken:t,workspace:w);
    expect(e.status,NativeM53EvidenceStatus.withinBand);
    expect(c.library.length,100000);
    expect(c.library.first.progress,2);
    expect(c.sessions,isEmpty);
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('saved draft panel gives accessible non-committing evidence',(
      tester)async{
    tester.view.physicalSize=const Size(320,840);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c=decodeMediaFlowState(fixture53());
    final ctx=token(c);
    final w=NativeEditingWorkspace(ownerId:'owner')..observe(c);
    addTearDown(w.dispose);
    w.stageLog(catalog:c,titleId:'a',amount:3,
      minutes:30,note:'saved');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:SingleChildScrollView(child:NativeM53CompletionEvidencePanel(
        taskContext:ctx,catalog:c,titleId:'a',
        currentOwnerId:'owner',workspace:w)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m53-evidence-saved')),findsOneWidget);
    expect(find.byKey(const Key('m53-status-saved')),findsOneWidget);
    expect(find.byKey(const Key('m53-band-progress-saved')),findsOneWidget);
    expect(find.byKey(const Key('m53-no-commit-saved')),findsOneWidget);
    expect(find.byType(FilledButton),findsNothing);
    expect(w.logCount,1);
    expect(c.sessions,isEmpty);
    expect(tester.takeException(),isNull);
  });

  testWidgets('standard and itemized live editors show evidence without staging',(
      tester)async{
    tester.view.physicalSize=const Size(400,1120);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c=decodeMediaFlowState(fixture53(seasons:true));
    final ctx=token(c);
    final w=NativeEditingWorkspace(ownerId:'owner')..observe(c);
    addTearDown(w.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeLogDraftSheet(catalog:c,title:c.library.first,
        workspace:w,taskContext:ctx,currentOwnerId:'owner'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m53-evidence-live-standard')),findsNothing);
    expect(w.logCount,0);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeItemizedDraftSheet(catalog:c,title:c.library.first,
        workspace:w,taskContext:ctx,currentOwnerId:'owner'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m53-evidence-live-itemized')),
      findsOneWidget);
    expect(find.byKey(const Key('m53-no-commit-live-itemized')),
      findsOneWidget);
    expect(w.logCount,0);
    expect(c.sessions,isEmpty);
    expect(tester.takeException(),isNull);
  });
}
