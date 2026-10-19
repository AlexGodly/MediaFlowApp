import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/features/library/library_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m37_library_plan.dart';

MediaFlowCatalog sample({int count = 2,bool duplicate = false}) {
  return decodeMediaFlowState({
    'categories':[
      {'id':'anime','name':'Anime'},
      {'id':'books','name':'Books'},
    ],
    'library': [
      for (var i=0;i<count;i++)
        {'id':'title-$i','title':'Title $i','categoryId':'anime',
         'status':'planned','priority':'medium','progress':0,'total':12,
         'rating':null,'description':'original $i',
         'coverUrl':'https://example.invalid/cover.png'},
      if (duplicate) {
        'id':'title-0','title':'Duplicated','categoryId':'anime',
        'status':'planned','progress':0,
      },
    ],
    'sessions':[{
      'id':'session-1','date':'2026-10-14','categoryId':'anime',
      'actualAmount':1,'minutes':25,'xp':10,
      'titles':[{'title':'Title 0','libraryId':'title-0','qty':1}],
    }],
    'collections':[{
      'id':'collection-1','title':'Collection',
      'titleIds':['title-0'],'order':['title-0'],
    }],
    'personalOrder':['title-0'],
    'settings':{'unknown':'must survive'},
  });
}

NativeM37Fields fields({
  String title='New Title',String category='anime',
  String status='planned',String priority='high',
  double progress=0,double? total=12,double? rating,
  String cover='',String description='',List<String> tags=const [],
}) => NativeM37Fields(
  title:title,categoryId:category,status:status,priority:priority,
  progress:progress,total:total,rating:rating,coverUrl:cover,
  description:description,tags:tags,
);

