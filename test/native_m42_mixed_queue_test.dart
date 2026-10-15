import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/personal_order/personal_order_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m42_mixed_queue.dart';

Map<String,dynamic> fixture() => {
  'categories':[
    {'id':'anime','name':'Anime'},
    {'id':'books','name':'Books'},
  ],
  'library':[
    {'id':'a1','title':'Alpha One','categoryId':'anime',
      'status':'active','progress':2,'total':10},
    {'id':'a2','title':'Alpha Two','categoryId':'anime',
      'status':'active','progress':0,'total':10},
    {'id':'a3','title':'Alpha Three','categoryId':'anime',
      'status':'completed','progress':10,'total':10},
    {'id':'a4','title':'Alpha Four','categoryId':'anime',
      'status':'dropped','progress':1,'total':10},
    {'id':'b1','title':'Beta One','categoryId':'books',
      'status':'active','progress':1,'total':20},
    {'id':'b2','title':'Beta Two','categoryId':'books',
      'status':'active','progress':20,'total':20},
  ],
  'collections':[
    {'id':'c1','title':'Favorite Worlds',
      'titleIds':['a2','b1','a3','a4','a1','missing'],
      'order':['a2','b1','a3','a4','a1','missing']},
    {'id':'c2','title':'Next Arc',
      'titleIds':['a2','b2'],'order':['a2','b2']},
  ],
  'orderPlan':{
    'titleIds':['a1','a2','b1','a3'],
    'collectionAssignments':[
      {'id':'assignment1','collectionId':'c1','categoryId':'anime',
        'categoryRule':'match','completedRule':'skip',
        'createdAt':100,'traversedTitleIds':['a2']},
      {'id':'assignment2','collectionId':'c1','categoryId':'books',
        'categoryRule':'force','completedRule':'include',
        'createdAt':200,'traversedTitleIds':[]},
      {'id':'assignment3','collectionId':'c2','categoryId':'anime',
        'categoryRule':'force','completedRule':'include',
        'createdAt':150,'traversedTitleIds':[]},
    ],
    'categoryQueues':{
      'anime':['c:assignment1','t:a2','c:assignment3','t:a1',
        'unknown','c:assignment1'],
      'books':['t:b1','c:assignment2'],
    },
    'futureField':{'keep':'unchanged'},
  },
  'history':[{'id':'h1','someOriginalField':'retain'}],
};


