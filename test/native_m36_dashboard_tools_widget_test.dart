import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/features/dashboard/native_m36_dashboard_tools_panel.dart';
import 'package:mediaflow_app/services/native_m36_dashboard_tools.dart';

void main(){
  final category=MediaFlowCategory.fromJson({
    'id':'anime','name':'Anime','icon':'◈'
  });
  final titles=[
    MediaFlowTitle.fromJson({
      'id':'a','title':'Title A','categoryId':'anime',
      'status':'active','priority':'medium','rating':null,'coverUrl':'',
    }),
    MediaFlowTitle.fromJson({
      'id':'b','title':'Title B','categoryId':'anime',
      'status':'planned','rating':8,'coverUrl':'https://example.invalid/b.png',
    }),
    MediaFlowTitle.fromJson({
      'id':'c','title':'Title C','categoryId':'anime',
      'status':'active','coverUrl':'',
    }),
  ];
  final catalog=MediaFlowCatalog(categories:[category],library:titles);

  testWidgets('phone renders stopwatch runtime calculator and review queues',
      (tester) async {
    final ctl=NativeM36DashboardToolsController();
    addTearDown(ctl.dispose);
    tester.view.physicalSize=const Size(340,760);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:ListView(children:[
        NativeM36DashboardToolsPanel(
          controller:ctl,catalog:catalog,openLibrary:()=>opened++),
      ]),
    )));
    await tester.pump();
    expect(find.text('STOPWATCH'),findsOneWidget);
    expect(find.text('RUNTIME CALCULATOR'),findsOneWidget);
    expect(find.text('RATE YOUR LIBRARY',skipOffstage:false),findsOneWidget);
    expect(find.text('MISSING COVERS',skipOffstage:false),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('calculator fields calculate a result and carry it forward',
      (tester) async {
    final ctl=NativeM36DashboardToolsController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:ListView(children:[NativeM36DashboardToolsPanel(
        controller:ctl,catalog:catalog,openLibrary:() {},
      )]),
    )));
    await tester.enterText(
      find.byKey(const Key('m36-chain-0-m-0')),'20');
    await tester.enterText(
      find.byKey(const Key('m36-chain-1-m-0')),'10');
    await tester.ensureVisible(find.byKey(const Key('m36-calculate')));
    await tester.tap(find.byKey(const Key('m36-calculate')));
    await tester.pump();
    expect(find.text('00:30:00'),findsOneWidget);
    expect(ctl.calculator.proposedLoggingMinutes,30);
    await tester.testTextInput.hide();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('m36-continue-result')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('m36-continue-result')));
    await tester.pump();
    expect(ctl.calculator.chain.first.totalSeconds,1800);
    expect(ctl.calculator.chain.last.totalSeconds,0);
  });

  testWidgets('stopwatch does not overwrite account data and can reset',
      (tester) async {
    final ctl=NativeM36DashboardToolsController();
    addTearDown(ctl.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:ListView(children:[NativeM36DashboardToolsPanel(
        controller:ctl,catalog:catalog,openLibrary:() {},
      )]),
    )));
    expect(ctl.stopwatch.isRunning,false);
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(ctl.stopwatch.isRunning,true);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(ctl.stopwatch.isRunning,false);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(ctl.stopwatch.elapsed,Duration.zero);
    expect(catalog.library[0].rating,isNull);
    expect(tester.takeException(),isNull);
  });
}
