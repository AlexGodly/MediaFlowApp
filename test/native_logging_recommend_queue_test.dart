import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/logging/native_logging_recommends_card.dart';
import 'package:mediaflow_app/services/native_logging_recommend_queue.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';

Map<String,dynamic> queueFixture({
  int size=12,bool? prioritized=true,bool includeSaved=false,
  bool duplicate=false,
}){
  final titles=<Map<String,dynamic>>[
    for(var i=0;i<size;i++)
      {'id':'q$i','title':'A long seasonal story recommendation $i',
        'categoryId':'anime','status':'active','priority':'high',
        'progress':0,'total':24},
    if(duplicate){'id':'q2','title':'Ambiguous q2 title',
      'categoryId':'anime','status':'active'},
  ];
  return {
    'categories':[{'id':'anime','name':'Anime'},
      {'id':'books','name':'Books'}],
    'library':titles,
    'settings':{
      if(prioritized!=null)'prioritizePersonalOrder':prioritized,
    },
    'orderPlan':{
      'titleIds':[for(var i=0;i<size;i++)'q$i'],
      'categoryQueues':{'anime':[for(var i=0;i<size;i++)'t:q$i']},
    },
    'sessionActive':includeSaved,
    if(includeSaved)'currentTask':{
      'categoryId':'anime','libraryId':'q3','title':'Current task',
      'low':2,'high':4,'unit':'episodes',
    },
  };
}

void main(){
  test('queue pages are bounded, preserve rank, and never change account',(){
    final catalog=decodeMediaFlowState(queueFixture());
    final first=NativeLoggingRecommendQueue.page(catalog,'anime');
    expect(first.items.map((e)=>e.title.id),
      ['q0','q1','q2','q3','q4']);
    expect(first.items.map((e)=>e.rank),[1,2,3,4,5]);
    expect(first.hasMore,true);
    expect(first.message,contains('preview only'));
    final second=NativeLoggingRecommendQueue.page(
      catalog,'anime',offset:5);
    expect(second.items.map((e)=>e.title.id),
      ['q5','q6','q7','q8','q9']);
    expect(second.hasMore,true);
    final third=NativeLoggingRecommendQueue.page(
      catalog,'anime',offset:10);
    expect(third.items.map((e)=>e.title.id),['q10','q11']);
    expect(third.hasMore,false);
    expect(catalog.sessions,isEmpty);
    expect(catalog.library.first.progress,0);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('queue browsing never replaces saved task recommendation',(){
    final catalog=decodeMediaFlowState(queueFixture(includeSaved:true));
    final saved=catalog.currentTask!;
    final page=NativeLoggingRecommendQueue.page(catalog,'anime');
    expect(page.items.first.title.id,'q0');
    expect(saved.libraryId,'q3');
    expect(saved.title,'Current task');
    expect(catalog.currentTask,same(saved));
    expect(catalog.sessions,isEmpty);
  });

  test('disabled, unknown policy, invalid category and offsets fail closed',(){
    for(final value in [null,false]){
      final c=decodeMediaFlowState(queueFixture(prioritized:value));
      final page=NativeLoggingRecommendQueue.page(c,'anime');
      expect(page.items,isEmpty);
      expect(page.hasMore,false);
      expect(page.message,contains(value==null?'unknown':'disabled'));
    }
    final good=decodeMediaFlowState(queueFixture());
    final invalid=NativeLoggingRecommendQueue.page(good,'unknown');
    expect(invalid.items,isEmpty);
    for(final offset in [-5,1,4,50,100]){
      expect(()=>NativeLoggingRecommendQueue.page(
        good,'anime',offset:offset),throwsFormatException);
    }
  });

  test('ambiguous title IDs are never selectable queue candidates',(){
    final c=decodeMediaFlowState(queueFixture(duplicate:true));
    final first=NativeLoggingRecommendQueue.page(c,'anime');
    expect(first.items.any((item)=>item.title.id=='q2'),false);
    expect(first.items.every((item)=>item.title.id!='q2'),true);
    expect(c.sessions,isEmpty);
  });

  test('50-position bound prevents unbounded pagination of 100k library',(){
    final raw=queueFixture(size:60);
    final titles=raw['library'] as List<Map<String,dynamic>>;
    for(var i=60;i<100000;i++){
      titles.add({'id':'extra$i','title':'Extra $i','categoryId':'anime',
        'status':'active','progress':0,'total':10});
    }
    final c=decodeMediaFlowState(raw);
    expect(c.library.length,100000);
    final page=NativeLoggingRecommendQueue.page(c,'anime',offset:45);
    expect(page.items.length,5);
    expect(page.hasMore,false);
    expect(c.sessions,isEmpty);
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('320px queue browser paginates and opens exact selected title',(
      tester)async{
    tester.view.physicalSize=const Size(320,820);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c=decodeMediaFlowState(queueFixture());
    final selected=<String>[];
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:SingleChildScrollView(
        child:NativeLoggingRecommendsCard(catalog:c,selectedIds:const {},
          onUse:(title)=>selected.add(title.id))))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('logging-browse-recommendation-queue')));
    await tester.tap(
      find.byKey(const Key('logging-browse-recommendation-queue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('logging-queue-browser')),findsOneWidget);
    expect(find.byKey(const ValueKey('logging-queue-use-1')),findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('logging-queue-next')));
    await tester.tap(find.byKey(const Key('logging-queue-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('logging-queue-use-7')),findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('logging-queue-use-7')));
    await tester.tap(find.byKey(const ValueKey('logging-queue-use-7')));
    expect(selected,['q6']);
    expect(c.library[6].progress,0);
    expect(c.sessions,isEmpty);
    expect(tester.takeException(),isNull);
  });
}
