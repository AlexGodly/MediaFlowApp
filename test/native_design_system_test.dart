import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/app/mediaflow_shell.dart';
import 'package:mediaflow_app/design_system/mediaflow_components.dart';
import 'package:mediaflow_app/design_system/mediaflow_theme.dart';

void main() {
  test('v410 foundation tokens and all three appearance palettes', () {
    final dark = MediaFlowTheme.palette(MediaFlowAppearance.dark);
    final light = MediaFlowTheme.palette(MediaFlowAppearance.light);
    final amoled = MediaFlowTheme.palette(MediaFlowAppearance.amoled);
    expect(dark.background, const Color(0xFF0E111A));
    expect(dark.panel, const Color(0xFF161B29));
    expect(dark.accent, const Color(0xFFE8A94A));
    expect(dark.overused, const Color(0xFFE8607A));
    expect(light.background, const Color(0xFFF5F6F8));
    expect(light.text, const Color(0xFF171A21));
    expect(amoled.background, Colors.black);
    expect(amoled.panel, const Color(0xFF050505));
    for (final mode in MediaFlowAppearance.values) {
      final theme = MediaFlowTheme.build(mode);
      expect(theme.extension<MediaFlowTokens>(), isNotNull);
      expect(theme.cardTheme.color, MediaFlowTheme.palette(mode).panel);
      expect(theme.scaffoldBackgroundColor,
          MediaFlowTheme.palette(mode).background);
    }
  });

  test('responsive breakpoints match original desktop breakpoint', () {
    expect(MediaFlowBreakpoints.desktop, 1081);
    expect(MediaFlowBreakpoints.pagePadding(320), 10);
    expect(MediaFlowBreakpoints.pagePadding(520), 14);
    expect(MediaFlowBreakpoints.pagePadding(1100), 20);
  });

  testWidgets('component library inherits light and AMOLED palette',
      (tester) async {
    for (final appearance in [MediaFlowAppearance.light, MediaFlowAppearance.amoled]) {
      await tester.pumpWidget(MaterialApp(
        theme: MediaFlowTheme.build(appearance),
        home: Scaffold(body: MfPanel(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            MfPageHeader(title: 'Library', subtitle: '100 titles'),
            MfBadge(label: 'Active', icon: Icons.play_arrow),
            MfEmptyState(title: 'No titles', message: 'Import one to start'),
          ],
        ))),
      ));
      expect(find.text('100 titles'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('No titles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('desktop sidebar exposes semantic and keyboard-accessible nav',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MediaFlowShell()));
    await tester.pump();
    expect(find.byType(MfNavigationTile), findsNWidgets(14));
    expect(find.byKey(const ValueKey('nav-settings')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pump();
    expect(find.text('Native application preferences'), findsOneWidget);
    expect(find.text('Appearance'), findsWidgets);
    await tester.tap(find.text('AMOLED').last);
    await tester.pump();
    expect(find.byType(MfPanel), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('v507 1080 uses bottom bar; 1081 uses website sidebar',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: MediaFlowShell()));
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    tester.view.physicalSize = const Size(1081, 840);
    await tester.pump();
    expect(find.byType(MfNavigationTile), findsNWidgets(9));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
