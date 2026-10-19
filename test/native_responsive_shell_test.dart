import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/app/mediaflow_shell.dart';

Future<void> size(WidgetTester tester, double width, double height) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(const MaterialApp(home: MediaFlowShell()));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // Widget-test window overrides must never leak to other tests.
  });

  testWidgets('phone uses bottom navigation with accessible More menu',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await size(tester, 360, 780);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Collections'), findsWidgets);
    await tester.tap(find.text('Collections').last);
    await tester.pumpAndSettle();
    expect(find.text('Collections'), findsWidgets);
  });

  testWidgets('v507 tablet uses bottom navigation, not desktop rail', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await size(tester, 820, 560);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Fresh Episodes'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shows sidebar without bottom bar or rail',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await size(tester, 1440, 900);
    expect(find.byKey(const ValueKey('nav-dashboard')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-history')));
    await tester.pump();
    expect(find.text('History'), findsWidgets);
  });
}
