import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/app/mediaflow_shell.dart';

void main() {
  testWidgets('mobile shell navigates to Library and More', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // The legacy Flutter subset stays testable independently of the
    // production full-site WebView, which has no widget-test engine.
    await tester.pumpWidget(const MaterialApp(home: MediaFlowShell()));
    await tester.tap(find.byIcon(Icons.local_library_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsWidgets);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Statistics'), findsWidgets);
  });
}
