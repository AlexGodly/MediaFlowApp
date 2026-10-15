import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/personal_order/personal_order_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m42_mixed_queue.dart';
import 'package:mediaflow_app/services/native_m44_personal_order_plan.dart';

MediaFlowCatalog m45Fixture({bool duplicateTitle=false})=>
  decodeMediaFlowState({
    'categories':[
      {'id':'anime','name':'Anime'},
      {'id':'books','name':'Books'},
    ],
    'library':[
      {'id':'a','title':'Alpha','categoryId':'anime',
        'status':'active','progress':0,'total':12},
      {'id':'b','title':'Beta','categoryId':'books',
        'status':'active','progress':0,'total':12},
      {'id':'c','title':'Gamma','categoryId':'anime',
        'status':'active','progress':0,'total':12},
      {'id':'d','title':'Delta','categoryId':'books',
        'status':'active','progress':0,'total':12},
      {'id':'e','title':'Epsilon','categoryId':'anime',
        'status':'active','progress':0,'total':12},
      {'id':'f','title':'Zeta','categoryId':'books',
        'status':'active','progress':0,'total':12},
      if(duplicateTitle)
        {'id':'e','title':'Duplicated Epsilon','categoryId':'anime'},
    ],
    'collections':[
      {'id':'set','title':'Favorite Stories',
        'titleIds':['c','a','e']},
    ],
    'orderPlan':{
      'titleIds':['a','b','c','d'],
      'categoryQueues':{
        'anime':['t:a','c:assigned','t:c'],
        'books':['t:b','t:d'],
      },
      'collectionAssignments':[
        {'id':'assigned','collectionId':'set','categoryId':'anime',
          'categoryRule':'match','completedRule':'skip',
          'traversedTitleIds':[],'createdAt':100},
      ],
      'unknownOriginalField':{'retain':true},
    },
    'sessions':[{'id':'history1','date':'2026-10-01'}],
  });

NativeM44PersonalOrderPlan m45Plan(MediaFlowCatalog snapshot)=>
  NativeM44PersonalOrderPlan(ownerId:'owner')
    ..observe(snapshot,currentOwnerId:'owner');

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.snapshot);
  final MediaFlowCatalog snapshot;
  @override
  Future<MediaFlowCatalog> load() async=>snapshot;
}

