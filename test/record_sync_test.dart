// Per-record sync with the website (v556 `mediaflow_records`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_controller.dart';
import 'package:mediaflow/src/data/account_ops.dart';
import 'package:mediaflow/src/data/records.dart';
import 'package:mediaflow/src/data/sync_engine.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/state/state_codec.dart';

import 'support/fakes.dart';

Map<String, dynamic> _account() {
  final fx = jsonDecode(File('test/fixtures/log-mixed-batch.json').readAsStringSync()) as Map;
  return deepCopyState((fx['before'] as Map).cast<String, dynamic>());
}

Map<String, dynamic> _item(Map<String, dynamic> s, String id) =>
    (s['library'] as List).cast<Map>().firstWhere((i) => i['id'] == id).cast<String, dynamic>();

BatchLogOp _log(String id, int reached) => BatchLogOp(LogRequest.create([LogEntry(libraryId: id, reached: reached)]));

void main() {
  test('a moved account is read from its records', () async {
    final start = _account();
    final cloud = FakeRecordCloud(start);
    final r = await syncOnce(cloud, 'u', const [], background: runInline);
    expect(r.index, isNotNull);
    expect(r.index!.entries.length, cloud.rows.length - 1); // all but the meta row
    expect(jsStringify(r.state), jsStringify(start));
    expect(cloud.casCalls, 0, reason: 'the single row is not written');
  });

  test('a log uploads only the records it changed', () async {
    final cloud = FakeRecordCloud(_account());
    final first = await syncOnce(cloud, 'u', const [], background: runInline);
    final r = await syncOnce(cloud, 'u', [_log('lib_alpha', 6)],
        knownRaw: first.raw, knownIndex: first.index, background: runInline);
    expect(r.uploaded, 1);
    expect(cloud.uploadedRows, lessThan(cloud.rows.length ~/ 2), reason: 'only changed records');
    final site = cloud.recordState;
    expect(_item(site, 'lib_alpha')['progress'], 6);
    expect((site['sessions'] as List).length, 2);
    expect(jsStringify(site), jsStringify(r.state), reason: 'the website rebuilds exactly what the app has');
  });

  test('a change the website made is pulled and kept under the app\'s log', () async {
    final cloud = FakeRecordCloud(_account());
    final first = await syncOnce(cloud, 'u', const [], background: runInline);
    cloud.websiteSavesRecords((s) => _item(s, 'lib_beta')['rating'] = 9);
    final r = await syncOnce(cloud, 'u', [_log('lib_alpha', 6)],
        knownRaw: first.raw, knownIndex: first.index, background: runInline);
    expect(_item(r.state!, 'lib_beta')['rating'], 9);
    expect(_item(r.state!, 'lib_alpha')['progress'], 6);
    expect(_item(cloud.recordState, 'lib_beta')['rating'], 9);
    expect(_item(cloud.recordState, 'lib_alpha')['progress'], 6);
  });

  test('the app\'s own rows coming back are not changes', () async {
    final cloud = FakeRecordCloud(_account());
    final first = await syncOnce(cloud, 'u', const [], background: runInline);
    final second = await syncOnce(cloud, 'u', [_log('lib_alpha', 6)],
        knownRaw: first.raw, knownIndex: first.index, background: runInline);
    final uploads = cloud.uploadedRows;
    final third = await syncOnce(cloud, 'u', const [], knownRaw: second.raw, knownIndex: second.index, background: runInline);
    expect(third.state, isNull, reason: 'nothing new');
    expect(cloud.uploadedRows, uploads);
  });

  test('a title deleted on the website goes away here', () async {
    final cloud = FakeRecordCloud(_account());
    final first = await syncOnce(cloud, 'u', const [], background: runInline);
    cloud.websiteSavesRecords((s) => (s['library'] as List).removeWhere((i) => (i as Map)['id'] == 'lib_beta'));
    final r = await syncOnce(cloud, 'u', const [], knownRaw: first.raw, knownIndex: first.index, background: runInline);
    expect((r.state!['library'] as List).any((i) => (i as Map)['id'] == 'lib_beta'), isFalse);
    expect(jsStringify(r.state), jsStringify(cloud.recordState));
  });

  test('a replayed log is not added twice', () async {
    final cloud = FakeRecordCloud(_account());
    final first = await syncOnce(cloud, 'u', const [], background: runInline);
    final op = _log('lib_alpha', 6);
    final a = await syncOnce(cloud, 'u', [op], knownRaw: first.raw, knownIndex: first.index, background: runInline);
    // The device lost track of the upload (e.g. the app closed): replay it.
    final b = await syncOnce(cloud, 'u', [op], knownRaw: first.raw, knownIndex: first.index, background: runInline);
    expect((cloud.recordState['sessions'] as List).length, 2);
    expect(jsStringify(a.state), jsStringify(b.state));
  });

  test('accounts not moved yet keep the single row', () async {
    final cloud = FakeRecordCloud(_account(), migrated: false);
    final r = await syncOnce(cloud, 'u', [_log('lib_alpha', 6)], background: runInline);
    expect(r.index, isNull);
    expect(cloud.casCalls, 1);
    expect(cloud.uploadCalls, 0);
  });

  test('the controller keeps the fallback copy current, marked for the website', () async {
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
    await account.log([const LogEntry(libraryId: 'lib_alpha', reached: 6)]);
    for (var n = 0; n < 200 && account.pendingCount > 0; n++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(account.pendingCount, 0);
    expect(_item(cloud.recordState, 'lib_alpha')['progress'], 6);
    await account.flushFallback();
    expect(cloud.fallbackWrites, greaterThanOrEqualTo(1));
    expect(_item(decodeStateData(cloud.fallback), 'lib_alpha')['progress'], 6);
    account.dispose();
  });
}
