import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/personal_order/personal_order_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m43_recommendation_audit.dart';

Map<String,dynamic> m43Fixture({bool? prioritize=true}) => {
  'categories':[
    {'id':'anime','name':'Anime'},
    {'id':'books','name':'Books'},
  ],
  'settings':{
    if(prioritize!=null) 'prioritizePersonalOrder':prioritize,
  },
  'library':[
    {'id':'x','title':'Test Apple','categoryId':'anime',
      'status':'active','progress':2,'total':10},
    {'id':'y','title':'Test Banana','categoryId':'anime',
      'status':'active','progress':0,'total':10},
    {'id':'z','title':'Completed Season','categoryId':'anime',
      'status':'completed','progress':10,'total':10},
    {'id':'other','title':'Book Force','categoryId':'books',
      'status':'active','progress':0,'total':10},
    {'id':'dropped','title':'Dropped Show','categoryId':'anime',
      'status':'dropped','progress':1,'total':10},
    {'id':'progressDone','title':'Finished by Units','categoryId':'anime',
      'status':'active','progress':10,'total':10},
  ],
  'collections':[
    {'id':'c1','title':'Favorite Queue',
      'titleIds':['y','other','z','x','dropped','progressDone']},
    {'id':'c2','title':'Force Queue',
      'titleIds':['z','other','x']},
  ],
  'orderPlan':{
    'titleIds':['x','y','other'],
    'categoryQueues':{
      'anime':['c:a1','t:x','c:a2','t:y'],
      'books':['t:other'],
    },
    'collectionAssignments':[
      {'id':'a1','collectionId':'c1','categoryId':'anime',
        'categoryRule':'match','completedRule':'skip',
        'traversedTitleIds':['y'],'createdAt':100},
      {'id':'a2','collectionId':'c2','categoryId':'anime',
        'categoryRule':'force','completedRule':'include',
        'traversedTitleIds':[],'createdAt':200},
    ],
  },
};

class _Repository extends MediaFlowLibraryRepository {
  _Repository(this.data);
  final MediaFlowCatalog data;
  @override
  Future<MediaFlowCatalog> load() async=>data;
}

