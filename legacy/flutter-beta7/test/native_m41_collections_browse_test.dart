import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/features/collections/collections_screen.dart';
import 'package:mediaflow_app/services/native_m40_collection_plan.dart';
import 'package:mediaflow_app/services/native_m41_collection_browser.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';

MediaFlowCatalog fixture({int count=4}) => decodeMediaFlowState({
  'categories':[
    {'id':'anime','name':'Anime'},
    {'id':'books','name':'Books'},
  ],
  'library':[
    for(var i=0;i<count;i++)
      {'id':'t$i','title':'Title $i',
        'categoryId':i.isEven?'anime':'books',
        'status':i==0?'completed':'active',
        'priority':i==0?'high':'low',
        'progress':i,'total':10,
        'rating':i==0?9:i==1?7:null,
        'coverUrl':i==0?'https://example.com/cover.jpg':'',
        'tags':[i==1?'magic':'science']},
  ],
  'collections':[{
    'id':'col1','title':'A Collection',
    'titleIds':[for(var i=0;i<count;i++)'t$i','missing'],
    'order':['t2','t0','t1',for(var i=3;i<count;i++)'t$i','missing'],
  }],
  'sessions':[],
  'orderPlan':{
    'titleIds':['t0','t3'],
    'collectionAssignments':[
      {'id':'a1','collectionId':'col1','categoryId':'anime',
       'categoryRule':'match','completedRule':'skip',
       'traversedTitleIds':['t2','t0']},
      {'id':'a2','collectionId':'col1','categoryId':'books',
       'categoryRule':'force','completedRule':'include',
       'traversedTitleIds':['t1']},
      {'id':'other','collectionId':'unrelated','categoryId':'anime',
       'traversedTitleIds':['t0']},
    ],
  },
});

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.source);
  final MediaFlowCatalog source;
  @override
  Future<MediaFlowCatalog> load() async => source;
}

