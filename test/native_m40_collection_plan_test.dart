import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/features/collections/collections_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m40_collection_plan.dart';

MediaFlowCatalog sample({
  int titles=3, bool missingMember=false,
  bool duplicateCollection=false, bool duplicateTitle=false,
}) => decodeMediaFlowState({
  'categories':[{'id':'anime','name':'Anime'}],
  'library':[
    for (var i=0;i<titles;i++)
      {'id':'title-$i','title':'Title $i','categoryId':'anime',
        'status':'active','priority':'medium','progress':i,'total':12},
    if (duplicateTitle) {'id':'title-1','title':'Duplicate','categoryId':'anime'}
  ],
  'collections':[
    {'id':'collection-1','title':'Favorites',
     'description':'Original','coverUrl':'',
     'titleIds':['title-1','title-0',if(missingMember)'legacy-gone'],
     'order':['title-0','title-1',if(missingMember)'legacy-gone'],
     'unknownV410Field':{'keep':true}},
    if (duplicateCollection)
      {'id':'collection-1','title':'Duplicate Collection','titleIds':[]},
  ],
  'settings':{'unknown':'keep'},
  'sessions':[
    {'id':'h1','date':'2026-10-14','categoryId':'anime','actualAmount':1,
     'minutes':25,'xp':30,'titles':[{'libraryId':'title-0','qty':1}]}
  ],
  'orderPlan':{'titleIds':['title-1']},
});

NativeM40CollectionFields fields({
  String name='Created',List<String> ids=const [],
  String description='Local',String cover='',
}) => NativeM40CollectionFields(
  title:name, description:description,coverUrl:cover,titleIds:ids);

class Repo extends MediaFlowLibraryRepository {
  Repo(this.catalog);
  final MediaFlowCatalog catalog;
  @override
  Future<MediaFlowCatalog> load() async => catalog;
  @override
  Future<MediaFlowCatalog> reload() async => catalog;
}

