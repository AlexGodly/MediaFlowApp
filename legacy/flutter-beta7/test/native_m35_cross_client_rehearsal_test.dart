import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_full_state.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m30_shared_sync.dart';

void main(){
  Map<String,dynamic> original() => jsonDecode(
    File('test/fixtures/m28_v410_lossless_sample.json').readAsStringSync(),
  ) as Map<String,dynamic>;

  NativeM30RevisionedSnapshot snapshot(String owner) =>
      NativeM30RevisionedSnapshot(
        ownerId:owner,revision:1,wire:original(),
        legacyUpdatedAt:'2026-10-14T12:00:00Z');

  test('staging matrix website/Android/iOS/Windows cannot overwrite stale',
      (){
    final simulation=NativeM30SimulatedSharedServer(
      gate:const NativeM30SyntheticGate.testOnlyComplete());
    const clients=['website','android','ios','windows'];
    final primary=snapshot('owner-a');
    simulation.seedForTest(primary);
    final proposals=[
      for(var i=0;i<clients.length;i++)
        NativeM30PriorityIntent.forSnapshot(
          base:primary,operationId:'same-version-$i',
          titleId:'v410-1',
          priority:i.isEven?'medium':'low'),
    ];
    expect(simulation.commitForTest(signedInOwnerId:'owner-a',
      intent:proposals[0],clientKind:clients[0]).result,
      NativeM30Result.applied);
    for(var i=1;i<clients.length;i++){
      expect(simulation.commitForTest(signedInOwnerId:'owner-a',
        intent:proposals[i],clientKind:clients[i]).result,
        NativeM30Result.conflict);
    }
    final current=simulation.readForTest(
      signedInOwnerId:'owner-a',ownerId:'owner-a')!;
    expect(current.revision,2);
    expect(MediaFlowFullState.parse(current.wire)
      .at(['library',0,'priority']),'medium');
    expect(MediaFlowFullState.parse(current.wire)
      .at(['xpLedger','v348ActionEvents','a1']),12);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
  });

  test('owner switch fails auth and old website unconditional write fails',(){
    final simulation=NativeM30SimulatedSharedServer(
      gate:const NativeM30SyntheticGate.testOnlyComplete());
    final a=snapshot('owner-a'), b=snapshot('owner-b');
    simulation.seedForTest(a);
    simulation.seedForTest(b);
    final intent=NativeM30PriorityIntent.forSnapshot(
      base:a,operationId:'owner-switch',titleId:'v410-1',
      priority:'medium');
    expect(simulation.commitForTest(signedInOwnerId:'owner-b',
      intent:intent,clientKind:'ios').result,NativeM30Result.unauthorized);
    expect(simulation.legacyUpsertForTest(
      signedInOwnerId:'owner-a',ownerId:'owner-a',
      wire:original()).result,NativeM30Result.legacyWriteBlocked);
    expect(simulation.readForTest(signedInOwnerId:'owner-b',
      ownerId:'owner-a'),isNull);
    expect(simulation.readForTest(signedInOwnerId:'owner-a',
      ownerId:'owner-a')!.wireDigest,a.wireDigest);
  });
}
