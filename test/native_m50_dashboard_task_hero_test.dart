import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/dashboard/dashboard_screen.dart';
import 'package:mediaflow_app/features/dashboard/native_m50_dashboard_task_hero.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m50_task_display.dart';

Map<String,dynamic> m50Fixture({
  String titleId='good',String cover='not-a-url',
  bool active=true,bool duplicate=false,
  String recommendation='The Longest Saved Recommendation',
  double progress=3,double? total=12,
  List<String>? reasons,
}) => {
  'categories':[{'id':'anime','name':'Seasonal Anime','icon':'📺'}],
  'library':[
    {'id':'good','title':'Original Library Name',
      'coverUrl':cover,'categoryId':'anime','status':'active',
      'priority':'high','progress':progress,'total':total},
    if(duplicate)
      {'id':'good','title':'Ambiguous cover','categoryId':'anime',
        'coverUrl':'https://example.org/wrong.jpg'},
    {'id':'other','title':'Unrelated','categoryId':'anime',
      'coverUrl':'https://example.org/another.jpg'},
  ],
  'sessionActive':active,
  if(active)'currentTask':{
    'categoryId':'anime','title':recommendation,
    'libraryId':titleId,'low':2,'high':4,'unit':'episodes',
    'reasons':reasons??['Stay consistent','A very useful task reason'],
    'v287OrderSource':{
      'type':'collection','categoryId':'anime',
      'libraryId':titleId,'assignmentId':'collection-1',
    },
  },
};

class _Repo extends MediaFlowLibraryRepository {
  _Repo(this.value);
  final MediaFlowCatalog value;
  @override
  Future<MediaFlowCatalog> load() async=>value;
}

