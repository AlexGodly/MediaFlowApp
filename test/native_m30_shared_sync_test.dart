import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_full_state.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m30_shared_sync.dart';
import 'package:mediaflow_app/services/native_snapshot_codec.dart';

void main() {
  Map<String, dynamic> fixture() => jsonDecode(
    File('test/fixtures/m28_v410_lossless_sample.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  NativeM30RevisionedSnapshot snapshot({
    String owner='account-a', int revision=41, Object? wire,
  }) => NativeM30RevisionedSnapshot(
    ownerId: owner, revision: revision, wire: wire ?? fixture(),
    legacyUpdatedAt: '2026-10-14T14:05:32.000000Z',
  );

  NativeM30PriorityIntent edit(NativeM30RevisionedSnapshot base, {
    String id='op-one', String title='v410-1', String priority='medium',
  }) => NativeM30PriorityIntent.forSnapshot(
    base: base, operationId: id, titleId: title, priority: priority,
  );

  test('native production write and shared protocol gates remain OFF', () {
    expect(NativeM30Protocol.deployed, isFalse);
    expect(NativeM30Protocol.cloudWritesEnabled, isFalse);
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    expect(NativeCloudCapabilities.hasServerSideCas, isFalse);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, isFalse);
    expect(const NativeM30SyntheticGate().readyForTestOnly, isFalse);
    final store=NativeM30SimulatedSharedServer();
    final base=snapshot();
    store.seedForTest(base);
    expect(store.commitForTest(signedInOwnerId: base.ownerId,
      intent: edit(base), clientKind: 'website').result,
      NativeM30Result.protocolUnavailable);
    expect(store.readForTest(signedInOwnerId: base.ownerId,
      ownerId: base.ownerId)!.revision, 41);
  });

  test('all migration prerequisites must be checked in synthetic gate', () {
    const required=NativeM30SyntheticGate.testOnlyComplete();
    expect(required.readyForTestOnly, isTrue);
    final missing=NativeM30SyntheticGate(
      websiteUsesSharedProtocol: true,
      legacyDirectWritesBlocked: false,
      ownerRlsAudited: true, durableReceiptsModeled: true,
      backupAndRestoreVerified: true, allWritersCompatible: true,
      sideEffectsVerified: true,
    );
    expect(missing.readyForTestOnly, isFalse);
    expect(NativeM30Protocol.deployed, isFalse);
  });

  test('web then Android: stale native draft conflicts, does not overwrite', () {
    final base=snapshot();
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(base);
    final website=edit(base,id:'web-change',priority:'low');
    final native=edit(base,id:'android-change',priority:'medium');
    final siteResult=store.commitForTest(signedInOwnerId:'account-a',
      intent:website,clientKind:'website');
    expect(siteResult.result,NativeM30Result.applied);
    expect(siteResult.revision,42);
    final conflict=store.commitForTest(signedInOwnerId:'account-a',
      intent:native,clientKind:'android');
    expect(conflict.result,NativeM30Result.conflict);
    final now=store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!;
    expect(now.revision,42);
    expect(MediaFlowFullState.parse(now.wire)
      .at(['library',0,'priority']),'low');
    expect(MediaFlowFullState.parse(now.wire)
      .at(['xpLedger','v348ActionEvents','a1']),12);
  });

  test('Android then website: stale website attempt cannot lose new changes', () {
    final base=snapshot();
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(base);
    final android=edit(base,id:'android-one',title:'v410-2',priority:'high');
    final website=edit(base,id:'website-two',priority:'medium');
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:android,clientKind:'android').result,NativeM30Result.applied);
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:website,clientKind:'website').result,NativeM30Result.conflict);
    final current=store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!;
    expect(MediaFlowFullState.parse(current.wire)
      .at(['library',1,'priority']),'high');
    expect(MediaFlowFullState.parse(current.wire)
      .at(['library',0,'priority']),'high');
  });

  test('retry after lost response is idempotent even after next write', () {
    final base=snapshot();
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(base);
    final intent=edit(base,id:'lost-ack',priority:'medium');
    // Simulate server commit succeeded, but the client never got the ACK.
    final unseen=store.commitForTest(signedInOwnerId:'account-a',
      intent:intent,clientKind:'ios');
    expect(unseen.result,NativeM30Result.applied);
    final newer=store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!;
    final later=edit(newer,id:'next-write',priority:'low');
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:later,clientKind:'website').result,NativeM30Result.applied);
    final retry=store.commitForTest(signedInOwnerId:'account-a',
      intent:intent,clientKind:'ios');
    expect(retry.result,NativeM30Result.replayed);
    expect(retry.revision,unseen.revision);
    expect(retry.digest,unseen.digest);
    expect(store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!.revision,43);
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:edit(base,id:'lost-ack',priority:'low'),
      clientKind:'ios').result,NativeM30Result.reusedOperationId);
  });

  test('same legacy updated_at but different payload is detected by digest', () {
    final base=snapshot();
    final alter=fixture();
    (alter['xpLedger'] as Map)['futureLedger']={'keep':true};
    final changed=snapshot(wire:alter);
    expect(base.legacyUpdatedAt,changed.legacyUpdatedAt);
    expect(base.revision,changed.revision);
    expect(base.wireDigest,isNot(changed.wireDigest));
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(changed);
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:edit(base),clientKind:'website').result,NativeM30Result.conflict);
    expect(store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!.wireDigest,changed.wireDigest);
  });

  test('owner isolation for reads, commits and idempotent receipts', () {
    final one=snapshot(),two=snapshot(owner:'account-b');
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(one);store.seedForTest(two);
    expect(store.readForTest(signedInOwnerId:'account-b',
      ownerId:'account-a'),isNull);
    final req=edit(one);
    expect(store.commitForTest(signedInOwnerId:'account-b',
      intent:req,clientKind:'android').result,NativeM30Result.unauthorized);
    expect(store.commitForTest(signedInOwnerId:'',
      intent:req,clientKind:'android').result,NativeM30Result.unauthorized);
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:req,clientKind:'android').result,NativeM30Result.applied);
    expect(store.commitForTest(signedInOwnerId:'account-b',
      intent:edit(two),clientKind:'android').result,NativeM30Result.applied);
    expect(store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!.revision,42);
    expect(store.readForTest(signedInOwnerId:'account-b',
      ownerId:'account-b')!.revision,42);
  });

  test('legacy website UPSERT is blocked, no fallback or silent rebase', () {
    final base=snapshot();
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(base);
    final uploaded=fixture();
    (uploaded['library'] as List).clear();
    expect(store.legacyUpsertForTest(signedInOwnerId:'account-a',
      ownerId:'account-a',wire:uploaded).result,
      NativeM30Result.legacyWriteBlocked);
    expect(store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!.wireDigest,base.wireDigest);
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:edit(base,id:'unsupported',priority:'completed'),
      clientKind:'android'),throwsA(isA<FormatException>()));
  });

  test('validate payload and never invent missing/duplicated title records', () {
    final base=snapshot();
    expect(()=>edit(base,id:'',priority:'medium'),throwsFormatException);
    expect(()=>edit(base,id:'../../x',priority:'medium'),throwsFormatException);
    expect(()=>edit(base,priority:'completed'),throwsFormatException);
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(base);
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:edit(base,title:'missing'),clientKind:'windows').result,
      NativeM30Result.invalid);
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:edit(base,priority:'high'),clientKind:'windows').result,
      NativeM30Result.noChange);
    expect(store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!.revision,41);
    final duplicate=fixture();
    (duplicate['library'] as List).add(
      jsonDecode(jsonEncode((duplicate['library'] as List).first)));
    final newStore=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    final dup=snapshot(wire:duplicate);
    newStore.seedForTest(dup);
    expect(newStore.commitForTest(signedInOwnerId:'account-a',
      intent:edit(dup),clientKind:'windows').result,NativeM30Result.invalid);
    expect(newStore.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!.revision,41);
  });

  test('gzip envelope, future fields and timestamps survive versioned commit', () {
    final source=fixture();
    final wrapper={
      '__mediaflowCompressed':'gzip',
      'data':base64Encode(gzip.encode(utf8.encode(jsonEncode(source)))),
      'nextEnvelopeField': {'keep':[1,2,3]},
    };
    final base=snapshot(wire:wrapper);
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(base);
    final req=edit(base,priority:'medium');
    expect(store.commitForTest(signedInOwnerId:'account-a',
      intent:req,clientKind:'website').result,NativeM30Result.applied);
    final current=store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!;
    expect((current.wire as Map)['nextEnvelopeField'],{'keep':[1,2,3]});
    final parsed=MediaFlowFullState.parse(current.wire);
    final untouched=MediaFlowFullState.parse(base.wire);
    expect(parsed.at(['settings','unknownFutureSetting']),
      untouched.at(['settings','unknownFutureSetting']));
    expect(parsed.at(['library',0,'seasons']),
      untouched.at(['library',0,'seasons']));
    expect(parsed.at(['sessions']),
      untouched.at(['sessions']));
    expect(parsed.at(['xpLedger']),
      untouched.at(['xpLedger']));
    expect(parsed.at(['activityLog']),
      untouched.at(['activityLog']));
    expect(parsed.at(['orderPlan']),
      untouched.at(['orderPlan']));
    expect(parsed.at(['collections']),
      untouched.at(['collections']));
    expect(parsed.at(['sessions',0,'timestamp']),
      '2026-10-01T12:34:56.123+01:00');
  });

  test('read snapshots are defensive and cannot modify committed state', () {
    final base=snapshot();
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(base);
    final detached=store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!;
    (detached.wire as Map).clear();
    final now=store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!;
    expect(now.wireDigest,base.wireDigest);
    expect(NativeSnapshotCodec.equivalent(now.wire,base.wire),true);
  });

  test('1000 sequential web/native operations have monotonic revision and no loss',
      () {
    final base=snapshot();
    final store=NativeM30SimulatedSharedServer(
      gate: const NativeM30SyntheticGate.testOnlyComplete());
    store.seedForTest(base);
    for (var i=0;i<1000;i++){
      final current=store.readForTest(signedInOwnerId:'account-a',
        ownerId:'account-a')!;
      final intended=i.isEven?'medium':'high';
      final result=store.commitForTest(
        signedInOwnerId:'account-a',
        intent:edit(current,id:'op-$i',priority:intended),
        clientKind:i.isEven?'website':'android');
      expect(result.result,NativeM30Result.applied);
      expect(result.revision,42+i);
    }
    final finalRow=store.readForTest(signedInOwnerId:'account-a',
      ownerId:'account-a')!;
    expect(finalRow.revision,1041);
    final full=MediaFlowFullState.parse(finalRow.wire);
    expect(full.inspect().libraryCount,2);
    expect(full.at(['settings','unknownFutureSetting']),isNotNull);
    expect(full.at(['xpLedger','libraryAdditions','v410-1']),10);
  },timeout:const Timeout(Duration(minutes:2)));
}
