import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/library/library_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m37_library_plan.dart';

MediaFlowCatalog sample({int count = 3}) => decodeMediaFlowState({
  'categories':[
    {'id':'anime','name':'Anime'},
    {'id':'books','name':'Books'},
  ],
  'library':[
    for (var i = 0; i < count; i++)
      {'id':'title-$i','title':'Title $i',
       'categoryId':'anime','status':'planned','priority':'medium',
       'progress': i == 0 ? 2 : 0,'total':12,
       'description':'Description $i',
       'tags':i == 0 ? ['Favorite'] : [],
       'seasons': i == 0 ? [
         {'name':'Season One','progress':2,'total':12}
       ] : [],
      },
  ],
  'sessions':[],
  'collections':[],
  'settings':{'custom':'keep untouched'},
});

class FakeRepo extends MediaFlowLibraryRepository {
  FakeRepo(this.catalog);
  final MediaFlowCatalog catalog;
  @override
  Future<MediaFlowCatalog> load() async => catalog;
}

void main() {
  test('batch metadata merges tags, preserves fields and supports one undo', () {
    final original = sample();
    final plan = NativeM37LibraryPlan(ownerId:'owner')..observe(original);
    plan.batchEdit(['title-0','title-1'],
      status:'active', priority:'high',
      addTags:['Favorite','New tag','new TAG']);
    expect(plan.editCount, 2);
    final preview = plan.previewCatalog();
    expect(preview.library[0].status, 'active');
    expect(preview.library[0].priority, 'high');
    expect(preview.library[0].progress, 2);
    expect(preview.library[0].seasons.single.progress, 2);
    expect(preview.library[0].tags, ['Favorite','New tag']);
    expect(preview.library[1].tags, ['Favorite','New tag','new TAG'].where(
        (tag) => tag.toLowerCase() != 'new tag' || tag == 'New tag').toList());
    expect(original.library.first.status, 'planned');
    expect(original.library.first.tags, ['Favorite']);
    expect(original.sessions, same(preview.sessions));
    expect(plan.mayUpload, false);
    expect(NativeCloudCapabilities.cloudWritesEnabled, false);
    plan.undo();
    expect(plan.editCount, 0);
    expect(plan.previewCatalog().library[0].status, 'planned');
    plan.redo();
    expect(plan.editCount, 2);
    plan.dispose();
  });

  test('batch operation fails atomically on one invalid/deleted title', () {
    final original = sample();
    final plan = NativeM37LibraryPlan(ownerId:'owner')..observe(original);
    expect(() => plan.batchEdit(['title-0', 'missing'],status:'active'),
      throwsStateError);
    expect(plan.changeCount, 0);
    expect(plan.canUndo, false);
    expect(() => plan.batchEdit(['title-0'], status:'invalid'),
      throwsFormatException);
    expect(() => plan.batchEdit(['title-0'], addTags:['  ']),
      throwsFormatException);
    expect(() => plan.batchEdit(['title-0']), throwsFormatException);
    plan.stageDelete(['title-1']);
    expect(() => plan.batchEdit(['title-0','title-1'],priority:'high'),
      throwsStateError);
    expect(plan.editCount, 0);
    plan.dispose();
  });

  test('batch no-op avoids empty undo and respects 200-change limit', () {
    final source = sample(count:205);
    final plan = NativeM37LibraryPlan(ownerId:'owner')..observe(source);
    plan.batchEdit(['title-0'], priority:'medium');
    expect(plan.canUndo, false);
    plan.batchEdit([for (var i=0;i<200;i++) 'title-$i'],
      priority:'high');
    expect(plan.editCount, 200);
    expect(() => plan.batchEdit(['title-200'],priority:'high'),
      throwsStateError);
    expect(plan.editCount, 200);
    plan.dispose();
  });

  test('batch edits created temporary titles without changing original IDs', () {
    final source = sample();
    final plan = NativeM37LibraryPlan(ownerId:'owner')..observe(source);
    plan.create(NativeM37Fields(
      title:'Temporary', categoryId:'books', status:'planned',
      priority:'medium', progress:0, total:4, rating:null,
      coverUrl:'', description:'local', tags:const []));
    final id = plan.previewCatalog().library.last.id;
    plan.batchEdit([id,'title-1'], categoryId:'anime',
      priority:'high', addTags:['Queued']);
    expect(plan.creationCount,1);
    expect(plan.editCount,1);
    expect(plan.fieldsFor(id).priority,'high');
    expect(plan.fieldsFor(id).tags,['Queued']);
    plan.undo();
    expect(plan.fieldsFor(id).priority,'medium');
    expect(plan.editCount,0);
    plan.dispose();
  });

  testWidgets('Title Details opens native inspector and local edit sheet',
      (tester) async {
    final data = sample();
    final plan = NativeM37LibraryPlan(ownerId:'owner');
    tester.view.physicalSize = const Size(900,1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:LibraryScreen(repository:FakeRepo(data),changePlan:plan))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title 0').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m38-title-details')), findsOneWidget);
    expect(find.text('Description 0'), findsOneWidget);
    expect(find.text('Season One'), findsOneWidget);
    expect(find.byKey(const Key('m38-edit-title')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('m38-edit-title')));
    await tester.tap(find.byKey(const Key('m38-edit-title')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m37-title')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('m37-title')),'Edited Title');
    await tester.ensureVisible(find.byKey(const Key('m37-stage-form')));
    await tester.tap(find.byKey(const Key('m37-stage-form')));
    await tester.pumpAndSettle();
    expect(plan.editCount,1);
    expect(data.library.first.title,'Title 0');
    expect(find.text('Edited Title'), findsWidgets);
    plan.dispose();
  });

  testWidgets('batch sheet requires confirmation, stages one action, undo works',
      (tester) async {
    final source = sample();
    final plan = NativeM37LibraryPlan(ownerId:'owner');
    tester.view.physicalSize = const Size(900,1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:LibraryScreen(repository:FakeRepo(source),changePlan:plan))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m37-select-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m37-select-visible')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m38-bulk-metadata')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('m38-bulk-tags')),'Bulk tag');
    await tester.ensureVisible(find.byKey(const Key('m38-stage-bulk')));
    await tester.tap(find.byKey(const Key('m38-stage-bulk')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m38-confirm-bulk')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m38-confirm-bulk')));
    await tester.pumpAndSettle();
    expect(plan.editCount, 3);
    expect(plan.fieldsFor('title-0').tags, ['Favorite','Bulk tag']);
    expect(source.library.first.tags,['Favorite']);
    plan.undo();
    expect(plan.editCount,0);
    plan.dispose();
  });
}
