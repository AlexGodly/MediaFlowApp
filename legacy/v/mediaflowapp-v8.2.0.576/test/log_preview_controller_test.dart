// 8.0.1.574: Log a title's XP preview runs in the background like the
// logging workspace's, and equals what saving earns.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_controller.dart';
import 'package:mediaflow/src/data/sync_engine.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/logic/stats.dart' show xpMetrics;
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/util/js.dart';

import 'support/fakes.dart';

Map<String, dynamic> _account() {
  final fx = jsonDecode(File('test/fixtures/log-mixed-batch.json').readAsStringSync()) as Map;
  return deepCopyState((fx['before'] as Map).cast<String, dynamic>());
}

void main() {
  test('preview = award', () async {
    final account = AccountController(
      userId: 'u',
      email: 'e',
      cloud: FakeRecordCloud(_account()),
      cache: MemoryCache(),
      background: runInline,
      fallbackInterval: Duration.zero,
      deviceId: 'test-device',
    );
    await account.start();
    final title = asList(account.view!.state['library'])
        .map(asMap)
        .firstWhere((i) => jsStr(i!['status']) != 'completed' && (jsNum(i['total']) == 0 || jsNum(i['progress']) + 2 < jsNum(i['total'])))!;
    final entry = LogEntry(libraryId: jsStr(title['id']), amount: 2, minutes: 40);
    final preview = await account.previewLog([entry]);
    expect(preview, isNotNull);
    final before = xpMetrics(account.view!.state).total;
    final outcome = await account.log([entry]);
    expect(outcome.applied, isTrue);
    expect(xpMetrics(account.view!.state).total - before, preview);
    account.dispose();
  });
}
