import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/logging/native_logging_recommends_card.dart';
import 'package:mediaflow_app/services/native_logging_recommends.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';

Map<String,dynamic> fixture({
  bool task=true,bool duplicate=false,bool? prioritize=true,
  String taskId='alpha',
})=>{
  'categories':[{'id':'anime','name':'Anime'}, {'id':'book','name':'Books'}],
  'library':[
    {'id':'alpha','title':'Alpha recommendation',
      'categoryId':'anime','status':'active','priority':'high',
      'progress':3,'total':12},
    {'id':'beta','title':'Beta recommendation',
      'categoryId':'anime','status':'active','progress':0,'total':24},
    if(duplicate){'id':'alpha','title':'Ambiguous alpha',
      'categoryId':'anime','status':'active'},
  ],
  'settings':{if(prioritize!=null)
    'prioritizePersonalOrder':prioritize},
  'orderPlan':{
    'titleIds':['beta'],
    'categoryQueues':{'anime':['t:beta']},
  },
  'sessionActive':task,
  if(task)'currentTask':{
    'categoryId':'anime','libraryId':taskId,
    'title':'Saved task','low':2,'high':4,'unit':'episodes',
  },
};

void main(){
  test('saved current task always wins and uses exact unique Library ID',(){
    final catalog=decodeMediaFlowState(fixture());
    final item=NativeLoggingRecommendation.forCategory(catalog,'anime');
    expect(item.source,NativeLoggingRecommendSource.savedTask);
    expect(item.title!.id,'alpha');
    expect(item.title!.title,'Alpha recommendation');
    expect(item.canUse,true);
    expect(catalog.sessions,isEmpty);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });
  test('missing or duplicate current task ID cannot silently pick queue fallback',(){
    for(final raw in [
      fixture(taskId:'deleted'),
      fixture(taskId:''),
      fixture(duplicate:true),
    ]){
      final a=NativeLoggingRecommendation.forCategory(
        decodeMediaFlowState(raw),'anime');
      expect(a.source,NativeLoggingRecommendSource.unavailable);
      expect(a.canUse,false);
      expect(a.title,isNull);
      expect(a.message,contains('missing or ambiguous'));
    }
  });
  test('queue preview only when priority rule explicitly enabled',(){
    final c=decodeMediaFlowState(fixture(task:false));
    final a=NativeLoggingRecommendation.forCategory(c,'anime');
    expect(a.source,NativeLoggingRecommendSource.personalOrderPreview);
    expect(a.title!.id,'beta');
    expect(a.queuePosition,1);
    expect(a.message,contains('not a confirmed'));
    for(final policy in [false,null]){
      final result=NativeLoggingRecommendation.forCategory(
        decodeMediaFlowState(fixture(task:false,prioritize:policy)),'anime');
      expect(result.source,NativeLoggingRecommendSource.unavailable);
      expect(result.canUse,false);
    }
    expect(NativeLoggingRecommendation.forCategory(c,'missing').canUse,false);
  });
  testWidgets('320px card selects directly without changing account state',(
      tester)async{
    tester.view.physicalSize=const Size(320,850);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog=decodeMediaFlowState(fixture());
    final chosen=<String>{};
    var count=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:SingleChildScrollView(child:NativeLoggingRecommendsCard(
        catalog:catalog,selectedIds:chosen,
        onUse:(title){chosen.add(title.id);count++;})))));
    await tester.pumpAndSettle();
    expect(find.text('MEDIAFLOW RECOMMENDS'),findsOneWidget);
    expect(find.byKey(const Key('logging-recommends-saved-source')),
      findsOneWidget);
    expect(find.text('Alpha recommendation'),findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('logging-use-recommended-title')));
    await tester.tap(find.byKey(const Key('logging-use-recommended-title')));
    expect(chosen,{'alpha'});
    expect(count,1);
    expect(catalog.sessions,isEmpty);
    expect(catalog.library.first.progress,3);
    expect(tester.takeException(),isNull);
  });
  testWidgets('unverified queue and missing task cannot submit', (tester)async{
    final catalog=decodeMediaFlowState(fixture(task:false));
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeLoggingRecommendsCard(
        catalog:catalog,selectedIds:const {},onUse:(_){fail('no click');}))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logging-recommends-queue-source')),
      findsOneWidget);
    final unknown=decodeMediaFlowState(fixture(taskId:'bad'));
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeLoggingRecommendsCard(
        catalog:unknown,selectedIds:const {},onUse:(_){fail('unsafe');}))));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(
      find.byKey(const Key('logging-use-recommended-title')))
      .onPressed,isNull);
    expect(tester.takeException(),isNull);
  });
}
