import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/personal_order/personal_order_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m42_mixed_queue.dart';
import 'package:mediaflow_app/services/native_m44_personal_order_plan.dart';

MediaFlowCatalog m44Fixture({
  bool duplicateCollections=false,
  bool duplicateAssignments=false,
  bool duplicateCategories=false,
}) => decodeMediaFlowState({
  'categories':[
    {'id':'anime','name':'Anime'},
    {'id':'books','name':'Books'},
    if(duplicateCategories) {'id':'anime','name':'Duplicate Anime'},
  ],
  'library':[
    {'id':'t1','title':'First','categoryId':'anime',
      'status':'active','priority':'high','progress':0,'total':10},
    {'id':'t2','title':'Second','categoryId':'anime',
      'status':'active','priority':'high','progress':0,'total':10},
    {'id':'t3','title':'Novel','categoryId':'books',
      'status':'active','priority':'high','progress':0,'total':10},
    {'id':'t4','title':'Finished','categoryId':'anime',
      'status':'completed','priority':'high','progress':10,'total':10},
  ],
  'collections':[
    {'id':'c1','title':'Anime Collection',
      'titleIds':['t2','t1','t3','t4'],
      'order':['t2','t1','t3','t4'],
      'otherWebField':{'preserve':true}},
    {'id':'c2','title':'Book Collection','titleIds':['t3','t4']},
    if(duplicateCollections)
      {'id':'c2','title':'Duplicate','titleIds':[]},
  ],
  'sessions':[
    {'id':'h1','categoryId':'anime','minutes':10},
  ],
  'orderPlan':{
    'titleIds':['t1','t2','t3'],
    'categoryQueues':{
      'anime':['c:a1','t:t1','c:a2','t:t2'],
      'books':['t:t3'],
      'unknown':['t:unknown'],
    },
    'collectionAssignments':[
      {'id':'a1','collectionId':'c1','categoryId':'anime',
        'categoryRule':'match','completedRule':'skip','createdAt':10,
        'traversedTitleIds':['t2']},
      {'id':'a2','collectionId':'c2','categoryId':'anime',
        'categoryRule':'force','completedRule':'include','createdAt':20,
        'traversedTitleIds':[]},
      if(duplicateAssignments)
        {'id':'a1','collectionId':'c2','categoryId':'books'},
    ],
    'unknownOrderField':{'mustStay':true},
  },
});

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.snapshot);
  MediaFlowCatalog snapshot;
  @override
  Future<MediaFlowCatalog> load() async => snapshot;
  @override
  Future<MediaFlowCatalog> reload() async => snapshot;
}