void main(){
  test('raw v287 category tokens and createdAt parse without mutating state',(){
    final raw=fixture();
    final original=(raw['orderPlan'] as Map)['categoryQueues'] as Map;
    final catalog=decodeMediaFlowState(raw);
    expect(catalog.categoryQueues['anime'],[
      'c:assignment1','t:a2','c:assignment3','t:a1',
      'unknown','c:assignment1']);
    expect(catalog.collectionAssignments[1].createdAt,200);
    expect(catalog.collectionAssignments.first.traversedTitleIds,['a2']);
    final queues=NativeM42MixedQueues(catalog);
    expect(queues.tokensForCategory('anime'),[
      'c:assignment1','t:a1','c:assignment3','t:a2','t:a3']);
    expect(queues.tokensForCategory('books'),['t:b1','c:assignment2']);
    expect(original['anime'],[
      'c:assignment1','t:a2','c:assignment3','t:a1',
      'unknown','c:assignment1']);
    expect(queues.diagnosticsForCategory('anime'),isNotEmpty);
  });

  test('v287 Collection blocks remain ONE queue slot with member positions',(){
    final queues=NativeM42MixedQueues(decodeMediaFlowState(fixture()));
    final rows=queues.slotsForCategory('anime');
    expect(rows.length,5);
    expect(rows.map((e)=>e.position),[1,2,3,4,5]);
    expect(rows.first.isCollection,true);
    expect(rows.first.collection!.title,'Favorite Worlds');
    expect(rows.first.candidates.single.title.id,'a1');
    expect(rows.first.candidates.single.outerPosition,1);
    expect(rows.first.candidates.single.collectionPosition,5);
    expect(rows[1].title!.id,'a1');
    expect(rows[1].candidates,isEmpty); // global per-category dedup
    expect(rows[2].candidates.map((v)=>v.title.id),['a2','b2']);
    expect(rows[2].candidates.map((v)=>v.collectionPosition),[1,2]);
    expect(rows[2].candidates.map((v)=>v.recommendationIndex),[2,3]);
    expect(rows[3].candidates,isEmpty);
    expect(rows[4].candidates,isEmpty); // completed direct skipped
    expect(queues.recommendationSequence('anime').map((v)=>v.title.id),
      ['a1','a2','b2']);
    expect(queues.placementsForTitle('a2').single.outerPosition,3);
    expect(queues.placementsForTitle('a4'),isEmpty);
    expect(queues.placementsForTitle('not-in-order'),isEmpty);
  });

  test('category force and completed-rule include stay isolated',(){
    final reader=NativeM42MixedQueues(decodeMediaFlowState(fixture()));
    final books=reader.slotsForCategory('books');
    expect(books.length,2);
    expect(books.first.candidates.single.title.id,'b1');
    final ids=books[1].candidates.map((v)=>v.title.id).toList();
    expect(ids,['a2','a3','a1']); // b1 already directly ordered
    expect(books[1].candidates.first.outerPosition,2);
    expect(reader.recommendationSequence('books').map((v)=>v.title.id),
      ['b1','a2','a3','a1']);
    final a1=reader.placementsForTitle('a1');
    expect(a1.map((v)=>v.outerPosition),[1,2]);
    expect(a1.map((v)=>v.assignmentId),['assignment1','assignment2']);
  });

  test('missing token fallback sorts new assignments by createdAt then ID',(){
    final raw=fixture();
    final order=raw['orderPlan'] as Map;
    order['categoryQueues']={};
    final q=NativeM42MixedQueues(decodeMediaFlowState(raw));
    expect(q.tokensForCategory('anime'),[
      't:a1','t:a2','t:a3','c:assignment1','c:assignment3']);
    expect(q.tokensForCategory('books'),['t:b1','c:assignment2']);
    expect(order['categoryQueues'],isEmpty);
  });

  test('ambiguous IDs and dangling queue assignments excluded safely',(){
    final raw=fixture();
    (raw['library'] as List).add({
      'id':'a1','title':'Duplicate','categoryId':'anime'});
    (raw['collections'] as List).add({
      'id':'c2','title':'Duplicate Collection','titleIds':[]});
    final assignments=(raw['orderPlan'] as Map)['collectionAssignments'] as List;
    assignments.add({
      'id':'assignment1','collectionId':'c1','categoryId':'anime'});
    assignments.add({
      'id':'lost','collectionId':'no-longer-here','categoryId':'anime'});
    final q=NativeM42MixedQueues(decodeMediaFlowState(raw));
    expect(q.tokensForCategory('anime'),['t:a2','t:a3']);
    expect(q.placementsForTitle('a1'),isEmpty);
    expect(q.diagnosticsForCategory('anime').join(' '),
      contains('ambiguous'));
    expect(q.diagnosticsForCategory('anime').join(' '),
      contains('unresolved'));
  });

  test('empty categories, invalid queue tokens, no cloud writer',(){
    final catalog=decodeMediaFlowState({
      'library':[],'categories':[],
      'orderPlan':{'titleIds':[],
        'categoryQueues':{'strange':['junk','c:lost','t:ghost']}},
    });
    final q=NativeM42MixedQueues(catalog);
    expect(q.categoryIds,['strange']);
    expect(q.slotsForCategory('strange'),isEmpty);
    expect(q.diagnosticsForCategory('strange').length,3);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('50,000 Library titles maintain bounded queue projection',(){
    final raw={
      'categories':[{'id':'anime','name':'Anime'}],
      'library':[
        for (var i=0;i<50000;i++)
          {'id':'title-$i','title':'Title $i','categoryId':'anime',
            'status':'active','progress':0,'total':12},
      ],
      'collections':[
        {'id':'huge','title':'Huge Collection',
          'titleIds':[for(var i=0;i<10000;i++)'title-$i']},
      ],
      'orderPlan':{
        'titleIds':['title-20000'],
        'collectionAssignments':[
          {'id':'a','collectionId':'huge','categoryId':'anime',
            'categoryRule':'match','completedRule':'skip'},
        ],
        'categoryQueues':{'anime':['c:a','t:title-20000']},
      },
    };
    final catalog=decodeMediaFlowState(raw);
    final q=NativeM42MixedQueues(catalog);
    final slots=q.slotsForCategory('anime');
    expect(slots.length,2);
    expect(slots.first.candidates.length,10000);
    expect(slots[1].candidates.length,1);
    expect(slots.first.candidates.last.collectionPosition,10000);
    expect(slots.first.candidates.last.outerPosition,1);
    expect(catalog.collections.single.titleIds.length,10000);
  }, timeout:const Timeout(Duration(minutes:2)));

  testWidgets('native UI switches between legacy direct and mixed queues',(
      tester) async {
    final catalog=decodeMediaFlowState(fixture());
    tester.view.physicalSize=const Size(960,1280);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home:Scaffold(body:PersonalOrderScreen(
        repository:_TypedRepo(catalog)))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('personal-order-entries')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m42-mixed-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m42-mixed-queue-entries')),findsOneWidget);
    expect(find.byKey(const Key('m42-readonly-disclaimer')),findsOneWidget);
    expect(find.text('Favorite Worlds'),findsOneWidget);
    expect(find.text('Next Arc'),findsOneWidget);
    await tester.tap(find.byKey(const Key('m42-collection-c:assignment1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Collection member #5'),findsOneWidget);
    expect(find.text('Slot 1'),findsWidgets);
    await tester.tap(find.byKey(const Key('m42-direct-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('personal-order-entries')),findsOneWidget);
  });
}

class _TypedRepo extends MediaFlowLibraryRepository {
  _TypedRepo(this.catalog);
  final MediaFlowCatalog catalog;
  @override
  Future<MediaFlowCatalog> load() async => catalog;
}