void main() {
  test('create/edit/add/order/remove/delete/restore and undo are local only',(){
    final source=sample();
    final p=NativeM40CollectionPlan(ownerId:'owner')..observe(source);
    final original=source.collections.single;
    final created=p.create(fields(ids:['title-2']));
    expect(created,startsWith('local_m40_'));
    expect(p.creations,1);
    p.addTitles('collection-1',['title-2','title-2','title-1']);
    expect(p.fieldsFor('collection-1').titleIds,
      ['title-0','title-1','title-2']);
    p.moveTitle('collection-1','title-2',0);
    expect(p.fieldsFor('collection-1').titleIds,
      ['title-2','title-0','title-1']);
    p.removeTitles('collection-1',['title-0']);
    expect(p.fieldsFor('collection-1').titleIds,['title-2','title-1']);
    expect(source.library.length,3);
    expect(original.titleIds,['title-0','title-1']);
    final preview=p.previewCatalog();
    expect(preview.library,same(source.library));
    expect(preview.sessions,same(source.sessions));
    expect(preview.personalOrderIds,same(source.personalOrderIds));
    expect(preview.collections.length,2);
    p.stageDelete('collection-1');
    expect(p.deletions,1);
    expect(p.previewCatalog().collections.single.id,created);
    p.restore('collection-1');
    expect(p.deletions,0);
    p.undo();
    expect(p.deletions,1);
    p.redo();
    expect(p.deletions,0);
    p.stageDelete(created);
    expect(p.creations,0);
    expect(p.mayUpload,false);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    p.dispose();
  });

  test('no-op operations do not create revisions and Undo rolls back one batch',(){
    final p=NativeM40CollectionPlan(ownerId:'owner')..observe(sample());
    p.addTitles('collection-1',['title-0']);
    p.moveTitle('collection-1','title-0',0);
    p.edit('collection-1',p.fieldsFor('collection-1'));
    expect(p.canUndo,false);
    p.addTitles('collection-1',['title-2','title-1']);
    expect(p.fieldsFor('collection-1').titleIds,
      ['title-0','title-1','title-2']);
    p.undo();
    expect(p.edits,0);
    expect(p.fieldsFor('collection-1').titleIds,['title-0','title-1']);
    p.redo();
    expect(p.edits,1);
    p.dispose();
  });

  test('valid membership only, retain unresolved legacy refs unless removed',(){
    final source=sample(missingMember:true);
    final p=NativeM40CollectionPlan(ownerId:'owner')..observe(source);
    p.addTitles('collection-1',['title-2']);
    expect(p.fieldsFor('collection-1').titleIds.last,'title-2');
    expect(p.fieldsFor('collection-1').titleIds.contains('legacy-gone'),true);
    expect(()=>p.addTitles('collection-1',['missing']),throwsStateError);
    expect(()=>p.addTitles('collection-1',['title-2','missing']),
      throwsStateError);
    expect(p.fieldsFor('collection-1').titleIds.last,'title-2');
    p.removeTitles('collection-1',['legacy-gone']);
    expect(p.fieldsFor('collection-1').titleIds.contains('legacy-gone'),false);
    expect(source.collections.single.titleIds.contains('legacy-gone'),true);
    p.dispose();
  });

  test('duplicate collection and title IDs fail closed before modifications',(){
    final p=NativeM40CollectionPlan(ownerId:'owner')..
      observe(sample(duplicateCollection:true,duplicateTitle:true));
    expect(()=>p.edit('collection-1',fields()),throwsStateError);
    expect(()=>p.stageDelete('collection-1'),throwsStateError);
    final id=p.create(fields());
    expect(()=>p.addTitles(id,['title-1']),throwsStateError);
    expect(p.fieldsFor(id).titleIds,isEmpty);
    expect(()=>p.create(fields(ids:['title-1'])),throwsStateError);
    p.dispose();
  });

  test('invalid inputs and 200-change bounds reject atomically',(){
    final p=NativeM40CollectionPlan(ownerId:'owner')..observe(sample());
    expect(()=>p.create(fields(name:'   ')),throwsFormatException);
    expect(()=>p.create(fields(cover:'javascript:alert(1)')),
      throwsFormatException);
    expect(()=>p.create(fields(ids:['title-0','title-0'])),
      throwsFormatException);
    expect(()=>p.addTitles('collection-1',[]),throwsFormatException);
    expect(()=>p.removeTitles('collection-1',['title-2']),throwsStateError);
    expect(()=>p.moveTitle('collection-1','title-0',50),
      throwsFormatException);
    expect(p.changeCount,0);
    for (var i=0;i<200;i++) { p.create(fields(name:'New $i')); }
    expect(p.changeCount,200);
    expect(()=>p.create(fields()),throwsStateError);
    p.dispose();
  });

  test('fresh source quarantine, discard, owner separation and cache',(){
    final source=sample();
    final p=NativeM40CollectionPlan(ownerId:'account-A')..observe(source);
    final other=NativeM40CollectionPlan(ownerId:'account-B')..observe(source);
    p.edit('collection-1', fields(name:'Edited',ids:['title-0','title-1']));
    final projected=p.previewCatalog();
    expect(p.previewCatalog(),same(projected));
    expect(other.hasChanges,false);
    p.observe(sample());
    expect(p.stale,true);
    expect(()=>p.undo(),throwsStateError);
    expect(()=>p.previewCatalog(),throwsStateError);
    expect(()=>p.addTitles('collection-1',['title-2']),throwsStateError);
    p.discard();
    expect(p.stale,false);
    expect(p.changeCount,0);
    expect(p.previewCatalog().collections.single.title,'Favorites');
    expect(()=>NativeM40CollectionPlan(ownerId:''),throwsStateError);
    other.dispose();
    p.dispose();
  });

  test('100k Library titles, projected collections reference unchanged data',(){
    final src=sample(titles:100000);
    final p=NativeM40CollectionPlan(ownerId:'scale')..observe(src);
    p.addTitles('collection-1',['title-99999']);
    final projected=p.previewCatalog();
    expect(projected.library,same(src.library));
    expect(projected.collections.single.titleIds.last,'title-99999');
    expect(src.collections.single.titleIds.length,2);
    p.dispose();
  }, timeout: const Timeout(Duration(minutes:2)));

  testWidgets('Collections create, preview and review changes stay device-only',
      (tester) async {
    final src=sample();
    final p=NativeM40CollectionPlan(ownerId:'owner');
    tester.view.physicalSize=const Size(900,1100);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:CollectionsScreen(repository:Repo(src),plan:p))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m40-create')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m40-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('m40-collection-title')),
      'Test Collection');
    await tester.ensureVisible(find.byKey(const Key('m40-save-collection')));
    await tester.tap(find.byKey(const Key('m40-save-collection')));
    await tester.pumpAndSettle();
    expect(p.creations,1);
    expect(src.collections.length,1);
    await tester.tap(find.byKey(const Key('m40-preview')));
    await tester.pumpAndSettle();
    expect(find.text('Test Collection'),findsOneWidget);
    expect(find.byKey(const Key('m40-source-label')),findsOneWidget);
    p.dispose();
  });

  testWidgets('Collection Direct Add then reorder and remove with confirmation',
      (tester) async {
    final src=sample();
    final p=NativeM40CollectionPlan(ownerId:'owner');
    tester.view.physicalSize=const Size(900,1200);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:CollectionsScreen(repository:Repo(src),plan:p))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m40-add-titles')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m40-direct-add-title-2')));
    await tester.pumpAndSettle();
    expect(p.edits,1);
    expect(p.fieldsFor('collection-1').titleIds.last,'title-2');
    expect(src.collections.single.titleIds.length,2);
    // ModalBottomSheet has no Cupertino navigation back button. Dismiss its
    // scrim as a user would, without depending on the platform toolbar.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m40-preview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m40-up-title-2')));
    await tester.pumpAndSettle();
    expect(p.fieldsFor('collection-1').titleIds,['title-0','title-2','title-1']);
    await tester.tap(find.byKey(const Key('m40-remove-title-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m40-confirm-remove')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m40-confirm-remove')));
    await tester.pumpAndSettle();
    expect(p.fieldsFor('collection-1').titleIds,['title-0','title-1']);
    expect(src.library.length,3);
    p.undo();
    expect(p.fieldsFor('collection-1').titleIds,['title-0','title-2','title-1']);
    p.dispose();
  });
}