void main(){
  test('local create/edit/delete/bulk-restore only changes the projection',(){
    final source=sample();
    final plan=NativeM37LibraryPlan(ownerId:'owner')..observe(source);
    plan.create(fields(title:'Created'));
    expect(plan.creationCount,1);
    expect(plan.changeCount,1);
    final createdId=plan.previewCatalog().library.last.id;
    expect(createdId,startsWith('local_m37_'));
    expect(source.library.length,2);
    plan.edit('title-0',fields(title:'Edited',status:'active',
      progress:2,rating:9,description:'preview only'));
    expect(plan.editCount,1);
    expect(plan.previewCatalog().library.first.title,'Edited');
    expect(source.library.first.title,'Title 0');
    expect(source.library.first.status,'planned');
    expect(source.sessions.single.xp,10);
    final projected=plan.previewCatalog();
    expect(projected.sessions, same(source.sessions));
    expect(projected.collections,same(source.collections));
    expect(projected.personalOrderIds,same(source.personalOrderIds));
    expect(plan.references('title-0'),greaterThanOrEqualTo(1));
    plan.stageDelete(['title-0','title-1',createdId]);
    expect(plan.creationCount,0);
    expect(plan.editCount,0);
    expect(plan.deletionCount,2);
    expect(plan.previewCatalog().library,isEmpty);
    plan.restoreDeleted('title-0');
    expect(plan.deletionCount,1);
    expect(plan.previewCatalog().library.single.title,'Title 0');
    expect(plan.mayUpload,false);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    plan.dispose();
  });

  test('undo and redo support multi-title deletion as one reversible action',(){
    final source=sample();
    final plan=NativeM37LibraryPlan(ownerId:'owner')..observe(source);
    plan.stageDelete(['title-0','title-1']);
    expect(plan.deletionCount,2);
    plan.undo();
    expect(plan.deletionCount,0);
    expect(plan.previewCatalog().library.length,2);
    plan.redo();
    expect(plan.deletionCount,2);
    plan.undo();
    plan.create(fields(title:'New instead'));
    expect(plan.canRedo,false);
    expect(plan.previewCatalog().library.length,3);
    plan.discard();
    expect(plan.hasChanges,false);
    expect(plan.previewCatalog(),same(source));
    plan.dispose();
  });

  test('validation blocks malformed fields and season aggregate edits',(){
    final source=sample();
    final plan=NativeM37LibraryPlan(ownerId:'owner')..observe(source);
    expect(()=>plan.create(fields(title:' ')),throwsFormatException);
    expect(()=>plan.create(fields(category:'nonexistent')),throwsFormatException);
    expect(()=>plan.create(fields(rating:11)),throwsFormatException);
    expect(()=>plan.create(fields(progress:13)),throwsFormatException);
    expect(()=>plan.create(fields(progress:double.nan)),throwsFormatException);
    expect(()=>plan.create(fields(cover:'javascript:alert(1)')),
      throwsFormatException);
    expect(()=>plan.create(fields(status:'invalid')),throwsFormatException);
    expect(()=>plan.create(fields(priority:'urgent')),throwsFormatException);
    expect(()=>plan.stageDelete([]),throwsFormatException);
    expect(()=>plan.stageDelete(['missing']),throwsStateError);
    expect(()=>plan.edit('missing',fields()),throwsStateError);
    expect(plan.changeCount,0);
    plan.dispose();
  });

  test('duplicate Library IDs are quarantined rather than guessed',(){
    final source=sample(duplicate:true);
    final plan=NativeM37LibraryPlan(ownerId:'owner')..observe(source);
    expect(()=>plan.edit('title-0',fields()),throwsStateError);
    expect(()=>plan.stageDelete(['title-0']),throwsStateError);
    expect(plan.changeCount,0);
    plan.dispose();
  });

  test('cloud refresh blocks stale plan even when titles look unchanged',(){
    final initial=sample();
    final plan=NativeM37LibraryPlan(ownerId:'owner')..observe(initial);
    plan.create(fields(title:'Offline novel'));
    plan.observe(sample());
    expect(plan.stale,true);
    expect(()=>plan.create(fields(title:'More')),throwsStateError);
    expect(()=>plan.previewCatalog(),throwsStateError);
    expect(()=>plan.undo(),throwsStateError);
    expect(plan.creationCount,1);
    plan.discard();
    expect(plan.stale,false);
    expect(plan.creationCount,0);
    expect(plan.previewCatalog().library.length,2);
    plan.dispose();
  });

  test('different authenticated owners never share Library change planners',(){
    final src=sample();
    final a=NativeM37LibraryPlan(ownerId:'account-A')..observe(src);
    final b=NativeM37LibraryPlan(ownerId:'account-B')..observe(src);
    a.create(fields(title:'Private A'));
    expect(a.changeCount,1);
    expect(b.changeCount,0);
    expect(b.previewCatalog().library.length,2);
    expect(()=>NativeM37LibraryPlan(ownerId:''),throwsStateError);
    a.dispose();b.dispose();
  });

  test('100k source titles are referenced without copying original records',(){
    final original=sample(count:100000);
    final plan=NativeM37LibraryPlan(ownerId:'scale')..observe(original);
    plan.edit('title-99999',fields(title:'Last changed'));
    final projected=plan.previewCatalog();
    expect(projected.library.length,100000);
    expect(projected.library.first,same(original.library.first));
    expect(projected.library.last.title,'Last changed');
    expect(original.library.last.title,'Title 99999');
    plan.stageDelete(['title-99999']);
    expect(plan.previewCatalog().library.length,99999);
    expect(original.library.length,100000);
    plan.dispose();
  }, timeout:const Timeout(Duration(minutes:2)));

  test('200 title changes bounded; bulk count and invalid input rejected',(){
    final src=sample(count:300);
    final plan=NativeM37LibraryPlan(ownerId:'owner')..observe(src);
    plan.stageDelete([for(var i=0;i<200;i++)'title-$i']);
    expect(plan.deletionCount,200);
    expect(()=>plan.stageDelete(['title-201']),throwsStateError);
    expect(()=>plan.stageDelete([for(var i=0;i<201;i++)'title-$i']),
      throwsFormatException);
    plan.dispose();
  });

  testWidgets('native Library stages a creation without changing cloud titles',
      (tester) async {
    final source=sample();
    final plan=NativeM37LibraryPlan(ownerId:'signed-in-user');
    final repo=_FakeRepo(source);
    tester.view.physicalSize=const Size(880,980);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      LibraryScreen(repository:repo,changePlan:plan))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m37-new-title')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m37-new-title')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('m37-title')),'Device Draft');
    await tester.ensureVisible(find.byKey(const Key('m37-stage-form')));
    await tester.tap(find.byKey(const Key('m37-stage-form')));
    await tester.pumpAndSettle();
    expect(plan.creationCount,1);
    expect(source.library.length,2);
    await tester.tap(find.byKey(const Key('m37-preview-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Device Draft'),findsOneWidget);
    expect(find.byKey(const Key('m37-preview-warning')),findsOneWidget);
    plan.dispose();
  });

  testWidgets('bulk selection stages only device deletions with confirmation',
      (tester) async {
    final source=sample();
    final plan=NativeM37LibraryPlan(ownerId:'owner');
    final repo=_FakeRepo(source);
    tester.view.physicalSize=const Size(880,980);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      LibraryScreen(repository:repo,changePlan:plan))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m37-select-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m37-select-visible')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m37-bulk-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Stage device-only deletion'),findsOneWidget);
    await tester.tap(find.text('Stage device-only deletion'));
    await tester.pumpAndSettle();
    expect(plan.deletionCount,2);
    expect(source.library.length,2);
    plan.dispose();
  });
}

class _FakeRepo extends MediaFlowLibraryRepository {
  _FakeRepo(this.value);
  final MediaFlowCatalog value;
  @override
  Future<MediaFlowCatalog> load() async => value;
}
