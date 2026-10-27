import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/dashboard/dashboard_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m44_personal_order_plan.dart';
import 'package:mediaflow_app/services/native_m48_task_coordination.dart';
import 'package:mediaflow_app/services/native_m49_dashboard_task_audit.dart';

Map<String,dynamic> m49Fixture({
  String id='b',bool? priority=true,String? source='collection',
  String assignment='as1',bool active=true,
  bool duplicate=false,bool completed=false,
  int extra=0,
}) => {
  'categories':[{'id':'anime','name':'Anime'},{'id':'book','name':'Books'}],
  'settings':{if(priority!=null)'prioritizePersonalOrder':priority},
  'sessionActive':active,
  if(active)'currentTask':{
    'categoryId':'anime','title':'Any display text',
    'libraryId':id,'low':1,'high':3,'unit':'episodes',
    'reasons':['why'],
    if(source!=null)'v287OrderSource':{
      'type':source,'categoryId':'anime','libraryId':id,
      'assignmentId':assignment,
    },
  },
  'library':[
    {'id':'a','title':'Alpha','categoryId':'anime',
      'status':'active','total':12},
    {'id':'b','title':'Beta','categoryId':'anime',
      'status':completed?'completed':'active',
      'progress':completed?12:0,'total':12},
    {'id':'cross','title':'Force cross category','categoryId':'book',
      'status':'active','total':12},
    if(duplicate)
      {'id':'b','title':'Duplicate Beta','categoryId':'anime'},
    for(var i=0;i<extra;i++)
      {'id':'x$i','title':'Extra $i','categoryId':'anime',
       'status':'active','total':12},
  ],
  'collections':[
    {'id':'c','title':'Collection','titleIds':['b','cross','a']},
  ],
  'orderPlan':{
    'titleIds':['a','b'],
    'categoryQueues':{'anime':['c:as1','t:a','t:b']},
    'collectionAssignments':[
      {'id':'as1','collectionId':'c','categoryId':'anime',
        'categoryRule':'force','completedRule':'skip','createdAt':1,
        'traversedTitleIds':[]},
    ],
  },
};

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.catalog);
  final MediaFlowCatalog catalog;
  @override
  Future<MediaFlowCatalog> load() async=>catalog;
}

