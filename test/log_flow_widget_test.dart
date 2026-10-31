// Drives the real screens: Library → title → "Log progress" → Save, then checks
// the log reached the (fake) cloud row exactly once.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_controller.dart';
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/ui/home_shell.dart';
import 'package:mediaflow/src/ui/theme.dart';

import 'support/fakes.dart';

Map<String, dynamic> _account() {
  final fx = jsonDecode(File('test/fixtures/log-mixed-batch.json').readAsStringSync()) as Map;
  return deepCopyState((fx['before'] as Map).cast<String, dynamic>());
}

Future<void> _settle(WidgetTester tester) async {
  // Let real async work (cache/cloud futures) finish, then rebuild.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('log progress for a Library title and sync it', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final cloud = FakeCloud(_account());
    final account = AccountController(
      userId: 'u',
      email: 'tester@example.com',
      cloud: cloud,
      cache: MemoryCache(),
      copyState: (s) async => deepCopyState(s),
    );
    await tester.runAsync(account.start);
    expect(account.hasData, isTrue);

    await tester.pumpWidget(MaterialApp(theme: MF.theme(), home: HomeShell(account: account)));
    await _settle(tester);

    expect(find.text('Test Anime Alpha'), findsOneWidget);
    await tester.tap(find.text('Test Anime Alpha'));
    await _settle(tester);

    expect(find.text('Log progress'), findsOneWidget);
    await tester.tap(find.text('Log progress'));
    await _settle(tester);

    // Defaults to "Episode reached" = current progress + 1 (3 → 4).
    final reached = find.widgetWithText(TextField, 'Episode reached');
    expect(reached, findsOneWidget);
    expect(tester.widget<TextField>(reached).controller!.text, '4');

    await tester.enterText(reached, '6');
    await tester.pump();
    final save = find.textContaining('Log 3 episodes');
    expect(save, findsOneWidget);
    await tester.tap(save);
    await _settle(tester);

    // Wait for the background upload.
    for (var i = 0; i < 40 && (account.pendingCount > 0 || account.status == SyncState.syncing); i++) {
      await _settle(tester);
    }
    expect(account.pendingCount, 0);
    expect(account.status, SyncState.synced);

    final cloudItem = (cloud.state['library'] as List).cast<Map>().firstWhere((i) => i['id'] == 'lib_alpha');
    expect(cloudItem['progress'], 6);
    final sessions = (cloud.state['sessions'] as List).cast<Map>();
    expect(sessions.where((s) => s['source'] == 'batch').length, 1);
    expect(sessions.last['actualAmount'], 3);
    expect(sessions.last['minutes'], 72);

    // The new log shows in History.
    await tester.tap(find.text('History'));
    await _settle(tester);
    expect(find.textContaining('3 episodes'), findsWidgets);
  });
}
