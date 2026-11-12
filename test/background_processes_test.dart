// Background Processes is on every screen (pushed pages too), open or
// minimised, and the minimised icon can be dragged.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_controller.dart';
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/ui/floating_dock.dart';
import 'package:mediaflow/src/ui/theme.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('shown over pushed pages; the minimised icon drags', (tester) async {
    final fx = jsonDecode(File('test/fixtures/log-mixed-batch.json').readAsStringSync()) as Map;
    final state = deepCopyState((fx['before'] as Map).cast<String, dynamic>());
    (state['settings'] as Map)['v441RecoveryUI'] = {'visibility': 'always'};
    final account = AccountController(userId: 'u', email: 't@example.com', cloud: FakeCloud(state), cache: MemoryCache(), background: runInline);
    await tester.runAsync(account.start);
    ProcessesUi.minimized.value = false;
    ProcessesUi.miniPos.value = null;

    await tester.pumpWidget(MaterialApp(
      theme: MF.theme(),
      navigatorKey: ProcessesUi.navigatorKey,
      navigatorObservers: [ProcessesUi.observer],
      builder: (context, child) => Stack(fit: StackFit.expand, children: [
        child!,
        GlobalBackgroundProcesses(openRecovery: (c, a, tab) {}),
      ]),
      home: const Scaffold(body: Text('Home')),
    ));
    ProcessesUi.host.value = account;
    await tester.pumpAndSettle();
    expect(find.text('Background Processes'), findsOneWidget);

    ProcessesUi.navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('A pushed page'))));
    await tester.pumpAndSettle();
    expect(find.text('A pushed page'), findsOneWidget);
    expect(find.text('Background Processes'), findsOneWidget);

    await tester.tap(find.byTooltip('Minimise to an icon'));
    await tester.pumpAndSettle();
    expect(find.text('Background Processes'), findsNothing);
    final icon = find.byIcon(Icons.layers_rounded);
    expect(icon, findsOneWidget);
    final before = tester.getCenter(icon);
    await tester.drag(icon, const Offset(-120, -200));
    await tester.pumpAndSettle();
    final after = tester.getCenter(icon);
    expect(after.dx, lessThan(before.dx - 60));
    expect(after.dy, lessThan(before.dy - 100));
    expect(ProcessesUi.miniPos.value, isNotNull);
    ProcessesUi.host.value = null;
    ProcessesUi.setMinimized(false);
  });
}
