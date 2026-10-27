import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/personal_order/personal_order_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m44_personal_order_plan.dart';
import 'package:mediaflow_app/services/native_m48_task_coordination.dart';

Map<String,dynamic> fixture48({
  bool? priority=true,bool force=true,bool active=true,
  int filler=0,
}) => {
  'categories':[
    {'id':'anime','name':'Anime'},
    {'id':'books','name':'Books'},
  ],
  'settings':{if(priority!=null) 'prioritizePersonalOrder':priority},
  'sessionActive':active,
  if(active) 'currentTask':{
    'categoryId':'anime','title':'Watch anime','low':2,'high':3,
    'unit':'episodes','reasons':[],
  },
  'library':[
    {'id':'a','title':'Alpha','categoryId':'anime',
      'status':'active','progress':0,'total':10},
    {'id':'b','title':'Beta','categoryId':'anime',
      'status':'active','progress':1,'total':10},
    {'id':'book','title':'Book','categoryId':'books',
      'status':'active','progress':0,'total':10},
    {'id':'done','title':'Done','categoryId':'anime',
      'status':'completed','progress':10,'total':10},
    {'id':'drop','title':'Dropped','categoryId':'anime',
      'status':'dropped','progress':0,'total':10},
    for(var i=0;i<filler;i++)
      {'id':'extra$i','title':'Extra $i','categoryId':'anime',
        'status':'active','progress':0,'total':10},
  ],
  'collections':[
    {'id':'c','title':'Stories',
      'titleIds':['b','book','done','drop','a']},
  ],
  'orderPlan':{
    'titleIds':['a','b','book'],
    'categoryQueues':{
      'anime':['c:source','t:a','t:b'],
      'books':['t:book'],
    },
    'collectionAssignments':[
      {'id':'source','collectionId':'c','categoryId':'anime',
        'categoryRule':force?'force':'match',
        'completedRule':'skip','createdAt':1,
        'traversedTitleIds':[]},
    ],
  },
};

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.snapshot);
  final MediaFlowCatalog snapshot;
  @override
  Future<MediaFlowCatalog> load() async => snapshot;
}

