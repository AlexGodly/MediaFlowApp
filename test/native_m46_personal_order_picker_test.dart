import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/personal_order/personal_order_screen.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m44_personal_order_plan.dart';
import 'package:mediaflow_app/services/native_m46_title_picker.dart';

MediaFlowCatalog m46Fixture({int count=130})=>decodeMediaFlowState({
  'categories':[
    {'id':'anime','name':'Anime'},
    {'id':'book','name':'Books'},
  ],
  'library':[
    for(var i=0;i<count;i++)
      {'id':'id' + i.toString(),
        'title':'Title ' + i.toString().padLeft(3,'0'),
        'categoryId':i.isEven?'anime':'book',
        'status':i%3==0?'completed':'active',
        'priority':i%5==0?'high':'low',
        'progress':i.toDouble(),'total':200},
  ],
  'orderPlan':{
    'titleIds':['id0','id1','id2'],
  },
});

class _M46Repo extends MediaFlowLibraryRepository {
  _M46Repo(this.catalog);
  final MediaFlowCatalog catalog;
  @override
  Future<MediaFlowCatalog> load() async=>catalog;
}

void main() {
  test('paginates entire eligible catalog beyond old 60 cap',(){
    final source=m46Fixture(count:163);
    final p=NativeM46TitlePicker(source,source.personalOrderIds);
    final first=p.browse(pageSize:40);
    final second=p.browse(page:1,pageSize:40);
    final last=p.browse(page:3,pageSize:40);
    expect(first.total,160);
    expect(first.pageCount,4);
    expect(first.titles.first.id,'id3');
    expect(first.titles.last.id,'id42');
    expect(second.titles.first.id,'id43');
    expect(last.titles.last.id,'id162');
    expect(last.hasNext,false);
    expect(p.browse(page:100,pageSize:40).page,3);
    expect(()=>p.browse(page:-1),throwsFormatException);
    expect(()=>p.browse(pageSize:201),throwsFormatException);
  });

  test('membership, category, status, priority and keyword compose',(){
    final source=m46Fixture();
    final p=NativeM46TitlePicker(source,source.personalOrderIds);
    expect(p.browse(membership:NativeM46Membership.alreadyAdded).total,3);
    expect(p.browse(membership:NativeM46Membership.all).total,130);
    final filtered=p.browse(
      categoryId:'anime',status:'active',priority:'high',
      membership:NativeM46Membership.notAdded,
      search:'title',pageSize:100);
    expect(filtered.titles,isNotEmpty);
    for(final title in filtered.titles) {
      expect(title.categoryId,'anime');
      expect(title.status,'active');
      expect(title.priority,'high');
      expect(source.personalOrderIds.contains(title.id),false);
    }
    expect(p.browse(search:'id129').titles.single.id,'id129');
    expect(p.browse(search:'absent').total,0);
  });

  test('sort affects display but never changes saved Personal Order order',(){
    final source=m46Fixture();
    final before=List<String>.of(source.personalOrderIds);
    final p=NativeM46TitlePicker(source,before);
    expect(p.browse(sort:NativeM46Sort.alphabetical,pageSize:200)
        .titles.first.id,'id3');
    expect(p.browse(sort:NativeM46Sort.priority,pageSize:200)
        .titles.first.priority,'high');
    expect(p.browse(sort:NativeM46Sort.progress,pageSize:200)
        .titles.first.id,'id129');
    expect(source.personalOrderIds,before);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('duplicate Library ID never exposed for staging',(){
    final source=decodeMediaFlowState({
      'categories':[{'id':'anime','name':'Anime'}],
      'library':[
        {'id':'ok','title':'Original','categoryId':'anime'},
        {'id':'dup','title':'One','categoryId':'anime'},
        {'id':'dup','title':'Two','categoryId':'anime'},
        {'id':'','title':'Blank','categoryId':'anime'},
      ],
      'orderPlan':{'titleIds':[]},
    });
    expect(NativeM46TitlePicker(source,[]).browse()
        .titles.map((title)=>title.id),['ok']);
  });

  test('100k-title picker remains paged and source stays immutable',(){
    final source=m46Fixture(count:100000);
    final result=NativeM46TitlePicker(source,source.personalOrderIds)
        .browse(page:2400,pageSize:40);
    expect(result.total,99997);
    expect(result.titles.length,40);
    expect(source.personalOrderIds,['id0','id1','id2']);
  },timeout:const Timeout(Duration(minutes:2)));

  testWidgets('Library picker traverses later pages and stages title locally',
      (tester) async {
    tester.view.physicalSize=const Size(920,1300);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final snapshot=m46Fixture(count:105);
    final plan=NativeM44PersonalOrderPlan(ownerId:'user');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PersonalOrderScreen(repository:_M46Repo(snapshot),
        plan:plan,currentOwnerId:'user'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-plan-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-available-tab')));
    await tester.pumpAndSettle();
    expect(find.textContaining('102 matching Library titles'),findsOneWidget);
    await tester.tap(find.byKey(const Key('m45-next-page')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m45-row-id43')),findsOneWidget);
    await tester.tap(find.byKey(const Key('m45-check-id43')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-apply-bulk')));
    await tester.pumpAndSettle();
    expect(plan.directTitleIds.last,'id43');
    expect(snapshot.personalOrderIds,['id0','id1','id2']);
    plan.dispose();
  });

  testWidgets('phone layout exposes Tools & Filters and display modes',
      (tester) async {
    tester.view.physicalSize=const Size(360,900);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final snapshot=m46Fixture(count:12);
    final plan=NativeM44PersonalOrderPlan(ownerId:'user');
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PersonalOrderScreen(repository:_M46Repo(snapshot),
        plan:plan,currentOwnerId:'user'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m45-plan-mode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m45-row-id0')),findsWidgets);
    await tester.tap(find.byKey(const Key('m46-tools-filters')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('m46-view-mode')),findsOneWidget);
    expect(find.byKey(const Key('m46-page-size')),findsOneWidget);
    plan.dispose();
  });
}
