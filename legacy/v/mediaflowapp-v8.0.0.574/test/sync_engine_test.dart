import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_ops.dart';
import 'package:mediaflow/src/data/sync_engine.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/state/state_codec.dart';

import 'support/fakes.dart';

Map<String, dynamic> _account() {
  final fx = jsonDecode(File('test/fixtures/log-mixed-batch.json').readAsStringSync()) as Map;
  return deepCopyState((fx['before'] as Map).cast<String, dynamic>());
}

int _sessions(Map<String, dynamic> s) => (s['sessions'] as List).length;

Map<String, dynamic> _item(Map<String, dynamic> s, String id) =>
    (s['library'] as List).cast<Map>().firstWhere((i) => i['id'] == id).cast<String, dynamic>();

void main() {
  test('uploads a pending log with a compare-and-swap write', () async {
    final cloud = FakeCloud(_account());
    final req = LogRequest.create([const LogEntry(libraryId: 'lib_alpha', reached: 6)]);
    final result = await syncOnce(cloud, 'u', [BatchLogOp(req)]);
    expect(result.uploaded, 1);
    expect(_sessions(cloud.state), 2);
    expect(_item(cloud.state, 'lib_alpha')['progress'], 6);
  });

  test('keeps a change the website saved in the meantime', () async {
    final cloud = FakeCloud(_account());
    cloud.beforeNextCas = (c) => c.websiteSaves((s) {
          (s['library'] as List).cast<Map>().firstWhere((i) => i['id'] == 'lib_beta')['rating'] = 9;
        });
    final req = LogRequest.create([const LogEntry(libraryId: 'lib_alpha', reached: 6)]);
    final result = await syncOnce(cloud, 'u', [BatchLogOp(req)]);
    expect(result.uploaded, 1);
    expect(cloud.casCalls, 2, reason: 'first write is rejected, second is re-applied on the newer copy');
    expect(_item(cloud.state, 'lib_beta')['rating'], 9);
    expect(_item(cloud.state, 'lib_alpha')['progress'], 6);
  });

  test('never logs the same request twice', () async {
    final cloud = FakeCloud(_account());
    final req = LogRequest.create([const LogEntry(libraryId: 'lib_alpha', reached: 6)]);
    await syncOnce(cloud, 'u', [BatchLogOp(req)]);
    final second = await syncOnce(cloud, 'u', [BatchLogOp(req)]);
    expect(second.uploaded, 0);
    expect(_sessions(cloud.state), 2);
  });

  test('a log made offline survives restart as JSON', () async {
    final req = LogRequest.create([const LogEntry(libraryId: 'lib_delta', amount: 2, minutes: 15)], note: 'train ride');
    final restored = LogRequest.fromJson((jsonDecode(jsonEncode(req.toJson())) as Map).cast<String, dynamic>());
    final cloud = FakeCloud(_account());
    await syncOnce(cloud, 'u', [BatchLogOp(restored)]);
    final delta = _item(cloud.state, 'lib_delta');
    expect(delta['progress'], 2);
    expect(delta['status'], 'active');
    final last = (cloud.state['sessions'] as List).last as Map;
    expect(last['note'], 'train ride');
    expect(last['minutes'], 15);
    expect(last['id'], req.sessionIds.first);
  });

  test('refuses to create data for an account without a row', () async {
    final cloud = FakeCloud(null);
    expect(() => syncOnce(cloud, 'u', const []), throwsA(isA<MissingCloudRow>()));
  });
}
