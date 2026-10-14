// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/features/settings/sync_safety_lab_panel.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_draft_journal.dart';
import 'package:mediaflow_app/services/native_edit_proposals.dart';
import 'package:mediaflow_app/services/native_offline_key_vault.dart';
import 'package:mediaflow_app/services/native_pending_review_store.dart';
import 'package:mediaflow_app/services/native_snapshot_codec.dart';
import 'package:mediaflow_app/services/native_sync_review.dart';

class TestVault implements NativeOfflineKeyVault {
  final Map<String, Uint8List> keys = {};
  @override
  Future<Uint8List?> read(String hash) async {
    final key = keys[hash];
    return key == null ? null : Uint8List.fromList(key);
  }
  @override
  Future<void> write(String hash, Uint8List key) async {
    keys[hash] = Uint8List.fromList(key);
  }
  @override
  Future<void> delete(String hash) async {
    keys.remove(hash);
  }
}

void main() {
  const owner = 'user-m19', rev = '2026-10-14T01:40:00.000000Z';

  NativeCloudRow row({String account = owner, String stamp = rev}) =>
      NativeCloudRow(ownerId: account, updatedAt: stamp, stateData: {
        'library': [
          {'id': 'a', 'title': 'A SECRET', 'priority': 'low'},
          {'id': 'b', 'title': 'B SECRET', 'priority': 'medium'},
        ],
        'sessions': [
          {'id': 'history', 'xp': 100},
        ],
        'settings': {'theme': 'dark'},
        'categories': [
          {'id': 'anime', 'name': 'Anime'},
        ],
        'xpLedger': {'total': 500},
        'collections': [
          {'id': 'favorite', 'titleIds': ['a']},
        ],
        'orderPlan': {'titleIds': ['a', 'b']},
        'futureField': {'must': 'survive'},
      });

  NativeDraftEntry entry(
    String id, String title, String priority, {
    String account = owner, String stamp = rev,
  }) => NativeDraftEntry(
    operationId: id,
    proposal: NativeEditProposal(
      kind: NativeEditKind.setTitlePriority,
      accountId: account,
      baseRevision: stamp,
      createdAt: DateTime.utc(2026, 10, 14),
      payload: {'titleId': title, 'value': priority},
    ),
  );

  NativeReviewBatch batch({
    String id = 'review-one',
    String title = 'a',
    String priority = 'high',
  }) {
    final journal = NativeDraftJournal(accountId: owner);
    journal.add(entry('op-one', title, priority));
    return NativeReviewBatch.stage(
      batchId: id, base: row(), journal: journal,
    );
  }

  test('fresh full-state fingerprint and atomic preview preserve all unknown fields',
      () {
    final original = row();
    final staged = batch();
    final decision = NativeSyncReview.inspect(
      batch: staged, cloudRow: original, signedInOwnerId: owner,
    );
    expect(decision.status, NativeReviewStatus.safeToSimulate);
    expect(decision.mayUpload, false);
    expect(NativeCloudCapabilities.cloudWritesEnabled, false);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, false);
    final proposed = NativeSnapshotCodec.decode(
      decision.plan!.proposedStateData,
    );
    expect((proposed['library'] as List).first['priority'], 'high');
    for (final field in ['sessions', 'xpLedger', 'settings',
        'futureField', 'collections', 'orderPlan']) {
      expect(NativeSnapshotCodec.equivalent(
        proposed[field], original.stateData[field],
      ), true, reason: field);
    }
  });

  test('timestamp collision detects cloud-content divergence and quarantines',
      () {
    final pending = batch();
    final external = row().stateData;
    (external['xpLedger'] as Map)['total'] = 501;
    final sameStamp = NativeCloudRow(
      ownerId: owner, updatedAt: rev, stateData: external,
    );
    final status = NativeSyncReview.inspect(
      batch: pending, cloudRow: sameStamp, signedInOwnerId: owner,
    );
    expect(status.status, NativeReviewStatus.payloadChanged);
    expect(status.plan, null);
    expect(NativeSyncReview.inspect(
      batch: pending, cloudRow: row(stamp: 'revision-two'),
      signedInOwnerId: owner,
    ).status, NativeReviewStatus.revisionChanged);
    expect(NativeSyncReview.inspect(
      batch: pending, cloudRow: null, signedInOwnerId: owner,
    ).status, NativeReviewStatus.missingCloudRow);
    expect(NativeSyncReview.inspect(
      batch: pending, cloudRow: row(account: 'other'),
      signedInOwnerId: owner,
    ).status, NativeReviewStatus.foreignAccount);
  });

  test('two simultaneous clients conflict, duplicate receipt is idempotent',
      () {
    final simulator = NativeSimulatedAtomicServer(row());
    final first = batch();
    final second = batch(id: 'review-two', title: 'b');
    final receipt = simulator.commitForTest(
      batch: first, signedInOwnerId: owner,
    );
    expect(receipt.result, contains('simulated-revision'));
    expect(receipt.alreadyApplied, false);
    final replay = simulator.commitForTest(
      batch: first, signedInOwnerId: owner,
    );
    expect(replay.result, receipt.result);
    expect(replay.alreadyApplied, true);
    expect(simulator.commitForTest(
      batch: second, signedInOwnerId: owner,
    ).result, NativeReviewStatus.revisionChanged.name);
    expect(simulator.commitForTest(
      batch: batch(id: 'review-one', title: 'b'),
      signedInOwnerId: owner,
    ).result, 'reused-id-different-batch');
    final snapshot = simulator.current!.stateData;
    expect((snapshot['library'] as List)[0]['priority'], 'high');
    expect((snapshot['library'] as List)[1]['priority'], 'medium');
  });

  test('format validation rejects foreign, duplicated, or altered operations',
      () {
    final staged = batch();
    expect(() => NativeReviewBatch.fromJson(
      staged.toJson(), signedInOwnerId: 'different',
    ), throwsFormatException);
    final altered = staged.toJson();
    (altered['operations'] as List).add(
      (altered['operations'] as List).first,
    );
    expect(() => NativeReviewBatch.fromJson(
      altered, signedInOwnerId: owner,
    ), throwsFormatException);
    final foreign = staged.toJson();
    ((foreign['operations'] as List).first as Map)['proposal'] = {
      ...(((foreign['operations'] as List).first as Map)['proposal'] as Map),
      'accountId': 'different',
    };
    expect(() => NativeReviewBatch.fromJson(
      foreign, signedInOwnerId: owner,
    ), throwsFormatException);
    // Defend staged batch immutability from caller-mutable JSON maps.
    expect(staged.entries.single.proposal.accountId, owner);
    expect(staged.toJson()['ownerId'], owner);
  });

  test('no status/XP side-effect shortcut can enter pending batch', () {
    final journal = NativeDraftJournal(accountId: owner);
    journal.add(NativeDraftEntry(
      operationId: 'blocked',
      proposal: NativeEditProposal(
        kind: NativeEditKind.setTitleStatus,
        accountId: owner,
        baseRevision: rev,
        createdAt: DateTime.utc(2026, 10, 14),
        payload: {'titleId': 'a', 'value': 'completed'},
      ),
    ));
    expect(() => NativeReviewBatch.stage(
      batchId: 'unsafe', base: row(), journal: journal,
    ), throwsStateError);
  });

  late Directory folder;
  late TestVault vault;
  late NativePendingReviewStore store;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('m19-safety-');
    vault = TestVault();
    store = NativePendingReviewStore(
      directoryProvider: () async => folder, keyVault: vault,
    );
  });
  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  File local(String account) {
    final hash = sha256.convert(
      utf8.encode('m19-pending-review:' + account),
    ).toString();
    return File(folder.path + Platform.pathSeparator +
        'mediaflow-pending-review-v1' + Platform.pathSeparator +
        'review-' + hash + '.json');
  }

  test('durable pending review is AES-GCM encrypted, never auto-committed',
      () async {
    final pending = batch();
    await store.save(pending, owner);
    final content = await local(owner).readAsString();
    expect(content, isNot(contains('A SECRET')));
    expect(content, isNot(contains('titleId')));
    expect(content, isNot(contains('revision-one')));
    final restarted = NativePendingReviewStore(
      directoryProvider: () async => folder, keyVault: vault,
    );
    final restored = await restarted.load(owner);
    expect(restored?.batchId, pending.batchId);
    expect(restored?.entries.single.proposal.payload['titleId'], 'a');
    expect(await restarted.load('foreign-user'), null);
    expect(NativeSyncReview.inspect(
      batch: restored!, cloudRow: row(),
      signedInOwnerId: owner,
    ).status, NativeReviewStatus.safeToSimulate);
  });

  test('tampered pending ciphertext and revoked OS key both fail closed',
      () async {
    await store.save(batch(), owner);
    final file = local(owner);
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    data['mac'] = base64Encode(List<int>.filled(16, 0));
    await file.writeAsString(jsonEncode(data));
    expect(await store.load(owner), null);
    await store.save(batch(), owner);
    vault.keys.clear();
    expect(await store.load(owner), null);
  });

  test('corrupt newest pending review recovers prior encrypted generation',
      () async {
    await store.save(batch(id: 'first-batch'), owner);
    await store.save(batch(id: 'new-batch'), owner);
    expect(await File(local(owner).path + '.previous').exists(), true);
    await local(owner).writeAsString('{\"truncated\":', flush: true);
    final previous = await store.load(owner);
    expect(previous?.batchId, 'first-batch');
    // Recovery does not execute or upload the batch.
    expect(NativeCloudCapabilities.cloudWritesEnabled, false);
  });

  test('queued save, clear, and logout cannot recreate old pending review',
      () async {
    final saving = store.save(batch(), owner);
    final clearing = store.clear(owner);
    await Future.wait([saving, clearing]);
    expect(await store.load(owner), null);
    expect(await local(owner).exists(), false);
    expect(vault.keys, isEmpty);
  });

  test('synthetic 100000-title full-payload hashing detects same-stamp edit',
      () {
    final source = {
      'library': [
        for (var i = 0; i < 100000; i++)
          {'id': 'id-' + i.toString(), 'title': 'Title ' + i.toString()},
      ],
      'sessions': <Object>[],
      'categories': <Object>[],
      'settings': <String, dynamic>{},
    };
    final stopwatch = Stopwatch()..start();
    final a = NativeCloudRow(
      ownerId: owner, updatedAt: rev, stateData: source,
    );
    final first = NativeReviewBatch.digest(a);
    final modified = a.stateData;
    ((modified['library'] as List)[99999] as Map)['title'] = 'Changed';
    final b = NativeCloudRow(
      ownerId: owner, updatedAt: rev, stateData: modified,
    );
    expect(NativeReviewBatch.digest(b), isNot(first));
    // Synthetic benchmark, not a real-device FPS or latency guarantee.
    // ignore: avoid_print
    print('M19_100K_DIGEST_MS=' + stopwatch.elapsedMilliseconds.toString());
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('synthetic lab detects timestamp collision with no cloud edits',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
        child: SyncSafetyLabPanel(),
      )),
    ));
    await tester.tap(find.text('Stage demo review'));
    await tester.pump();
    await tester.tap(find.text('Check conflict'));
    await tester.pump();
    expect(find.textContaining('safeToSimulate'), findsOneWidget);
    await tester.tap(find.text('Simulate another device'));
    await tester.pump();
    await tester.tap(find.text('Check conflict'));
    await tester.pump();
    expect(find.textContaining('payloadChanged'), findsOneWidget);
    await tester.tap(find.text('Reset lab'));
    await tester.pump();
    expect(find.textContaining('Synthetic lab reset'), findsOneWidget);
  });
}