void main(){
  test('bulk additions follow Library order and preserve existing references',(){
    final source=m45Fixture();
    final p=m45Plan(source);
    p.addDirectTitles(['f','e','f']);
    expect(p.directTitleIds,['a','b','c','d','e','f']);
    expect(source.personalOrderIds,['a','b','c','d']);
    final preview=p.previewCatalog();
    expect(preview.personalOrderIds,['a','b','c','d','e','f']);
    expect(preview.library,same(source.library));
    expect(preview.sessions,same(source.sessions));
    expect(preview.collections,same(source.collections));
    expect(preview.collectionAssignments,same(source.collectionAssignments));
    expect(preview.prioritizePersonalOrder,source.prioritizePersonalOrder);
    expect(p.mayUpload,false);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    expect(p.pendingOperations,1); // one batch = one checkpoint
    p.addDirectTitles(['a','b']);
    expect(p.pendingOperations,1); // duplicate adds are a no-op
    p.undo();
    expect(p.directTitleIds,['a','b','c','d']);
    expect(p.hasChanges,false);
    p.redo();
    expect(p.directTitleIds,['a','b','c','d','e','f']);
    p.dispose();
  });

  test('category-only reorder leaves unrelated global title slots stable',(){
    final original=m45Fixture();
    final p=m45Plan(original);
    p.positionDirectTitle('c',1,categoryId:'anime');
    expect(p.directTitleIds,['c','b','a','d']);
    expect(p.tokens('anime'),['t:c','c:assigned','t:a']);
    expect(p.tokens('books'),['t:b','t:d']);
    p.moveDirectTitle('a',-1,categoryId:'anime');
    expect(p.directTitleIds,['a','b','c','d']);
    expect(p.hasChanges,false);
    p.undo();
    expect(p.directTitleIds,['c','b','a','d']);
    p.undo();
    expect(p.directTitleIds,original.personalOrderIds);
    p.redo();
    expect(p.directTitleIds,['c','b','a','d']);
    expect(original.categoryQueues['anime'],['t:a','c:assigned','t:c']);
    expect(original.personalOrderIds,['a','b','c','d']);
    p.dispose();
  });

  test('global order move crosses categories without changing titles',(){
    final source=m45Fixture();
    final p=m45Plan(source);
    p.positionDirectTitle('d',1);
    expect(p.directTitleIds,['d','a','b','c']);
    expect(p.tokens('books'),['t:d','t:b']);
    p.moveDirectTitle('a',1);
    expect(p.directTitleIds,['d','b','a','c']);
    expect(p.tokens('anime'),['t:a','c:assigned','t:c']);
    expect(()=>p.positionDirectTitle('a',0),throwsFormatException);
    expect(()=>p.positionDirectTitle('a',99),throwsFormatException);
    expect(()=>p.positionDirectTitle('a',1,categoryId:'books'),
      throwsStateError);
    p.dispose();
  });

  test('bulk remove is reversible and never removes Library or Collection',(){
    final original=m45Fixture();
    final p=m45Plan(original);
    p.removeDirectTitles(['c','a']);
    expect(p.directTitleIds,['b','d']);
    expect(p.tokens('anime'),['c:assigned']);
    expect(NativeM42MixedQueues(p.previewCatalog())
      .recommendationSequence('anime').map((e)=>e.title.id),
      ['c','a','e']);
    expect(p.previewCatalog().collections.single.titleIds,['c','a','e']);
    expect(p.previewCatalog().library.length,6);
    p.undo();
    expect(p.directTitleIds,original.personalOrderIds);
    p.redo();
    expect(p.directTitleIds,['b','d']);
    p.discard();
    expect(p.previewCatalog(),same(original));
    expect(p.canUndo,false);
    p.dispose();
  });

  test('interleaved assignment/title operations share ONE atomic undo stack',(){
    final original=m45Fixture();
    final p=m45Plan(original);
    p.addDirectTitles(['e']);
    p.setRules('assigned',categoryRule:'force');
    p.moveDirectTitle('e',-1,categoryId:'anime');
    expect(p.directTitleIds,['a','b','e','d','c']);
    expect(p.previewCatalog().collectionAssignments.single.categoryRule,
      'force');
    p.undo();
    expect(p.directTitleIds,['a','b','c','d','e']);
    p.undo();
    expect(p.previewCatalog().collectionAssignments.single.categoryRule,
      'match');
    p.undo();
    expect(p.directTitleIds,original.personalOrderIds);
    expect(p.hasChanges,false);
    p.redo();
    p.redo();
    p.redo();
    expect(p.directTitleIds,['a','b','e','d','c']);
    expect(p.previewCatalog().collectionAssignments.single.categoryRule,
      'force');
    p.dispose();
  });

  test('picker isolates category/membership, caps results, refuses ambiguity',(){
    final original=m45Fixture(duplicateTitle:true);
    final p=m45Plan(original);
    expect(p.browseDirectTitlePicker(
      categoryId:'anime',search:'epsilon'),isEmpty);
    expect(p.browseDirectTitlePicker(
      categoryId:'books',search:'zeta').single.id,'f');
    expect(p.browseDirectTitlePicker(
      categoryId:'anime',alreadyOrdered:true).map((v)=>v.id),['a','c']);
    expect(()=>p.addDirectTitles(['e']),throwsStateError);
    expect(()=>p.addDirectTitles(['not-real']),throwsStateError);
    expect(()=>p.addDirectTitles(['']),throwsStateError);
    expect(()=>p.addDirectTitles([]),throwsFormatException);
    expect(()=>p.addDirectTitles(List.generate(201,(i)=>'id$i')),
      throwsFormatException);
    expect(()=>p.removeDirectTitles(['e']),throwsStateError);
    expect(()=>p.removeDirectTitles([]),throwsFormatException);
    expect(()=>p.browseDirectTitlePicker(limit:0),throwsFormatException);
    expect(p.hasChanges,false);
    p.dispose();
  });

  test('stale snapshot and owner switch quarantine direct edits, no rebase',(){
    final first=m45Fixture(),next=m45Fixture();
    final p=m45Plan(first);
    p.addDirectTitles(['e']);
    p.observe(next,currentOwnerId:'owner');
    expect(p.stale,true);
    expect(()=>p.addDirectTitles(['f']),throwsStateError);
    expect(()=>p.undo(),throwsStateError);
    expect(()=>p.previewCatalog(),throwsStateError);
    expect(first.personalOrderIds,['a','b','c','d']);
    p.discard();
    expect(p.previewCatalog(),same(next));
    p.addDirectTitles(['e']);
    p.observe(next,currentOwnerId:'another-owner');
    expect(p.canEdit,false);
    expect(()=>p.removeDirectTitles(['e']),throwsStateError);
    p.discard();
    expect(p.stale,true);
    expect(p.source,isNull);
    p.dispose();
  });

  test('100,000 title source keeps projections bounded, batch cap and undo',(){
    final source=decodeMediaFlowState({
      'categories':[{'id':'anime','name':'Anime'}],
      'library':[
        for(var i=0;i<100000;i++)
          {'id':'id$i','title':'Title $i','categoryId':'anime'},
      ],
      'collections':[],
      'orderPlan':{'titleIds':['id0','id1','id2']},
    });
    final p=m45Plan(source);
    expect(p.browseDirectTitlePicker(search:'Title 99',limit:40)
      .length,40);
    p.addDirectTitles(List.generate(200,(i)=>'id${i+100}').reversed);
    expect(p.directTitleIds.length,203);
    expect(p.directTitleIds[3],'id100');
    expect(p.directTitleIds.last,'id299');
    final preview=p.previewCatalog();
    expect(preview.library,same(source.library));
    expect(p.previewCatalog(),same(preview));
    p.removeDirectTitles(List.generate(200,(i)=>'id${i+100}'));
    expect(p.directTitleIds,['id0','id1','id2']);
    p.undo();
    expect(p.directTitleIds.length,203);
    p.undo();
    expect(p.hasChanges,false);
    expect(source.personalOrderIds,['id0','id1','id2']);
    p.dispose();
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('UI bulk Add Library titles / Undo / preview',(
      tester) async{
    tester.view.physicalSize=const Size(980,1450);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original=m45Fixture(),p=m45Plan(m45Fixture());
    // Build using the same exact catalog instance that the plan observes.
    p.discard();
    final plan=NativeM44PersonalOrderPlan(ownerId:'user');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PersonalOrderScreen(
        repository:_Repo(original),plan:plan,currentOwnerId:'user'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-plan-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m45-direct-title-rows')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m45-available-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m45-row-e')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m45-check-e')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-apply-bulk')));
    await tester.pumpAndSettle();
    expect(plan.directTitleIds,['a','b','c','d','e']);
    expect(original.personalOrderIds,['a','b','c','d']);
    await tester.tap(find.byKey(const Key('m45-undo')));
    await tester.pumpAndSettle();
    expect(plan.directTitleIds,['a','b','c','d']);
    await tester.tap(find.byKey(const Key('m45-redo')));
    await tester.pumpAndSettle();
    expect(plan.directTitleIds,['a','b','c','d','e']);
    await tester.tap(find.byKey(const Key('m45-preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m44-preview-toggle')),findsOneWidget);
    expect(find.byKey(const Key('m42-mixed-queue-entries')),findsOneWidget);
    plan.dispose();
    p.dispose();
  });

  testWidgets('UI confirmed bulk remove keeps source untouched',(
      tester) async {
    tester.view.physicalSize=const Size(980,1450);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final original=m45Fixture();
    final plan=NativeM44PersonalOrderPlan(ownerId:'user');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PersonalOrderScreen(
        repository:_Repo(original),plan:plan,currentOwnerId:'user'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-plan-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-check-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-apply-bulk')));
    await tester.pumpAndSettle();
    expect(find.text('Remove 1 direct order entries?'),findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(plan.directTitleIds,['a','b','c','d']);
    await tester.tap(find.byKey(const Key('m45-apply-bulk')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-confirm-bulk')));
    await tester.pumpAndSettle();
    expect(plan.directTitleIds,['b','c','d']);
    expect(original.library.length,6);
    expect(original.personalOrderIds,['a','b','c','d']);
    plan.dispose();
  });
}
