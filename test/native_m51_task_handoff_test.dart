import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/dashboard/dashboard_screen.dart';
import 'package:mediaflow_app/features/logging/logging_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_editing_workspace.dart';
import 'package:mediaflow_app/services/native_m51_task_handoff.dart';

Map<String,dynamic> fixture51({
  String taskId='a',bool sessionActive=true,
  bool duplicate=false,bool forceCategory=false,
}) => {
  'categories':[
    {'id':'anime','name':'Anime'},
    {'id':'books','name':'Books'},
  ],
  'library':[
    {'id':'a','title':'Alpha','categoryId':forceCategory?'books':'anime',
      'status':'active','priority':'high','progress':2,'total':12},
    {'id':'b','title':'Beta','categoryId':'anime',
      'status':'active','progress':0,'total':12},
    if(duplicate){'id':'a','title':'Duplicate Alpha','categoryId':'anime'},
  ],
  'sessionActive':sessionActive,
  if(sessionActive)'currentTask':{
    'categoryId':'anime','libraryId':taskId,
    'title':'Saved displayed task title',
    'low':2,'high':4,'unit':'episodes',
    'reasons':['Schedule selected Anime'],
  },
};

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.catalog);
  final MediaFlowCatalog catalog;
  @override
  Future<MediaFlowCatalog> load() async=>catalog;
}

