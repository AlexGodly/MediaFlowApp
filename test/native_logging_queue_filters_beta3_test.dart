import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/logging/native_logging_recommends_card.dart';
import 'package:mediaflow_app/services/native_logging_recommends.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';

Map<String,dynamic> fixtureBeta3({bool duplicates=false,
  bool? prioritize=true,bool saved=true,int count=16}) {
  final ids=List.generate(count,(i)=>'t${i.toString().padLeft(2,'0')}');
  return {
    'categories':[{'id':'anime','name':'Anime'},{'id':'books','name':'Books'}],
    'library':[
      {'id':'saved','title':'Saved anime','categoryId':'anime',
        'status':'active','priority':'medium','progress':2,'total':12},
      for(var i=0;i<count;i++)
        {'id':ids[i],'title':'Queue title number ${i.toString().padLeft(2,'0')}',
          'categoryId':'anime','status':'active','priority':'medium',
          'progress':i,'total':50},
      if(duplicates&&ids.isNotEmpty)
        {'id':ids[1],'title':'Ambiguous queue row',
          'categoryId':'anime','status':'active'},
    ],
    'settings':{if(prioritize!=null)'prioritizePersonalOrder':prioritize},
    'orderPlan':{
      'titleIds':ids,
      'categoryQueues':{'anime':[for(final id in ids)'t:$id']},
    },
    'sessionActive':saved,
    if(saved)'currentTask':{
      'categoryId':'anime','libraryId':'saved','title':'Saved anime',
      'low':2,'high':4,'unit':'episodes',
    },
  };
}

void main(){
  test('browser exposes ordered, bounded, verified queue entries without writes',(){
    final catalog=decodeMediaFlowState(fixtureBeta3());
    final entries=NativeLoggingRecommendation.browseQueueCatalog(
      catalog,'anime');
    expect(entries.length,16);
    expect(entries.first.title!.id,'t00');
    expect(entries.last.title!.id,'t15');
    expect(entries.map((e)=>e.queuePosition),
      List.generate(16,(i)=>i+1));
    expect(entries.every((e)=>e.source==
      NativeLoggingRecommendSource.personalOrderPreview),true);
    expect(entries.every((e)=>e.message.contains('not a confirmed')),true);
    expect(NativeLoggingRecommendation.browseQueueCatalog(
      catalog,'anime',maxCandidates:7).length,7);
    expect(()=>NativeLoggingRecommendation.browseQueueCatalog(
      catalog,'anime',maxCandidates:501),throwsFormatException);
    expect(catalog.sessions,isEmpty);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('duplicate, missing saved title and policy-gated queues fail closed',(){
    final duplicate=decodeMediaFlowState(fixtureBeta3(duplicates:true));
    final entries=NativeLoggingRecommendation.browseQueueCatalog(
      duplicate,'anime');
    expect(entries.map((e)=>e.title!.id),isNot(contains('t01')));
    for(final policy in [false,null]){
      final catalog=decodeMediaFlowState(
        fixtureBeta3(prioritize:policy));
      expect(NativeLoggingRecommendation.browseQueueCatalog(
        catalog,'anime'),isEmpty);
    }
    final missing=fixtureBeta3();
    (missing['currentTask'] as Map<String,dynamic>)['libraryId']='gone';
    expect(NativeLoggingRecommendation.browseQueueCatalog(
      decodeMediaFlowState(missing),'anime'),isEmpty);
    expect(NativeLoggingRecommendation.browseQueueCatalog(
      duplicate,'books'),isEmpty);
  });

  test('100k titles only keep selected queue preview index',(){
    final fixture=fixtureBeta3(count:16);
    final library=fixture['library'] as List<dynamic>;
    for(var i=0;i<99983;i++){
      library.add({'id':'background-$i','title':'Unrelated $i',
        'categoryId':'books','status':'active','total':20});
    }
    final catalog=decodeMediaFlowState(fixture);
    expect(catalog.library.length,100000);
    final results=NativeLoggingRecommendation.browseQueueCatalog(
      catalog,'anime');
    expect(results.length,16);
    expect(catalog.sessions,isEmpty);
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('320px queue supports search, pagination, and selection filters',(
      tester)async{
    tester.view.physicalSize=const Size(320,1000);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog=decodeMediaFlowState(fixtureBeta3());
    final selected=<String>{'t01'};
    var calls=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:SingleChildScrollView(child:StatefulBuilder(
        builder:(context,update)=>NativeLoggingRecommendsCard(
          catalog:catalog,selectedIds:selected,
          onUse:(title){
            update(()=>selected.add(title.id));
            calls++;
          },
        ),
      )),
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('logging-browse-queue')));
    await tester.tap(find.byKey(const Key('logging-browse-queue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logging-queue-row-t00')),findsOneWidget);
    expect(find.byKey(const Key('logging-queue-row-t01')),findsNothing);
    expect(find.byKey(const Key('logging-queue-row-t05')),findsOneWidget);
    final next=find.byKey(const Key('logging-queue-next-page'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logging-queue-row-t06')),findsOneWidget);
    expect(find.byKey(const Key('logging-queue-row-t00')),findsNothing);
    await tester.ensureVisible(find.byKey(
      const Key('logging-queue-filter-alreadyAdded')));
    await tester.tap(find.byKey(
      const Key('logging-queue-filter-alreadyAdded')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logging-queue-row-t01')),findsOneWidget);
    expect(find.byKey(const Key('logging-queue-row-t06')),findsNothing);
    await tester.ensureVisible(find.byKey(const Key('logging-queue-filter-all')));
    await tester.tap(find.byKey(const Key('logging-queue-filter-all')));
    await tester.pumpAndSettle();
    final search=find.byKey(const Key('logging-queue-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search,'number 12');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logging-queue-row-t12')),findsOneWidget);
    expect(find.byKey(const Key('logging-queue-row-t11')),findsNothing);
    final use=find.byKey(const Key('logging-use-queue-t12'));
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
    expect(selected,contains('t12'));
    expect(calls,1);
    expect(catalog.currentTask!.libraryId,'saved');
    expect(catalog.sessions,isEmpty);
    expect(tester.takeException(),isNull);
  });
}
