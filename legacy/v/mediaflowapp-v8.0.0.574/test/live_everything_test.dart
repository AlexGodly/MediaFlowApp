// 8.0.0.574: every change from another device (the website, another phone or
// PC) arrives live, not only the logging draft.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_controller.dart';
import 'package:mediaflow/src/data/sync_engine.dart';
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/util/js.dart';

import 'support/fakes.dart';

Map<String, dynamic> _account() {
  final fx = jsonDecode(File('test/fixtures/log-mixed-batch.json').readAsStringSync()) as Map;
  return deepCopyState((fx['before'] as Map).cast<String, dynamic>());
}

void main() {
  test('a title edited on the website arrives with the next probe', () async {
    final cloud = FakeRecordCloud(_account());
    final account = AccountController(
      userId: 'u',
      email: 'e',
      cloud: cloud,
      cache: MemoryCache(),
      background: runInline,
      fallbackInterval: Duration.zero,
      deviceId: 'test-device',
    );
    await account.start();
    expect(account.usesRecords, isTrue);
    expect(await account.probeNow(), isFalse, reason: 'nothing new');

    final id = jsStr(asMap(asList(account.view!.state['library']).first)!['id']);
    cloud.websiteSavesRecords((s) {
      final t = asList(s['library']).map(asMap).firstWhere((x) => jsStr(x!['id']) == id)!;
      t['coverUrl'] = 'https://example.invalid/new-cover.jpg';
      t['title'] = 'Changed on the website';
    });
    expect(await account.probeNow(), isTrue);
    final t = asList(account.view!.state['library']).map(asMap).firstWhere((x) => jsStr(x!['id']) == id)!;
    expect(t['coverUrl'], 'https://example.invalid/new-cover.jpg');
    expect(t['title'], 'Changed on the website');
    expect(await account.probeNow(), isFalse, reason: 'already merged');
    account.dispose();
  });
}