void main(){
  test('request is exact-ID and owner-gated; no automatic selection/staging',(){
    final source=decodeMediaFlowState(fixture51());
    final handoff=NativeM51TaskHandoff(ownerId:'alex');
    addTearDown(handoff.dispose);
    expect(handoff.hasRequest,false);
    expect(()=>handoff.request(source,currentOwnerId:'somebody-else'),
      throwsStateError);
    expect(handoff.hasRequest,false);
    handoff.request(source,currentOwnerId:'alex');
    final view=handoff.inspect(source,currentOwnerId:'alex');
    expect(view.status,NativeM51HandoffStatus.ready);
    expect(view.ready,true);
    expect(view.title!.title,'Alpha');
    expect(view.categoryId,'anime');
    expect(view.taskTargetLow,2);
    expect(view.taskTargetHigh,4);
    expect(view.taskUnit,'episodes');
    expect(source.sessions,isEmpty);
    expect(source.currentTask!.libraryId,'a');
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    handoff.dismiss();
    expect(handoff.hasRequest,false);
    expect(handoff.inspect(source,currentOwnerId:'alex').status,
      NativeM51HandoffStatus.absent);
  });

  test('missing/ambiguous IDs and inactive tasks cannot be handed off',(){
    final handoff=NativeM51TaskHandoff(ownerId:'alex');
    addTearDown(handoff.dispose);
    for(final source in [
      fixture51(taskId:''),
      fixture51(taskId:'missing'),
      fixture51(duplicate:true),
      fixture51(sessionActive:false),
    ]){
      expect(()=>handoff.request(decodeMediaFlowState(source),
        currentOwnerId:'alex'),throwsStateError);
      expect(handoff.hasRequest,false);
    }
  });

  test('request rejects changed account and replaced snapshot even if identical JSON',(){
    final source=decodeMediaFlowState(fixture51());
    final handoff=NativeM51TaskHandoff(ownerId:'alex');
    addTearDown(handoff.dispose);
    handoff.request(source,currentOwnerId:'alex');
    expect(handoff.inspect(source,currentOwnerId:'not-alex').status,
      NativeM51HandoffStatus.differentOwner);
    final newSnapshot=decodeMediaFlowState(fixture51());
    expect(handoff.inspect(newSnapshot,currentOwnerId:'alex').status,
      NativeM51HandoffStatus.replacedSnapshot);
    expect(handoff.inspect(source,currentOwnerId:'alex').ready,true);
    expect(source.sessions,isEmpty);
  });

  test('replaced task metadata or missing title fails closed without staging',(){
    final source=decodeMediaFlowState(fixture51());
    final handoff=NativeM51TaskHandoff(ownerId:'alex');
    addTearDown(handoff.dispose);
    handoff.request(source,currentOwnerId:'alex');
    // Immutable source snapshot is identity-pinned: a new catalog with
    // changed task is never rebound, even if its Library still matches.
    final newCatalog=decodeMediaFlowState(fixture51(taskId:'b'));
    expect(handoff.inspect(newCatalog,currentOwnerId:'alex').status,
      NativeM51HandoffStatus.replacedSnapshot);
    final force=decodeMediaFlowState(fixture51(forceCategory:true));
    handoff.request(force,currentOwnerId:'alex');
    expect(handoff.inspect(force,currentOwnerId:'alex').ready,true);
    // Force Collection queues can recommend a title outside task category.
    expect(handoff.inspect(force,currentOwnerId:'alex').title!.categoryId,
      'books');
  });

  test('handoff preserves existing local logging and item selection intent',(){
    final source=decodeMediaFlowState(fixture51());
    final workspace=NativeEditingWorkspace(ownerId:'alex');
    addTearDown(workspace.dispose);
    workspace.observe(source);
    workspace.stageLog(
      catalog:source,titleId:'b',amount:1,minutes:20,
      note:'Existing deliberate offline draft');
    final existing=workspace.logDraft('b');
    final handoff=NativeM51TaskHandoff(ownerId:'alex');
    addTearDown(handoff.dispose);
    handoff.request(source,currentOwnerId:'alex');
    expect(handoff.inspect(source,currentOwnerId:'alex').ready,true);
    expect(workspace.logDraft('b'),same(existing));
    expect(workspace.logCount,1);
    expect(workspace.logDraft('a'),isNull);
    expect(workspace.xpAwarded,0);
    expect(source.sessions,isEmpty);
  });

  test('100k Library stress: exact match finds same reference, no copying',(){
    final raw=fixture51();
    final library=raw['library'] as List<dynamic>;
    for(var i=0;i<99998;i++){
      library.add({'id':'s$i','title':'Stress $i','categoryId':'anime',
        'status':'active','total':12});
    }
    final source=decodeMediaFlowState(raw);
    expect(source.library.length,100000);
    final controller=NativeM51TaskHandoff(ownerId:'alex');
    addTearDown(controller.dispose);
    controller.request(source,currentOwnerId:'alex');
    final view=controller.inspect(source,currentOwnerId:'alex');
    expect(view.ready,true);
    expect(identical(view.title,source.library.first),true);
    expect(source.sessions,isEmpty);
    expect(source.library.length,100000);
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('Dashboard handoff navigates to Logging review, no auto draft',(
      tester)async{
    tester.view.physicalSize=const Size(400,1000);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source=decodeMediaFlowState(fixture51());
    final repo=_Repo(source);
    final handoff=NativeM51TaskHandoff(ownerId:'alex');
    final workspace=NativeEditingWorkspace(ownerId:'alex');
    addTearDown(handoff.dispose);
    addTearDown(workspace.dispose);
    workspace.observe(source);
    var logging=false;
    await tester.pumpWidget(MaterialApp(home:StatefulBuilder(
      builder:(context,update)=>Scaffold(
        body:logging
          ?LoggingScreen(repository:repo,workspace:workspace,
            taskHandoff:handoff,currentOwnerId:'alex')
          :DashboardScreen(repository:repo,openLibrary:(){},
            openHistory:(){},onReviewTaskInLogging:(catalog){
              handoff.request(catalog,currentOwnerId:'alex');
              update(()=>logging=true);
            }),
      ),
    )));
    await tester.pumpAndSettle();
    final button=find.byKey(const Key('m51-review-in-logging'));
    await tester.scrollUntilVisible(button,200,
      scrollable:find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed,isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m51-handoff-card')),findsOneWidget);
    expect(find.byKey(const Key('m51-logging-controls-scroll')),findsOneWidget);
    expect(tester.takeException(),isNull);
    expect(find.text('Alpha'),findsWidgets);
    expect(find.byKey(const Key('m51-review-task-title')),findsOneWidget);
    expect(workspace.logCount,0);
    await tester.tap(find.byKey(const Key('m51-review-task-title')));
    await tester.pumpAndSettle();
    expect(find.text('Draft logging locally'),findsOneWidget);
    expect(workspace.logCount,0);
    expect(source.sessions,isEmpty);
  });

  testWidgets('320px narrow Logging handoff remains scrollable without overflow',(
      tester)async{
    tester.view.physicalSize=const Size(320,720);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source=decodeMediaFlowState(fixture51());
    final request=NativeM51TaskHandoff(ownerId:'alex');
    addTearDown(request.dispose);
    request.request(source,currentOwnerId:'alex');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:LoggingScreen(repository:_Repo(source),taskHandoff:request,
        currentOwnerId:'alex'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m51-logging-controls-scroll')),
      findsOneWidget);
    expect(find.byKey(const Key('logging-browser-titles')),findsOneWidget);
    expect(find.byKey(const Key('m51-handoff-card')),findsOneWidget);
    expect(tester.takeException(),isNull);
    await tester.ensureVisible(find.byKey(const Key('m51-review-task-title')));
    await tester.tap(find.byKey(const Key('m51-review-task-title')));
    await tester.pumpAndSettle();
    expect(find.text('Draft logging locally'),findsNothing);
    expect(find.text('Current progress: 2/12'),findsOneWidget);
    expect(source.sessions,isEmpty);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Logging handoff is dismissible; stale source does not select',(
      tester)async{
    tester.view.physicalSize=const Size(420,1060);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source=decodeMediaFlowState(fixture51());
    final other=decodeMediaFlowState(fixture51());
    final handoff=NativeM51TaskHandoff(ownerId:'alex');
    addTearDown(handoff.dispose);
    handoff.request(source,currentOwnerId:'alex');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:LoggingScreen(repository:_Repo(other),
        taskHandoff:handoff,currentOwnerId:'alex'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m51-handoff-card')),findsOneWidget);
    expect(find.byKey(const Key('m51-review-task-title')),findsNothing);
    expect(find.textContaining('snapshot changed'),findsOneWidget);
    await tester.tap(find.byKey(const Key('m51-dismiss-handoff')));
    await tester.pumpAndSettle();
    expect(handoff.hasRequest,false);
    expect(find.byKey(const Key('m51-handoff-card')),findsNothing);
    expect(source.sessions,isEmpty);
  });
}