void main() {
  test('priority tri-state is read-only and survives actual state decode',(){
    expect(decodeMediaFlowState(m43Fixture()).prioritizePersonalOrder,true);
    expect(decodeMediaFlowState(
      m43Fixture(prioritize:false)).prioritizePersonalOrder,false);
    expect(decodeMediaFlowState(
      m43Fixture(prioritize:null)).prioritizePersonalOrder,isNull);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('first v287 recommendation has exact source, slot and member rank',(){
    final catalog=decodeMediaFlowState(m43Fixture());
    final audit=NativeM43RecommendationAudit(catalog);
    final anime=audit.forCategory('anime');
    expect(anime.recommendations.map((e)=>e.title.id),
      ['x','z','other','y']);
    final first=anime.firstEligible()!;
    expect(first.title.id,'x');
    expect(first.fromCollection,true);
    expect(first.assignmentId,'a1');
    expect(first.outerPosition,1);
    expect(first.collectionPosition,4);
    expect(first.recommendationIndex,1);
    expect(anime.slots.length,4);
    expect(anime.ineligibleOccurrences,greaterThanOrEqualTo(5));
    expect(catalog.collectionAssignments.first.traversedTitleIds,['y']);
    expect(audit.priorityEnabled,true);
  });

  test('multiple title placements explain traversed, completed and dedup',(){
    final audit=NativeM43RecommendationAudit(
      decodeMediaFlowState(m43Fixture()));
    final x=audit.placementsForTitle('x');
    expect(x.length,3);
    expect(x.map((e)=>e.slotPosition),[1,2,3]);
    expect(x.map((e)=>e.recommendationIndex),[1,null,null]);
    expect(x[1].reason,contains('Already recommended'));
    expect(x[2].reason,contains('Already recommended'));
    expect(x.first.directSavedPosition,1);

    final y=audit.placementsForTitle('y');
    expect(y.map((e)=>e.reason).first,contains('traversed'));
    expect(y.last.recommendationIndex,4);
    expect(y.last.slotPosition,4);

    final z=audit.placementsForTitle('z');
    expect(z.first.reason,contains('Completed title skipped'));
    expect(z.last.recommendationIndex,2);
    expect(z.last.collectionName,'Force Queue');

    final other=audit.placementsForTitle('other');
    expect(other.first.reason,contains('Category does not match'));
    expect(other.where((e)=>e.eligible).map((e)=>e.categoryId),
      ['anime','books']);
    expect(other.where((e)=>e.eligible).map((e)=>e.slotPosition),
      [3,1]);
    expect(audit.placementsForTitle('unknown'),isEmpty);
  });

  test('skips dropped and progress-completed titles, never guesses rank',(){
    final audit=NativeM43RecommendationAudit(
      decodeMediaFlowState(m43Fixture()));
    final dropped=audit.placementsForTitle('dropped');
    expect(dropped.single.eligible,false);
    expect(dropped.single.reason,'Dropped title');
    final complete=audit.placementsForTitle('progressDone');
    expect(complete.single.reason,'Completed title skipped by Collection rule');
    expect(complete.single.recommendationIndex,isNull);
    expect(audit.forCategory('anime').unresolvedMembers,0);
  });

  test('exclusion preview mirrors v180 queue-only filtering, not fallback',(){
    final audit=NativeM43RecommendationAudit(
      decodeMediaFlowState(m43Fixture()));
    final original=audit.forCategory('anime').firstEligible()!;
    final after=audit.firstEligibleWithExclusions('anime',{'x'})!;
    expect(original.title.id,'x');
    expect(after.title.id,'z');
    expect(after.recommendationIndex,2); // never renumber stored queue
    expect(audit.firstEligibleWithExclusions('anime',
      {'x','z','other','y'}),isNull);
    expect(audit.forCategory('anime').firstEligible()!.title.id,'x');
    expect(audit.forCategory('anime'),
      same(audit.forCategory('anime'))); // cache
  });

  test('search is capped and does not materialize all Library results',(){
    final audit=NativeM43RecommendationAudit(
      decodeMediaFlowState(m43Fixture()));
    expect(audit.searchTitles('TEST').map((t)=>t.id),['x','y']);
    expect(audit.searchTitles('x').single.id,'x');
    expect(audit.searchTitles(''),isEmpty);
    expect(()=>audit.searchTitles('Test',limit:0),throwsFormatException);
  });

  test('large account renders only requested category evidence',(){
    final raw={
      'categories':[{'id':'anime','name':'Anime'}],
      'library':[
        for(var i=0;i<50000;i++)
          {'id':'title-$i','title':'Title $i','categoryId':'anime',
            'status':'active','progress':0,'total':12},
      ],
      'collections':[
        {'id':'huge','title':'Large Collection',
          'titleIds':[for(var i=0;i<7000;i++)'title-$i']},
      ],
      'orderPlan':{
        'titleIds':['title-48000'],
        'categoryQueues':{'anime':['c:large','t:title-48000']},
        'collectionAssignments':[
          {'id':'large','collectionId':'huge','categoryId':'anime',
            'categoryRule':'match','completedRule':'skip'},
        ],
      },
    };
    final catalog=decodeMediaFlowState(raw);
    final audit=NativeM43RecommendationAudit(catalog);
    final category=audit.forCategory('anime');
    expect(category.recommendations.length,7001);
    expect(category.placements['title-6999']!.single.memberPosition,7000);
    expect(category.firstEligible()!.title.id,'title-0');
    expect(audit.placementsForTitle('title-48000').single
      .directSavedPosition,1);
    expect(audit.searchTitles('title-1',limit:10).length,10);
    expect(catalog.collections.single.titleIds.length,7000);
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('first candidate jumps to its exact Collection queue block',(
      tester) async {
    tester.view.physicalSize=const Size(1000,1450);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo=_Repository(decodeMediaFlowState(m43Fixture()));
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PersonalOrderScreen(repository:repo))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m42-mixed-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m43-first-eligible')),findsOneWidget);
    expect(find.textContaining('Test Apple · recommendation #1'),
      findsOneWidget);
    await tester.tap(find.byKey(const Key('m43-jump-first')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m43-clear-focus')),findsOneWidget);
    expect(find.byKey(const Key('m43-focused-c:a1')),findsOneWidget);
    expect(find.byKey(const Key('m42-member-a1-x')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m43-clear-focus')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m42-collection-c:a1')),findsOneWidget);
    expect(repo.data.collectionAssignments.first.traversedTitleIds,['y']);
  });

  testWidgets('rank lookup shows skipped reasons and navigates to source',(
      tester) async {
    tester.view.physicalSize=const Size(1000,1450);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo=_Repository(decodeMediaFlowState(m43Fixture()));
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PersonalOrderScreen(repository:repo))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m42-mixed-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m43-ranking-explorer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('m43-rank-search')),
      'Test Apple');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m43-title-x')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 saved position(s)'),findsOneWidget);
    expect(find.textContaining('Already recommended'),findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('m43-jump-anime-t:x')));
    await tester.tap(find.byKey(const Key('m43-jump-anime-t:x')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m43-clear-focus')),findsOneWidget);
    expect(find.byKey(const Key('m42-slot-t:x')),findsOneWidget);
  });
}
