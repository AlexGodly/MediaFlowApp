// Beta 16: the account is decoded, replayed and encoded in the background, the
// device keeps the cloud copy in its compressed form, and an unchanged cloud
// copy is not downloaded again.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_controller.dart';
import 'package:mediaflow/src/data/account_ops.dart';
import 'package:mediaflow/src/data/local_cache.dart';
import 'package:mediaflow/src/data/sync_engine.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/logic/xp_preview.dart';
import 'package:mediaflow/src/state/lazy_copy.dart';
import 'package:mediaflow/src/state/state_codec.dart';

import 'support/fakes.dart';

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map).cast<String, dynamic>();

Map<String, dynamic> _account() => deepCopyState((_fixture('log-mixed-batch')['before'] as Map).cast<String, dynamic>());

Map<String, dynamic> _item(Map<String, dynamic> s, String id) =>
    (s['library'] as List).cast<Map>().firstWhere((i) => i['id'] == id).cast<String, dynamic>();

void main() {
  test('uploads the compressed form, decoded and encoded in an isolate', () async {
    final cloud = FakeCloud(_account(), compressed: true);
    final req = LogRequest.create([const LogEntry(libraryId: 'lib_alpha', reached: 6)]);
    final result = await syncOnce(cloud, 'u', [BatchLogOp(req)]);
    expect(result.uploaded, 1);
    expect(isCompressedStateData(result.raw), isTrue);
    expect(_item(result.state!, 'lib_alpha')['progress'], 6);
    expect(_item(cloud.state, 'lib_alpha')['progress'], 6);
    expect(jsonEncode(decodeStateData(result.raw)), jsonEncode(cloud.state));
  });

  test('an unchanged cloud copy is not downloaded again', () async {
    final cloud = FakeCloud(_account(), compressed: true);
    final first = await syncOnce(cloud, 'u', const []);
    expect(cloud.fetchCalls, 1);

    final again = await syncOnce(cloud, 'u', const [], knownRaw: first.raw, knownUpdatedAt: first.updatedAt);
    expect(cloud.fetchCalls, 1);
    expect(again.state, isNull, reason: 'nothing changed: keep the copy on screen');
    expect(identical(again.raw, first.raw), isTrue);

    // A change made here is replayed on the copy already on the device.
    final req = LogRequest.create([const LogEntry(libraryId: 'lib_alpha', reached: 6)]);
    final up = await syncOnce(cloud, 'u', [BatchLogOp(req)], knownRaw: first.raw, knownUpdatedAt: first.updatedAt);
    expect(cloud.fetchCalls, 1);
    expect(up.uploaded, 1);
    expect(_item(cloud.state, 'lib_alpha')['progress'], 6);

    // The website saved: the newer copy is downloaded and kept.
    cloud.websiteSaves((s) => (s['library'] as List).cast<Map>().firstWhere((i) => i['id'] == 'lib_beta')['rating'] = 9);
    final pulled = await syncOnce(cloud, 'u', const [], knownRaw: up.raw, knownUpdatedAt: up.updatedAt);
    expect(cloud.fetchCalls, 2);
    expect(_item(pulled.state!, 'lib_beta')['rating'], 9);
    expect(_item(pulled.state!, 'lib_alpha')['progress'], 6);
  });

  test('the website saving between the check and the write is never overwritten', () async {
    final cloud = FakeCloud(_account(), compressed: true);
    final first = await syncOnce(cloud, 'u', const []);
    cloud.beforeNextCas = (c) => c.websiteSaves((s) {
          (s['library'] as List).cast<Map>().firstWhere((i) => i['id'] == 'lib_beta')['rating'] = 9;
        });
    final req = LogRequest.create([const LogEntry(libraryId: 'lib_alpha', reached: 6)]);
    final result = await syncOnce(cloud, 'u', [BatchLogOp(req)], knownRaw: first.raw, knownUpdatedAt: first.updatedAt);
    expect(result.uploaded, 1);
    expect(cloud.casCalls, 2);
    expect(_item(cloud.state, 'lib_beta')['rating'], 9);
    expect(_item(cloud.state, 'lib_alpha')['progress'], 6);
  });

  test('an old uncompressed row is kept compressed on the device', () async {
    final cloud = FakeCloud(_account());
    final result = await syncOnce(cloud, 'u', const []);
    expect(isCompressedStateData(result.raw), isTrue);
    expect(jsonEncode(decodeStateData(result.raw)), jsonEncode(cloud.state));
  });

  test('cache files: Beta 15 layout is read and compressed, Beta 16 layout round-trips', () {
    final dir = Directory.systemTemp.createTempSync('mf-cache');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/a.json', pendingPath = '${dir.path}/a-pending.json';
    final account = _account();
    final req = LogRequest.create([const LogEntry(libraryId: 'lib_alpha', reached: 6)]);
    File(path).writeAsStringSync(jsonEncode({'version': 3, 'userId': 'u', 'baseUpdatedAt': 'v1', 'base': account, 'pending': []}));
    File(pendingPath).writeAsStringSync(jsonEncode({'userId': 'u', 'pending': [BatchLogOp(req).toJson()]}));

    final old = readCachedAccount(path, pendingPath, 'u');
    expect(old.upgraded, isTrue);
    expect(isCompressedStateData(old.raw), isTrue);
    expect(jsonEncode(decodeStateData(old.raw)), jsonEncode(account));
    expect(old.pending.single.id, req.groupId);
    expect(old.baseUpdatedAt, 'v1');

    File(path).writeAsStringSync(jsonEncode({'version': 4, 'userId': 'u', 'baseUpdatedAt': 'v2', 'baseRaw': old.raw}));
    final next = readCachedAccount(path, pendingPath, 'u');
    expect(next.upgraded, isFalse);
    expect(next.baseUpdatedAt, 'v2');
    expect(jsonEncode(next.raw), jsonEncode(old.raw));
    expect(readCachedAccount(path, pendingPath, 'someone else').raw, isNull);
  });

  test('the app logs, restarts offline and syncs without re-downloading', () async {
    final cloud = FakeCloud(_account(), compressed: true);
    final cache = MemoryCache();
    final a = AccountController(userId: 'u', email: 'e', cloud: cloud, cache: cache);
    await a.start();
    expect(a.status, SyncState.synced);
    expect(cloud.fetchCalls, 1);

    final outcome = await a.log([const LogEntry(libraryId: 'lib_alpha', reached: 6)]);
    expect(outcome.applied, isTrue);
    expect(_item(a.view!.state, 'lib_alpha')['progress'], 6);
    for (var i = 0; i < 200 && a.pendingCount > 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(a.pendingCount, 0);
    expect(cloud.fetchCalls, 1, reason: 'the cloud had not changed, so the copy here was used');
    expect(_item(cloud.state, 'lib_alpha')['progress'], 6);
    a.dispose();

    // Restart: the device copy opens first, then a check finds nothing new.
    final b = AccountController(userId: 'u', email: 'e', cloud: cloud, cache: cache);
    await b.start();
    expect(_item(b.view!.state, 'lib_alpha')['progress'], 6);
    expect(cloud.fetchCalls, 1);
    b.dispose();
  });

  test('XP for this log: the background trial save matches one on the account itself', () async {
    final fx = _fixture('rec-quick-progress');
    final before = (fx['before'] as Map).cast<String, dynamic>();
    final task = (fx['task'] as Map).cast<String, dynamic>();
    final draft = (fx['logDraft'] as Map).cast<String, dynamic>();
    final cloud = FakeCloud(deepCopyState(before), compressed: true);
    final a = AccountController(userId: 'u', email: 'e', cloud: cloud, cache: MemoryCache());
    await a.start();
    final viaIsolate = await a.previewXp(task, draft);
    final direct = xpPreviewData(deepCopyState(a.view!.state), deepCopyState(task), deepCopyState(draft));
    expect(jsonEncode(viaIsolate.data), jsonEncode(direct));
    a.dispose();
  });

  test('a lazy copy copies only what is read, and never changes the original', () {
    final original = _account();
    final text = jsonEncode(original);
    final copy = LazyStateCopy(original);
    (copy['library'] as List).removeAt(0);
    copy['newKey'] = 1;
    copy.remove('stopwatch');
    expect(copy.touched, {'library', 'newKey', 'stopwatch'});
    expect(identical(copy.peek('sessions'), original['sessions']), isTrue);
    expect(copy.containsKey('stopwatch'), isFalse);
    expect(jsonEncode(original), text);
    expect((jsonDecode(jsonEncode(copy)) as Map)['library'].length, (original['library'] as List).length - 1);
  });
}