void main() {
  test('priority tri-state and current task context do not imply selection',(){
    for(final enabled in [true,false,null]) {
      final catalog=decodeMediaFlowState(fixture48(priority:enabled));
      final engine=NativeM48TaskCoordination(catalog);
      final view=engine.preview('anime');
      expect(view.currentTaskMatchesCategory,true);
      expect(view.sessionActive,true);
      expect(view.first!.title.id,'b');
      expect(view.canInferTaskSelection,enabled==true);
      expect(view.fallbackOrUnknown,enabled!=true);
      expect(catalog.currentTask!.categoryId,'anime');
      expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    }
    final inactive=NativeM48TaskCoordination(
      decodeMediaFlowState(fixture48(active:false)));
    expect(inactive.activeCategoryId,'');
    expect(inactive.preview('anime').currentTaskMatchesCategory,false);
  });

  test('v287 force queue, deduplication and priority order are preserved',(){
    final catalog=decodeMediaFlowState(fixture48());
    final service=NativeM48TaskCoordination(catalog);
    final result=service.preview('anime',limit:5);
    expect(result.candidates.map((c)=>c.title.id),['b','book','a']);
    expect(result.eligibleCount,3);
    expect(result.first!.assignmentId,'source');
    expect(result.first!.outerPosition,1);
    expect(result.first!.collectionPosition,1);
    expect(result.candidates[1].title.categoryId,'books');
    expect(service.preview('books').first!.title.id,'book');
    expect(catalog.personalOrderIds,['a','b','book']);
    expect(catalog.collections.first.titleIds.length,5);
  });

  test('hypothetical exclusions respect existing ranks and never persist',(){
    final service=NativeM48TaskCoordination(
      decodeMediaFlowState(fixture48()));
    final excluded=service.preview('anime',excludedIds:{'b','book'});
    expect(excluded.first!.title.id,'a');
    expect(excluded.first!.recommendationIndex,3);
    expect(excluded.excludedCount,2);
    expect(service.preview('anime',excludedIds:{'a','b','book'}).first,
      isNull);
    expect(()=>service.preview('anime',limit:0),throwsFormatException);
    expect(()=>service.preview('anime',limit:21),throwsFormatException);
    expect(()=>service.preview('anime',excludedIds:{
      for(var i=0;i<201;i++) 'fake$i',
    }),throwsFormatException);
    expect(()=>service.preview('missing'),throwsStateError);
    expect(service.preview('anime').first!.title.id,'b');
  });

  test('simulated successful Collection consumption advances only that block',(){
    final source=decodeMediaFlowState(fixture48());
    final service=NativeM48TaskCoordination(source);
    final first=service.preview('anime').first!;
    final result=service.afterSuccessfulCollectionConsumption('anime',first);
    expect(result.wouldAdvanceCollection,true);
    expect(result.assignmentId,'source');
    expect(result.before.first!.title.id,'b');
    expect(result.after.first!.title.id,'book');
    expect(result.after.first!.recommendationIndex,1);
    expect(source.collectionAssignments.single.traversedTitleIds,isEmpty);
    expect(source.personalOrderIds,['a','b','book']);
    expect(source.library.length,5);
    expect(source.sessions,isEmpty);
    expect(source.currentTask!.categoryId,'anime');
    expect(service.preview('anime').first!.title.id,'b');
    expect(()=>service.afterSuccessfulCollectionConsumption('books',first),
      throwsStateError);
    expect(()=>service.afterSuccessfulCollectionConsumption('anime',first,
      excludedIds:{'b'}),throwsStateError);
  });

  test('direct title does not advance Collection traversal',(){
    final source=decodeMediaFlowState(fixture48(force:false));
    final engine=NativeM48TaskCoordination(source);
    final entry=engine.preview('anime').candidates
      .firstWhere((c)=>c.title.id=='a');
    // Both titles are already supplied by the Collection, so a separate
    // minimal queue is needed to test a genuine direct-only candidate.
    final directOnly=decodeMediaFlowState({
      'categories':[{'id':'anime','name':'Anime'}],
      'library':[{'id':'x','title':'X','categoryId':'anime',
        'status':'active','progress':0,'total':12}],
      'orderPlan':{'titleIds':['x']},
      'settings':{'prioritizePersonalOrder':true},
    });
    expect(entry.fromCollection,true);
    final e=NativeM48TaskCoordination(directOnly);
    final first=e.preview('anime').first!;
    expect(first.fromCollection,false);
    final result=e.afterSuccessfulCollectionConsumption('anime',first);
    expect(result.wouldAdvanceCollection,false);
    expect(result.assignmentId,'');
    expect(identical(result.before,result.after),true);
  });

  test('local draft queue can be compared without cross-account or cloud edits',(){
    final source=decodeMediaFlowState(fixture48());
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(source,currentOwnerId:'owner');
    final saved=NativeM48TaskCoordination(source).preview('anime');
    plan.positionMixedToken('anime','t:a',1);
    final projected=plan.previewCatalog();
    final preview=NativeM48TaskCoordination(projected).preview('anime');
    expect(saved.first!.title.id,'b');
    expect(preview.first!.title.id,'a');
    expect(projected.library,same(source.library));
    expect(projected.sessions,same(source.sessions));
    expect(source.categoryQueues['anime']!.first,'c:source');
    plan.observe(decodeMediaFlowState(fixture48()),currentOwnerId:'owner');
    expect(plan.stale,true);
    expect(()=>plan.previewCatalog(),throwsStateError);
    expect(plan.mayUpload,false);
    plan.dispose();
  });

  test('100k Library items do not cause task/history mutations',(){
    final source=decodeMediaFlowState(fixture48(filler:99995));
    final engine=NativeM48TaskCoordination(source);
    final before=engine.preview('anime');
    final after=engine.afterSuccessfulCollectionConsumption(
      'anime',before.first!);
    expect(source.library.length,100000);
    expect(before.eligibleCount,3);
    expect(after.after.first!.title.id,'book');
    expect(source.collectionAssignments.single.traversedTitleIds,isEmpty);
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('UI shows policy, hypothetical rerolls and saved/draft compare',
      (tester) async {
    tester.view.physicalSize=const Size(1050,1600);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source=decodeMediaFlowState(fixture48());
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PersonalOrderScreen(repository:_Repo(source),
        plan:plan,currentOwnerId:'owner'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m42-mixed-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m48-task-coordination')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m48-priority-state')),findsOneWidget);
    expect(find.textContaining('Beta · recommendation #1'),findsWidgets);
    await tester.enterText(find.byKey(const Key('m48-exclusion-input')),'b');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m48-queue-count')),findsOneWidget);
    expect(find.textContaining('Book · recommendation #2'),findsWidgets);
    await tester.tap(find.byKey(const Key('m47-edit-toggle')));
    await tester.pumpAndSettle();
    plan.positionMixedToken('anime','t:a',1);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m48-saved-first')),findsOneWidget);
    expect(find.byKey(const Key('m48-local-first')),findsOneWidget);
    expect(source.personalOrderIds,['a','b','book']);
    plan.dispose();
  });
}
