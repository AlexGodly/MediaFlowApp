import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/personal_order/personal_order_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m42_mixed_queue.dart';
import 'package:mediaflow_app/services/native_m44_personal_order_plan.dart';

MediaFlowCatalog m47Fixture({int members=45,bool duplicate=false}) =>
    decodeMediaFlowState({
      'categories':[
        {'id':'anime','name':'Anime'},
        {'id':'books','name':'Books'},
      ],
      'library':[
        {'id':'a1','title':'Alpha','categoryId':'anime',
          'status':'active','total':12},
        {'id':'a2','title':'Beta','categoryId':'anime',
          'status':'active','total':12},
        {'id':'b1','title':'Novel','categoryId':'books',
          'status':'active','total':12},
        for(var i=0;i<members;i++)
          {'id':'m$i','title':'Member $i','categoryId':'anime',
           'status':'active','total':12},
        if(duplicate) {'id':'a1','title':'Duplicate Alpha',
          'categoryId':'anime'},
      ],
      'collections':[
        {'id':'set','title':'Favorite Episodes',
          'titleIds':[for(var i=0;i<members;i++) 'm$i']},
        {'id':'other','title':'Overlap Queue',
          'titleIds':['m0','m1','a1']},
      ],
      'orderPlan':{
        'titleIds':['a1','b1','a2'],
        'categoryQueues':{
          'anime':['t:a1','c:one','t:a2','c:two'],
          'books':['t:b1'],
        },
        'collectionAssignments':[
          {'id':'one','collectionId':'set','categoryId':'anime',
            'categoryRule':'match','completedRule':'skip','createdAt':1},
          {'id':'two','collectionId':'other','categoryId':'anime',
            'categoryRule':'match','completedRule':'skip','createdAt':2},
        ],
      },
    });

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.catalog);
  final MediaFlowCatalog catalog;
  @override
  Future<MediaFlowCatalog> load() async=>catalog;
}

NativeM44PersonalOrderPlan _plan(MediaFlowCatalog data) =>
    NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(data,currentOwnerId:'owner');