void main(){
  test('M44 add creates live references, default rules and no cloud writes',(){
    final base=m44Fixture();
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner');
    plan.observe(base,currentOwnerId:'owner');
    final newId=plan.addCollection('c1','books');
    expect(newId,startsWith('local_m44_'));
    expect(plan.hasChanges,true);
    expect(plan.mayUpload,false);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    final preview=plan.previewCatalog();
    final added=preview.collectionAssignments.last;
    expect(added.collectionId,'c1');
    expect(added.categoryId,'books');
    expect(added.categoryRule,'match');
    expect(added.completedRule,'skip');
    expect(added.traversedTitleIds,isEmpty);
    expect(preview.collectionAssignments.length,3);
    expect(base.collectionAssignments.length,2);
    expect(preview.library,same(base.library));
    expect(preview.collections,same(base.collections));
    expect(preview.sessions,same(base.sessions));
    expect(preview.personalOrderIds,same(base.personalOrderIds));
    expect(preview.categoryQueues['anime'],base.categoryQueues['anime']);
    expect(preview.categoryQueues['unknown'],base.categoryQueues['unknown']);
    expect(plan.tokens('books'),['t:t3','c:$newId']);
    expect(plan.previewCatalog(),same(preview));
    expect(()=>plan.addCollection('c1','books'),throwsStateError);
    plan.dispose();
  });

  test('rules and traversal are reversible preview only',(){
    final base=m44Fixture();
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(base,currentOwnerId:'owner');
    final originals=base.collectionAssignments.first.traversedTitleIds;
    plan.setRules('a1',categoryRule:'force',completedRule:'include');
    final changed=plan.previewCatalog().collectionAssignments.first;
    expect(changed.categoryRule,'force');
    expect(changed.completedRule,'include');
    expect(changed.traversedTitleIds,['t2']);
    expect(NativeM42MixedQueues(plan.previewCatalog())
      .recommendationSequence('anime').map((e)=>e.title.id),
      contains('t3'));
    plan.resetTraversal('a1');
    expect(plan.previewCatalog().collectionAssignments.first.traversedTitleIds,
      isEmpty);
    expect(base.collectionAssignments.first.traversedTitleIds,
      same(originals));
    plan.undo();
    expect(plan.previewCatalog().collectionAssignments.first.traversedTitleIds,
      ['t2']);
    plan.undo();
    expect(plan.hasChanges,false);
    plan.redo();
    plan.redo();
    expect(plan.previewCatalog().collectionAssignments.first.traversedTitleIds,
      isEmpty);
    plan.setRules('a1',categoryRule:'force',completedRule:'include');
    expect(()=>plan.setRules('a1',categoryRule:'illegal'),throwsFormatException);
    expect(()=>plan.setRules('a1',completedRule:'other'),throwsFormatException);
    plan.dispose();
  });

  test('mixed queue moves preserve direct relative slots, undo and redo',(){
    final base=m44Fixture();
    final original=base.categoryQueues['anime']!.toList();
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(base,currentOwnerId:'owner');
    plan.move('a2',-1);
    expect(plan.tokens('anime'),['c:a1','c:a2','t:t1','t:t2']);
    expect(plan.canUndo,true);
    plan.setPosition('a1',4);
    expect(plan.tokens('anime'),['c:a2','t:t1','t:t2','c:a1']);
    plan.undo();
    expect(plan.tokens('anime'),['c:a1','c:a2','t:t1','t:t2']);
    plan.undo();
    expect(plan.tokens('anime'),original);
    expect(plan.hasChanges,false);
    plan.redo();
    plan.redo();
    expect(plan.tokens('anime').last,'c:a1');
    expect(base.categoryQueues['anime'],original);
    expect(()=>plan.setPosition('a1',0),throwsFormatException);
    expect(()=>plan.setPosition('a1',99),throwsFormatException);
    plan.dispose();
  });

  test('remove affects assignment only; discard restores all references',(){
    final base=m44Fixture();
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(base,currentOwnerId:'owner');
    plan.remove('a1');
    expect(plan.previewCatalog().collectionAssignments.map((a)=>a.id),['a2']);
    expect(plan.tokens('anime'),['t:t1','c:a2','t:t2']);
    expect(plan.previewCatalog().collections.length,2);
    expect(plan.previewCatalog().library.length,4);
    plan.undo();
    expect(plan.previewCatalog().collectionAssignments.map((a)=>a.id),
      ['a1','a2']);
    plan.redo();
    plan.discard();
    expect(plan.hasChanges,false);
    expect(plan.previewCatalog(),same(base));
    expect(plan.canUndo,false);
    plan.dispose();
  });

  test('stale source quarantines edits without rebasing or partial commit',(){
    final base=m44Fixture();
    final next=m44Fixture();
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(base,currentOwnerId:'owner');
    plan.setRules('a1',categoryRule:'force');
    plan.observe(next,currentOwnerId:'owner');
    expect(plan.stale,true);
    expect(plan.canEdit,false);
    expect(()=>plan.undo(),throwsStateError);
    expect(()=>plan.move('a1',1),throwsStateError);
    expect(()=>plan.previewCatalog(),throwsStateError);
    expect(base.collectionAssignments.first.categoryRule,'match');
    plan.discard();
    expect(plan.stale,false);
    expect(plan.previewCatalog(),same(next));
    expect(plan.hasChanges,false);
    plan.dispose();
  });

  test('owner switch fails closed without attaching another account state',(){
    final base=m44Fixture();
    final other=m44Fixture();
    final plan=NativeM44PersonalOrderPlan(ownerId:'ownerA')
      ..observe(base,currentOwnerId:'ownerA');
    plan.addCollection('c1','books');
    plan.observe(other,currentOwnerId:'ownerB');
    expect(plan.stale,true);
    expect(plan.canEdit,false);
    expect(()=>plan.addCollection('c2','books'),throwsStateError);
    plan.discard();
    expect(plan.stale,true);
    expect(plan.source,isNull);
    plan.observe(other,currentOwnerId:'ownerA');
    expect(plan.stale,false);
    expect(plan.previewCatalog(),same(other));
    plan.dispose();
  });

  test('ambiguous source identifiers and duplicate category pair reject edits',(){
    final base=m44Fixture(
      duplicateCollections:true,
      duplicateAssignments:true,
      duplicateCategories:true);
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(base,currentOwnerId:'owner');
    expect(()=>plan.addCollection('c2','books'),throwsStateError);
    expect(()=>plan.addCollection('c1','anime'),throwsStateError);
    expect(()=>plan.setRules('a1',categoryRule:'force'),throwsStateError);
    expect(()=>plan.remove('a1'),throwsStateError);
    expect(()=>plan.setPosition('a1',1),throwsStateError);
    expect(()=>plan.addCollection('ghost','books'),throwsStateError);
    expect(()=>plan.availableCollections('anime'),throwsStateError);
    expect(plan.hasChanges,false);
    plan.dispose();
  });

  test('picker bounds and mutation cap prevent runaway queued operations',(){
    final base=m44Fixture();
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(base,currentOwnerId:'owner');
    expect(plan.availableCollections('books').map((c)=>c.id),['c1','c2']);
    expect(plan.availableCollections('anime').map((c)=>c.id),isEmpty);
    expect(plan.availableCollections('books',search:'book').single.id,'c2');
    expect(()=>plan.availableCollections('books',limit:0),throwsFormatException);
    for(var i=0;i<200;i++) {
      plan.setRules('a1',categoryRule:i.isEven?'force':'match');
    }
    expect(plan.pendingOperations,200);
    expect(()=>plan.setRules('a1',categoryRule:'force'),throwsStateError);
    plan.undo();
    expect(plan.pendingOperations,199);
    plan.setRules('a1',categoryRule:'match');
    expect(plan.pendingOperations,200);
    expect(plan.canRedo,false);
    plan.dispose();
  });

  test('large Library/Collection references are not copied or mutated',(){
    final base=decodeMediaFlowState({
      'categories':[{'id':'anime','name':'Anime'}],
      'library':[
        for(var i=0;i<50000;i++)
          {'id':'t$i','title':'Title $i',
            'categoryId':'anime','status':'active','total':12},
      ],
      'collections':[
        {'id':'large','title':'Large Library Queue',
          'titleIds':[for(var i=0;i<9000;i++)'t$i']},
        {'id':'new','title':'New Queue',
          'titleIds':[for(var i=9000;i<18000;i++)'t$i']},
      ],
      'orderPlan':{
        'titleIds':['t10000'],
        'collectionAssignments':[
          {'id':'a','collectionId':'large','categoryId':'anime',
           'categoryRule':'match','completedRule':'skip'},
        ],
        'categoryQueues':{'anime':['c:a','t:t10000']},
      },
    });
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(base,currentOwnerId:'owner');
    final id=plan.addCollection('new','anime');
    final preview=plan.previewCatalog();
    expect(preview.library,same(base.library));
    expect(preview.collections,same(base.collections));
    expect(preview.collectionAssignments.length,2);
    expect(NativeM42MixedQueues(preview)
      .recommendationSequence('anime').length,18000);
    expect(plan.tokens('anime').last,'c:$id');
    plan.dispose();
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('local assignment picker, undo and preview switch work',(
      tester) async {
    tester.view.physicalSize=const Size(1024,1480);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data=m44Fixture();
    final plan=NativeM44PersonalOrderPlan(ownerId:'user');
    await tester.pumpWidget(MaterialApp(
      home:Scaffold(body:PersonalOrderScreen(
        repository:_Repo(data),plan:plan,currentOwnerId:'user'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m44-plan-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m44-assignment-list')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m44-add-assignment')));
    await tester.pumpAndSettle();
    // Category Anime already owns both Collections; switch to Books.
    await tester.tapAt(const Offset(10,10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m44-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Books').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m44-add-assignment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m44-picker-c1')));
    await tester.pumpAndSettle();
    expect(plan.hasChanges,true);
    expect(plan.previewCatalog().collectionAssignments.length,3);
    expect(find.byKey(const Key('m44-undo')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m44-undo')));
    await tester.pumpAndSettle();
    expect(plan.hasChanges,false);
    await tester.tap(find.byKey(const Key('m44-redo')));
    await tester.pumpAndSettle();
    expect(plan.hasChanges,true);
    await tester.tap(find.byKey(const Key('m44-preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m44-preview-toggle')),findsOneWidget);
    expect(find.byKey(const Key('m42-mixed-queue-entries')),findsOneWidget);
    expect(data.collectionAssignments.length,2);
    plan.dispose();
  });

  testWidgets('local rule, moves and removal confirmation are UI accessible',(
      tester) async {
    tester.view.physicalSize=const Size(1024,1600);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data=m44Fixture();
    final plan=NativeM44PersonalOrderPlan(ownerId:'user');
    await tester.pumpWidget(MaterialApp(
      home:Scaffold(body:PersonalOrderScreen(
        repository:_Repo(data),plan:plan,currentOwnerId:'user'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m44-plan-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m44-down-a1')));
    await tester.pumpAndSettle();
    expect(plan.tokens('anime').first,'t:t1');
    await tester.tap(find.byKey(const Key('m44-remove-a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(plan.previewCatalog().collectionAssignments.length,2);
    await tester.tap(find.byKey(const Key('m44-remove-a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm local change'));
    await tester.pumpAndSettle();
    expect(plan.previewCatalog().collectionAssignments.length,1);
    await tester.tap(find.byKey(const Key('m44-undo')));
    await tester.pumpAndSettle();
    expect(plan.previewCatalog().collectionAssignments.length,2);
    plan.dispose();
  });
}