void main(){
  test('only an exact, unique Library ID permits poster and progress',(){
    final exact=NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(
        cover:'https://images.example.com/cover.png')));
    expect(exact.resolution,NativeM50TitleResolution.exact);
    expect(exact.title!.title,'Original Library Name');
    expect(exact.recommendedName,'The Longest Saved Recommendation');
    expect(exact.safeCoverUrl,'https://images.example.com/cover.png');
    expect(exact.progressPercent,0.25);
    expect(exact.sourceClaim,contains('not independently verified'));
    final ambiguous=NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(duplicate:true)));
    expect(ambiguous.resolution,NativeM50TitleResolution.ambiguousId);
    expect(ambiguous.title,isNull);
    expect(ambiguous.safeCoverUrl,isNull);
    expect(ambiguous.progressPercent,isNull);
    final missing=NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(titleId:'deleted')));
    expect(missing.resolution,NativeM50TitleResolution.missingTitle);
    expect(missing.title,isNull);
    final noId=NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(titleId:'')));
    expect(noId.resolution,NativeM50TitleResolution.missingId);
    expect(noId.title,isNull);
    expect(noId.recommendedName,'The Longest Saved Recommendation');
    final inactive=NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(active:false)));
    expect(inactive.resolution,NativeM50TitleResolution.inactive);
    expect(inactive.active,false);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('cover validation excludes unsafe addresses and credentials',(){
    for(final url in [
      'http://example.org/cover.jpg',
      'file:///var/private/cover.jpg',
      'javascript:alert(1)',
      '//example.org/cover.jpg',
      'https://me:secret@example.org/cover.jpg',
      'data:image/svg+xml;base64,abc',
      '',
    ]){
      final data=NativeM50TaskDisplay.fromCatalog(
        decodeMediaFlowState(m50Fixture(cover:url)));
      expect(data.safeCoverUrl,isNull,reason:url);
    }
    expect(NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(
        cover:'https://covers.example.com/hello.png'))).safeCoverUrl,
      'https://covers.example.com/hello.png');
  });

  test('progress rejects invalid denominators and caps overflowing values',(){
    final noTotal=NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(total:0)));
    expect(noTotal.progressPercent,isNull);
    expect(NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(progress:25,total:12)))
      .progressPercent,1);
    expect(NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(progress:-3,total:12)))
      .progressPercent,0);
    expect(NativeM50TaskDisplay.fromCatalog(
      decodeMediaFlowState(m50Fixture(progress:double.infinity,total:12)))
      .progressPercent,isNull);
  });

  testWidgets('compact 320px/360px task card never overflows and only navigates',(
      tester)async{
    for(final width in [320.0,360.0]){
      tester.view.physicalSize=Size(width,920);
      tester.view.devicePixelRatio=1;
      final catalog=decodeMediaFlowState(m50Fixture(
        recommendation:'A Very Very Very Very Long '
          'Recommended Name Even On Very Narrow Screens',
        reasons:['A difficult reason with many many words '
          'that should wrap instead of overflowing']));
      var library=0,personalOrder=0;
      await tester.pumpWidget(MaterialApp(home:Scaffold(
        body:SingleChildScrollView(
          child:NativeM50DashboardTaskHero(catalog:catalog,
            openLibrary:()=>library++,
            openPersonalOrder:()=>personalOrder++)))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('m50-compact-layout')),findsOneWidget);
      expect(find.byKey(const Key('m50-wide-layout')),findsNothing);
      expect(find.byKey(const Key('m50-task-progress')),findsOneWidget);
      expect(find.byKey(const Key('m50-task-source-claim')),findsOneWidget);
      expect(find.byKey(const Key('m49-task-id-label')),findsOneWidget);
      expect(tester.takeException(),isNull);
      await tester.ensureVisible(find.byKey(const Key('m50-browse-library')));
      await tester.tap(find.byKey(const Key('m50-browse-library')));
      await tester.ensureVisible(
        find.byKey(const Key('m50-open-personal-order')));
      await tester.tap(find.byKey(const Key('m50-open-personal-order')));
      expect(library,1);
      expect(personalOrder,1);
      expect(catalog.currentTask!.libraryId,'good');
      expect(catalog.sessions,isEmpty);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('wide desktop task card shows poster, evidence and reasons',(
      tester)async{
    tester.view.physicalSize=const Size(1120,900);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog=decodeMediaFlowState(m50Fixture(
      reasons:['one','two','three','four','five']));
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeM50DashboardTaskHero(
        catalog:catalog,openLibrary:(){}))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m50-wide-layout')),findsOneWidget);
    expect(find.byKey(const Key('m50-compact-layout')),findsNothing);
    expect(find.byKey(const Key('m50-task-poster')),findsOneWidget);
    expect(find.byKey(const Key('m50-task-target')),findsOneWidget);
    expect(find.byKey(const Key('m50-task-reason')),findsNWidgets(4));
    expect(find.text('+1 more reasons'),findsOneWidget);
    expect(find.byKey(const Key('m50-open-personal-order')),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('inactive or ambiguous tasks never show unrelated covers',(
      tester)async{
    tester.view.physicalSize=const Size(320,780);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeM50DashboardTaskHero(
        catalog:decodeMediaFlowState(m50Fixture(active:false)),
        openLibrary:(){}))));
    await tester.pumpAndSettle();
    expect(find.text('No active task'),findsOneWidget);
    expect(find.byKey(const Key('m50-task-poster')),findsNothing);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:SingleChildScrollView(child:NativeM50DashboardTaskHero(
        catalog:decodeMediaFlowState(m50Fixture(duplicate:true)),
        openLibrary:(){})))));
    await tester.pumpAndSettle();
    expect(find.textContaining('appears more than once'),findsOneWidget);
    expect(find.byType(Image),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('the live Dashboard uses the new hero and preserves History',(
      tester)async{
    tester.view.physicalSize=const Size(840,1200);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog=decodeMediaFlowState(m50Fixture());
    final repository=_Repo(catalog);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:DashboardScreen(repository:repository,
        openLibrary:(){},openHistory:(){}))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m50-task-hero')),findsOneWidget);
    expect(find.byKey(const Key('m49-dashboard-evidence')),
      findsOneWidget);
    expect(find.text('RECENT ACTIVITY'),findsOneWidget);
    expect(catalog.sessions,isEmpty);
  });
}