void main() {
  test('v287 assignment map is decoded and retained in preview',(){
    final source=fixture();
    expect(source.collectionAssignments.length,3);
    expect(source.collectionAssignments.first.categoryRule,'match');
    expect(source.collectionAssignments[1].completedRule,'include');
    final impact=inspectCollectionOrderImpact(
      source,source.collections.single);
    expect(impact.assignments.map((x)=>x.id).toList(),['a1','a2']);
    expect(impact.directMembers,2);
    expect(impact.traversedMembers,3);
    expect(impact.requiresQueueReview,true);
    final p=NativeM40CollectionPlan(ownerId:'owner')..observe(source);
    p.addTitles('col1',['t0','t1']);
    // A noop does not create a preview; perform an actual membership edit.
    p.removeTitles('col1',['t2']);
    final staged=p.previewCatalog();
    expect(staged.collectionAssignments,same(source.collectionAssignments));
    expect(staged.personalOrderIds,same(source.personalOrderIds));
    expect(staged.sessions,same(source.sessions));
    expect(staged.library,same(source.library));
    expect(staged.collectionAssignments.first.traversedTitleIds,['t2','t0']);
    expect(source.collections.single.titleIds.contains('t2'),true);
    expect(p.mayUpload,false);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    p.dispose();
  });

  test('only Collection member IDs are filtered and manually ordered',(){
    final source=fixture();
    final byId={for(final t in source.library)t.id:t};
    final c=source.collections.single;
    final all=browseCollection(c,byId,const NativeM41BrowseOptions());
    expect(all.items.map((t)=>t.id).toList(),['t2','t0','t1','t3']);
    expect(all.total,4);
    expect(browseCollection(c,byId,const NativeM41BrowseOptions(
      categoryId:'anime')).items.map((t)=>t.id),['t2','t0']);
    expect(browseCollection(c,byId,const NativeM41BrowseOptions(
      status:'completed')).items.single.id,'t0');
    expect(browseCollection(c,byId,const NativeM41BrowseOptions(
      priority:'high')).items.single.id,'t0');
    expect(browseCollection(c,byId,const NativeM41BrowseOptions(
      minRating:8)).items.single.id,'t0');
    expect(browseCollection(c,byId,const NativeM41BrowseOptions(
      cover:'with')).items.single.id,'t0');
    expect(browseCollection(c,byId,const NativeM41BrowseOptions(
      cover:'without')).total,3);
    expect(browseCollection(c,byId,const NativeM41BrowseOptions(
      search:'magic')).items.single.id,'t1');
    final sorted=browseCollection(c,byId,const NativeM41BrowseOptions(
      sort:NativeM41Sort.rating));
    expect(sorted.items.first.id,'t0');
    expect(c.titleIds,['t2','t0','t1','t3','missing']);
  });

  test('pagination respects filtered count, boundaries, and stable selection',(){
    final source=fixture(count:62);
    final byId={for(final t in source.library)t.id:t};
    final c=source.collections.single;
    final page0=browseCollection(c,byId,const NativeM41BrowseOptions(
      pageSize:25,page:0));
    final page1=browseCollection(c,byId,const NativeM41BrowseOptions(
      pageSize:25,page:1));
    final last=browseCollection(c,byId,const NativeM41BrowseOptions(
      pageSize:25,page:999));
    expect(page0.items.length,25);
    expect(page1.items.length,25);
    expect(page0.pages,3);
    expect(last.page,2);
    expect(last.items.length,12);
    expect(page0.items.map((i)=>i.id).toSet()
      .intersection(page1.items.map((i)=>i.id).toSet()),isEmpty);
    expect(()=>browseCollection(c,byId,
      const NativeM41BrowseOptions(pageSize:1)),throwsFormatException);
    expect(source.library.length,62);
  });

  test('unknown and duplicate queue entries are not silently rewritten',(){
    final source=decodeMediaFlowState({
      'library':[{'id':'x','title':'X'}],
      'collections':[{'id':'c','title':'C','titleIds':['x']}],
      'orderPlan':{'titleIds':[],
        'collectionAssignments':[
          {'id':'a','collectionId':'missing','categoryId':'anime',
            'traversedTitleIds':['x','x','ghost']},
        ]},
    });
    final result=inspectCollectionOrderImpact(
      source,source.collections.single);
    expect(result.assignments,isEmpty);
    expect(result.directMembers,0);
    expect(result.traversedMembers,0);
    expect(source.collectionAssignments.single.traversedTitleIds,
      ['x','x','ghost']);
  });

  testWidgets('v274 filters and five views expose correct controls',(
      tester) async {
    final source=fixture();
    tester.view.physicalSize=const Size(960,1200);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:CollectionsScreen(repository:_Repo(source)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A Collection'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m41-order-impact')),findsOneWidget);
    expect(find.byKey(const Key('m41-status')),findsOneWidget);
    expect(find.byKey(const Key('m41-category')),findsOneWidget);
    expect(find.byKey(const Key('m41-rating')),findsOneWidget);
    expect(find.byKey(const Key('m41-view')),findsOneWidget);
    expect(find.byKey(const Key('m41-per-page')),findsOneWidget);
    expect(find.text('Title 2'),findsOneWidget);
    await tester.enterText(find.byKey(const Key('m41-search')),'Title 1');
    await tester.pumpAndSettle();
    // The search TextField and the result row both display this exact text.
    expect(find.text('Title 1'),findsWidgets);
    expect(find.text('Title 2'),findsNothing);
  });

  testWidgets('bulk removal is confirmation-gated, reversible and queue-safe',(
      tester) async {
    final source=fixture();
    final plan=NativeM40CollectionPlan(ownerId:'owner');
    tester.view.physicalSize=const Size(960,1200);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:CollectionsScreen(repository:_Repo(source),plan:plan))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A Collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m41-select-visible')));
    await tester.pumpAndSettle();
    expect(find.text('Remove selected (4)'),findsOneWidget);
    await tester.tap(find.byKey(const Key('m41-remove-selected')));
    await tester.pumpAndSettle();
    expect(plan.changeCount,0);
    expect(find.byKey(const Key('m41-confirm-bulk-remove')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m41-confirm-bulk-remove')));
    await tester.pumpAndSettle();
    expect(plan.edits,1);
    expect(plan.fieldsFor('col1').titleIds,['missing']);
    expect(source.collections.single.titleIds.length,5);
    expect(source.library.length,4);
    expect(source.collectionAssignments.length,3);
    plan.undo();
    expect(plan.fieldsFor('col1').titleIds.length,5);
    plan.dispose();
  });
}