void main(){
  test('v410 currentTask.libraryId and source annotation decode exactly',(){
    final catalog=decodeMediaFlowState(m49Fixture());
    final task=catalog.currentTask!;
    expect(task.libraryId,'b');
    expect(task.title,'Any display text');
    expect(task.orderSource!.type,'collection');
    expect(task.orderSource!.assignmentId,'as1');
    expect(task.orderSource!.categoryId,'anime');
    expect(task.orderSource!.libraryId,'b');
    expect(catalog.sessions,isEmpty);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('saved annotation and queue source confirm exact provenance',(){
    final catalog=decodeMediaFlowState(m49Fixture());
    final e=NativeM49DashboardTaskAudit(catalog).inspect();
    expect(e.status,NativeM49TaskEvidenceStatus.confirmedQueueSource);
    expect(e.confirmed,true);
    expect(e.currentMatch!.title.id,'b');
    expect(e.currentMatch!.outerPosition,1);
    expect(e.currentMatch!.recommendationIndex,1);
    expect(e.currentMatch!.fromCollection,true);
    expect(e.currentMatch!.assignmentId,'as1');
    expect(e.queuePreview!.candidates.map((x)=>x.title.id),
      ['b','cross','a']);
    expect(e.priority,NativeM48PriorityPolicy.enabled);
  });

  test('source mismatches are surfaced instead of claiming confirmation',(){
    final wrong=NativeM49DashboardTaskAudit(decodeMediaFlowState(
      m49Fixture(assignment:'wrong'))).inspect();
    expect(wrong.status,NativeM49TaskEvidenceStatus.sourceConflict);
    expect(wrong.confirmed,false);
    final type=NativeM49DashboardTaskAudit(decodeMediaFlowState(
      m49Fixture(source:'title'))).inspect();
    expect(type.status,NativeM49TaskEvidenceStatus.sourceConflict);
    final absent=NativeM49DashboardTaskAudit(decodeMediaFlowState(
      m49Fixture(source:null))).inspect();
    expect(absent.status,NativeM49TaskEvidenceStatus.queueMatchUnverified);
    expect(absent.currentMatch!.title.id,'b');
    expect(absent.confirmed,false);
  });

  test('missing ID, unavailable title and duplicate Library IDs fail closed',(){
    final missing=NativeM49DashboardTaskAudit(decodeMediaFlowState(
      m49Fixture(id:''))).inspect();
    expect(missing.status,NativeM49TaskEvidenceStatus.missingLibraryId);
    final unresolved=NativeM49DashboardTaskAudit(decodeMediaFlowState(
      m49Fixture(id:'gone'))).inspect();
    expect(unresolved.status,
      NativeM49TaskEvidenceStatus.missingLibraryTitle);
    final ambiguous=NativeM49DashboardTaskAudit(decodeMediaFlowState(
      m49Fixture(duplicate:true))).inspect();
    expect(ambiguous.status,NativeM49TaskEvidenceStatus.ambiguousLibraryId);
    final skipped=NativeM49DashboardTaskAudit(decodeMediaFlowState(
      m49Fixture(completed:true))).inspect();
    expect(skipped.status,NativeM49TaskEvidenceStatus.notInQueue);
  });

  test('priority disabled/unknown and active state do not rewrite task',(){
    for(final priority in <bool?>[false,null]){
      final c=decodeMediaFlowState(m49Fixture(priority:priority));
      final evidence=NativeM49DashboardTaskAudit(c).inspect();
      expect(evidence.confirmed,true);
      expect(evidence.priority,priority==false
        ?NativeM48PriorityPolicy.disabled:NativeM48PriorityPolicy.unknown);
      expect(evidence.queuePreview!.fallbackOrUnknown,true);
      expect(c.currentTask!.low,1);
      expect(c.currentTask!.high,3);
    }
    final inactive=NativeM49DashboardTaskAudit(decodeMediaFlowState(
      m49Fixture(active:false))).inspect(categoryId:'anime');
    expect(inactive.status,NativeM49TaskEvidenceStatus.inactive);
    expect(inactive.queuePreview!.first!.title.id,'b');
    final wrongCategory=NativeM49DashboardTaskAudit(decodeMediaFlowState(
      m49Fixture())).inspect(categoryId:'book');
    expect(wrongCategory.status,NativeM49TaskEvidenceStatus.inactive);
  });

  test('exclusions are preview only; actual task matching stays unfiltered',(){
    final c=decodeMediaFlowState(m49Fixture());
    final reader=NativeM49DashboardTaskAudit(c);
    final filtered=reader.inspect(excludedTitleIds:{'b','cross'});
    expect(filtered.currentMatch!.title.id,'b');
    expect(filtered.currentMatch!.recommendationIndex,1);
    expect(filtered.queuePreview!.first!.title.id,'a');
    expect(filtered.queuePreview!.first!.recommendationIndex,3);
    expect(reader.inspect().queuePreview!.first!.title.id,'b');
    expect(c.collectionAssignments.single.traversedTitleIds,isEmpty);
    expect(c.currentTask!.libraryId,'b');
  });

  test('100k titles are not mutated or copied by preview',(){
    final c=decodeMediaFlowState(m49Fixture(extra:99997));
    final audit=NativeM49DashboardTaskAudit(c);
    expect(c.library.length,100000);
    final evidence=audit.inspect();
    expect(evidence.confirmed,true);
    expect(evidence.queuePreview!.candidates.length,3);
    expect(identical(audit.catalog.library,c.library),true);
    expect(c.categoryQueues['anime'],['c:as1','t:a','t:b']);
    expect(c.collectionAssignments.single.traversedTitleIds,isEmpty);
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('Dashboard shows read-only provenance and opens Personal Order',(
      tester)async{
    tester.view.physicalSize=const Size(980,1800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c=decodeMediaFlowState(m49Fixture());
    var opened=false;
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:DashboardScreen(repository:_Repo(c),
        openLibrary:(){},openHistory:(){},
        openPersonalOrder:()=>opened=true))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m49-task-id-label')),findsOneWidget);
    expect(find.textContaining('Saved exact Library ID: b'),findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('m49-dashboard-evidence')));
    await tester.tap(find.byKey(const Key('m49-dashboard-evidence')));
    await tester.pumpAndSettle();
    expect(find.textContaining('confirmedQueueSource'),findsOneWidget);
    expect(find.byKey(const Key('m49-readonly-warning')),findsOneWidget);
    expect(find.textContaining('Beta · queue rank #1'),findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('m49-open-order')));
    await tester.tap(find.byKey(const Key('m49-open-order')));
    expect(opened,true);
    expect(c.collectionAssignments.single.traversedTitleIds,isEmpty);
  });

  testWidgets('Dashboard displays saved vs local draft without committing',(
      tester)async{
    tester.view.physicalSize=const Size(980,1800);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c=decodeMediaFlowState(m49Fixture());
    final plan=NativeM44PersonalOrderPlan(ownerId:'owner')
      ..observe(c,currentOwnerId:'owner');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:DashboardScreen(repository:_Repo(c),personalOrderPlan:plan,
        openLibrary:(){},openHistory:(){}))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('m49-dashboard-evidence')));
    await tester.tap(find.byKey(const Key('m49-dashboard-evidence')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m49-draft-first')),findsNothing);
    plan.positionMixedToken('anime','t:a',1);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m49-draft-first')),findsOneWidget);
    expect(find.textContaining('Local draft first: Alpha'),findsOneWidget);
    await tester.enterText(find.byKey(const Key('m49-exclusions')),'b');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m49-saved-first')),findsOneWidget);
    expect(c.currentTask!.libraryId,'b');
    plan.discard();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m49-draft-first')),findsNothing);
    plan.dispose();
  });
}
