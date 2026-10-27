import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/logging/native_logging_recommends_card.dart';
import 'package:mediaflow_app/services/native_logging_recommends.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';

Map<String,dynamic> browseFixture({
  bool task=true,bool duplicate=false,bool? prioritize=true,
  String taskId='alpha',
})=> {
  'categories':[{'id':'anime','name':'Anime'}],
  'library':[
    for(final id in ['alpha','beta','gamma','delta','epsilon','zeta','eta'])
      {'id':id,'title':'Title $id','categoryId':'anime',
       'status':'active','priority':'medium','progress':1,'total':12},
    if(duplicate){'id':'gamma','title':'Duplicate gamma',
      'categoryId':'anime','status':'active'},
  ],
  'settings':{if(prioritize!=null)
    'prioritizePersonalOrder':prioritize},
  'orderPlan':{
    'titleIds':['beta','gamma','delta','epsilon','zeta','eta'],
    'categoryQueues':{
      'anime':['t:beta','t:gamma','t:delta','t:epsilon','t:zeta','t:eta'],
    },
  },
  'sessionActive':task,
  if(task)'currentTask':{
    'categoryId':'anime','libraryId':taskId,
    'title':'Saved task','low':2,'high':4,'unit':'episodes',
  },
};

void main(){
  test('queue browsing is capped, excludes saved and selected ID',(){
    final c=decodeMediaFlowState(browseFixture());
    final results=NativeLoggingRecommendation.browseQueue(c,'anime',
      limit:3,excludedIds:const {'delta'});
    expect(results.map((r)=>r.title!.id),['beta','gamma','epsilon']);
    expect(results.every((r)=>r.source==
      NativeLoggingRecommendSource.personalOrderPreview),true);
    expect(results.every((r)=>r.message.contains('not a confirmed')),true);
    expect(results.map((r)=>r.queuePosition),[1,2,4]);
    expect(c.sessions,isEmpty);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    expect(()=>NativeLoggingRecommendation.browseQueue(c,'anime',limit:0),
      throwsFormatException);
    expect(()=>NativeLoggingRecommendation.browseQueue(c,'anime',limit:9),
      throwsFormatException);
  });

  test('duplicates, blocked saved tasks and disabled policy fail safely',(){
    final dup=decodeMediaFlowState(browseFixture(duplicate:true));
    final seen=NativeLoggingRecommendation.browseQueue(dup,'anime',limit:8);
    expect(seen.any((r)=>r.title?.id=='gamma'),false);
    final bad=decodeMediaFlowState(browseFixture(taskId:'missing'));
    expect(NativeLoggingRecommendation.browseQueue(bad,'anime'),isEmpty);
    final unknown=decodeMediaFlowState(browseFixture(prioritize:null));
    expect(NativeLoggingRecommendation.browseQueue(unknown,'anime'),isEmpty);
    final disabled=decodeMediaFlowState(browseFixture(prioritize:false));
    expect(NativeLoggingRecommendation.browseQueue(disabled,'anime'),isEmpty);
    expect(NativeLoggingRecommendation.browseQueue(dup,'other'),isEmpty);
  });

  testWidgets('mobile queue browse is opt in and does not alter account',
      (tester)async{
    tester.view.physicalSize=const Size(320,880);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog=decodeMediaFlowState(browseFixture());
    final selected=<String>{'alpha'};
    var hits=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:SingleChildScrollView(child:StatefulBuilder(
        builder:(context,update)=>NativeLoggingRecommendsCard(
          catalog:catalog,selectedIds:selected,
          onUse:(title){update(()=>selected.add(title.id));hits++;}),
      )),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logging-queue-heading')),findsNothing);
    final more=find.byKey(const Key('logging-browse-queue'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logging-queue-heading')),findsOneWidget);
    expect(find.byKey(const Key('logging-queue-row-beta')),findsOneWidget);
    expect(find.byKey(const Key('logging-use-queue-gamma')),findsOneWidget);
    expect(find.textContaining('not live task rerolls'),findsOneWidget);
    final use=find.byKey(const Key('logging-use-queue-gamma'));
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(selected,{'alpha','gamma'});
    expect(hits,1);
    expect(find.byKey(const Key('logging-use-queue-gamma')),findsNothing);
    expect(find.byKey(const Key('logging-queue-row-delta')),findsOneWidget);
    expect(catalog.currentTask!.libraryId,'alpha');
    expect(catalog.library.first.progress,1);
    expect(catalog.sessions,isEmpty);
    expect(tester.takeException(),isNull);
  });
}