void main() {
  test('direct token crosses Collection block and reorders recommendation',(){
    final original=m47Fixture(members:3);
    final p=_plan(original);
    expect(p.tokens('anime'),['t:a1','c:one','t:a2','c:two']);
    p.positionMixedToken('anime','t:a2',2);
    expect(p.tokens('anime'),['t:a1','t:a2','c:one','c:two']);
    expect(p.directTitleIds,['a1','b1','a2']);
    expect(NativeM42MixedQueues(p.previewCatalog())
      .recommendationSequence('anime').take(3).map((x)=>x.title.id),
      ['a1','a2','m0']);
    expect(p.tokens('books'),['t:b1']);
    expect(original.categoryQueues['anime'],
      ['t:a1','c:one','t:a2','c:two']);
    expect(original.personalOrderIds,['a1','b1','a2']);
    expect(p.mayUpload,false);
    p.undo();
    expect(p.tokens('anime'),original.categoryQueues['anime']);
    expect(p.hasChanges,false);
    p.redo();
    expect(p.tokens('anime')[1],'t:a2');
    p.dispose();
  });

  test('direct crossing direct title changes only category global slots',(){
    final base=m47Fixture(members:2);
    final p=_plan(base);
    p.positionMixedToken('anime','t:a2',1);
    expect(p.tokens('anime'),['t:a2','t:a1','c:one','c:two']);
    expect(p.directTitleIds,['a2','b1','a1']);
    expect(p.previewCatalog().library,same(base.library));
    expect(p.previewCatalog().collections,same(base.collections));
    expect(p.previewCatalog().sessions,same(base.sessions));
    p.undo();
    expect(p.directTitleIds,base.personalOrderIds);
    p.redo();
    expect(p.directTitleIds,['a2','b1','a1']);
    p.discard();
    expect(p.previewCatalog(),same(base));
    p.dispose();
  });

  test('Collection blocks retain single outer slot; dedupe shifts with order',(){
    final base=m47Fixture(members:3);
    final p=_plan(base);
    final before=NativeM42MixedQueues(p.previewCatalog());
    expect(before.slotsForCategory('anime')[1].candidates.length,3);
    expect(before.slotsForCategory('anime')[3].candidates.length,0);
    p.positionMixedToken('anime','c:two',1);
    expect(p.tokens('anime'),['c:two','t:a1','c:one','t:a2']);
    final now=NativeM42MixedQueues(p.previewCatalog()).slotsForCategory('anime');
    expect(now.length,4);
    expect(now.first.candidates.map((c)=>c.title.id),['m0','m1','a1']);
    expect(now[2].candidates.map((c)=>c.title.id),['m2']);
    expect(now.first.position,1);
    expect(p.directTitleIds,base.personalOrderIds);
    p.undo();
    expect(p.tokens('anime'),base.categoryQueues['anime']);
    p.dispose();
  });

  test('invalid token, category, ambiguous source and stale owner fail closed',(){
    final base=m47Fixture(members:2);
    final p=_plan(base);
    expect(()=>p.positionMixedToken('anime','bad',1),throwsFormatException);
    expect(()=>p.positionMixedToken('anime','t:ghost',1),throwsStateError);
    expect(()=>p.positionMixedToken('anime','c:one',0),throwsFormatException);
    expect(()=>p.positionMixedToken('anime','c:one',99),throwsFormatException);
    expect(()=>p.positionMixedToken('books','c:one',1),throwsStateError);
    expect(()=>p.positionMixedToken('anime','t:b1',1),throwsStateError);
    expect(p.hasChanges,false);
    p.moveMixedToken('anime','c:one',-1);
    expect(p.pendingOperations,1);
    p.observe(m47Fixture(members:2),currentOwnerId:'owner');
    expect(p.stale,true);
    expect(()=>p.moveMixedToken('anime','c:one',1),throwsStateError);
    expect(()=>p.undo(),throwsStateError);
    expect(base.categoryQueues['anime'],['t:a1','c:one','t:a2','c:two']);
    p.dispose();

    final ambiguous=m47Fixture(members:2,duplicate:true);
    final bad=_plan(ambiguous);
    expect(()=>bad.positionMixedToken('anime','c:one',1),throwsStateError);
    expect(bad.hasChanges,false);
    bad.dispose();
  });

  test('100k Library and 8k-member Collection remain unchanged on edits',(){
    final data=m47Fixture(members:8000);
    final p=_plan(data);
    p.moveMixedToken('anime','c:one',-1);
    expect(p.tokens('anime').first,'c:one');
    expect(p.previewCatalog().library,same(data.library));
    expect(p.previewCatalog().collections,same(data.collections));
    expect(p.previewCatalog().collections.first.titleIds.length,8000);
    p.undo();
    expect(p.hasChanges,false);
    p.dispose();
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('mixed editor stages Collection move, undo, and saved preview',
      (tester) async {
    tester.view.physicalSize=const Size(1080,1480);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final base=m47Fixture(members:4);
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PersonalOrderScreen(repository:_Repo(base),
        plan:plan,currentOwnerId:'owner'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m42-mixed-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m42-readonly-disclaimer')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m47-edit-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m47-edit-warning')),findsOneWidget);
    expect(find.byKey(const Key('m47-position-c:one')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m47-up-c:one')));
    await tester.pumpAndSettle();
    expect(plan.tokens('anime').first,'c:one');
    expect(plan.pendingOperations,1);
    expect(base.categoryQueues['anime']!.first,'t:a1');
    await tester.tap(find.byKey(const Key('m47-undo')));
    await tester.pumpAndSettle();
    expect(plan.tokens('anime').first,'t:a1');
    await tester.tap(find.byKey(const Key('m47-redo')));
    await tester.pumpAndSettle();
    expect(plan.tokens('anime').first,'c:one');
    await tester.tap(find.byKey(const Key('m47-edit-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m47-edit-warning')),findsNothing);
    expect(find.byKey(const Key('m44-preview-toggle')),findsOneWidget);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    plan.dispose();
  });

  testWidgets('Collection member pager reveals entries beyond first 20',
      (tester) async {
    tester.view.physicalSize=const Size(1050,1500);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final base=m47Fixture(members:46);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PersonalOrderScreen(repository:_Repo(base)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m42-mixed-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m42-collection-c:one')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m42-member-one-m0')),findsOneWidget);
    expect(find.byKey(const Key('m42-member-one-m20')),findsNothing);
    await tester.ensureVisible(find.byKey(
      const Key('m47-member-next-c:one')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m47-member-next-c:one')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m42-member-one-m20')),findsOneWidget);
    expect(find.text('Members page 2 of 3'),findsOneWidget);
    expect(base.collections.first.titleIds.length,46);
  });
}
