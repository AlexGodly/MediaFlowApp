import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_editing_workspace.dart';
import 'package:mediaflow_app/services/native_priority_review_coordinator.dart';
import 'package:mediaflow_app/services/native_snapshot_codec.dart';
import 'package:mediaflow_app/services/native_sync_review.dart';

void main() {
  Map<String,dynamic> fixture() => jsonDecode(
    File('test/fixtures/m28_v410_lossless_sample.json').readAsStringSync(),
  ) as Map<String,dynamic>;
  const owner = 'account-a', revision = '2026-10-14T18:00:12.123456Z';
  late NativeCloudRow row;
  late MediaFlowCatalog catalog;
  late NativeEditingWorkspace workspace;
  late NativePriorityCloudAnchor anchor;
  late NativePriorityReviewCoordinator workflow;
  NativeReviewBatch? pending;
  bool ownerCurrent = true, online = true;
  int reads = 0, saves = 0, deletes = 0;

  void priority({String status='active', String value='medium',
      double progress=6, double? rating=8.5}) {
    workspace.stageTitle(catalog: catalog, titleId:'v410-1',
      priority:value, status:status, progress:progress, rating:rating);
  }

  setUp(() {
    row = NativeCloudRow(
      ownerId:owner, updatedAt:revision, stateData:fixture());
    catalog = decodeMediaFlowState(row.stateData);
    workspace = NativeEditingWorkspace(ownerId:owner)..observe(catalog);
    anchor = NativePriorityCloudAnchor(
      ownerId:owner, revision:revision,
      fullPayloadDigest:NativeReviewBatch.digest(row));
    pending=null; ownerCurrent=true; online=true;
    reads=0; saves=0; deletes=0;
    workflow=NativePriorityReviewCoordinator(
      ownerId:owner, isOwnerCurrent:()=>ownerCurrent,
      fetchFreshCloudRow:() async {
        reads++;
        if(!online) throw const SocketException('offline');
        return row;
      },
      loadEncryptedReview:(id) async {
        expect(id,owner);
        return pending;
      },
      saveEncryptedReview:(batch,id) async {
        expect(id,owner);
        saves++;
        pending=batch;
      },
      clearEncryptedReview:(id) async {
        expect(id,owner);
        deletes++;
        pending=null;
      },
    );
  });
  tearDown(() => workspace.dispose());

  test('priority-only draft stages encrypted review metadata, never uploads',
      () async {
    priority();
    final before=row.stateData;
    final batch=await workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true);
    expect(batch.entries.length,1);
    expect(batch.entries.single.proposal.payload,
      {'titleId':'v410-1','value':'medium'});
    expect(batch.baseRevision,revision);
    expect(batch.baseDigest,NativeReviewBatch.digest(row));
    expect(batch.toJson().containsKey('state_data'),isFalse);
    expect(jsonEncode(batch.toJson()),isNot(contains('futureLedgerConfig')));
    expect(saves,1);
    expect(reads,1);
    expect(NativeSnapshotCodec.equivalent(row.stateData,before),isTrue);
    expect(NativeCloudCapabilities.cloudWritesEnabled,isFalse);
    expect((await workflow.pendingReview())?.batchId,batch.batchId);
    final verdict=await workflow.inspectPending();
    expect(verdict.status,NativeReviewStatus.safeToSimulate);
    expect(verdict.mayUpload,isFalse);
    expect(verdict.plan,isNotNull);
    expect(NativeSnapshotCodec.decode(verdict.plan!.proposedStateData)
      ['settings'],before['settings']);
    expect(NativeSnapshotCodec.decode(verdict.plan!.proposedStateData)
      ['xpLedger'],before['xpLedger']);
    expect(NativeSnapshotCodec.decode(verdict.plan!.proposedStateData)
      ['sessions'],before['sessions']);
    expect(NativeSnapshotCodec.decode(verdict.plan!.proposedStateData)
      ['v410UnknownRoot'],before['v410UnknownRoot']);
  });

  test('only present authenticated cloud snapshot may stage drafts',() async {
    priority();
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:false),
      throwsStateError);
    expect(saves,0);
    expect(reads,0);
  });

  test('same timestamp but changed XP ledger blocks stage, no rebase',() async {
    priority();
    final changed=row.stateData;
    (changed['xpLedger'] as Map)['future']=91;
    row=NativeCloudRow(ownerId:owner,updatedAt:revision,stateData:changed);
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsStateError);
    expect(saves,0);
    expect(reads,1);
  });

  test('unsupported status, progress, rating, standard log and itemized all block',
      () async {
    priority(status:'completed');
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsStateError);
    workspace.discardAll();
    workspace.observe(catalog);
    priority(progress:7);
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsStateError);
    workspace.discardAll();
    workspace.observe(catalog);
    priority(rating:9);
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsStateError);
    workspace.discardAll();
    workspace.observe(catalog);
    workspace.stageLog(catalog:catalog,titleId:'v410-1',
      amount:1,minutes:24,note:'Synthetic');
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsStateError);
    expect(saves,0);
  });

  test('offline, account switch and stale workspace refuse staging', () async {
    priority();
    online=false;
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsA(isA<SocketException>()));
    ownerCurrent=false;
    await expectLater(workflow.pendingReview(),throwsStateError);
    ownerCurrent=true;
    workspace.observe(decodeMediaFlowState(row.stateData));
    expect(workspace.stale,isTrue);
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsStateError);
  });

  test('no silent replacement of another encrypted pending review',() async {
    priority();
    await workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true);
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsStateError);
    expect(saves,1);
    await workflow.discardPending();
    expect(deletes,1);
    expect(await workflow.pendingReview(),isNull);
    expect(workspace.titleDrafts.length,1);
    expect((row.stateData['library'] as List).first['priority'],'high');
  });

  test('manual fresh check quarantines changed payload at same timestamp',() async {
    priority();
    await workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true);
    final changed=row.stateData;
    (changed['sessions'] as List).add({'id':'new-website-history'});
    row=NativeCloudRow(ownerId:owner,updatedAt:revision,stateData:changed);
    final verdict=await workflow.inspectPending();
    expect(verdict.status,NativeReviewStatus.payloadChanged);
    expect(verdict.mayUpload,isFalse);
    expect(verdict.plan,isNull);
    expect(pending,isNotNull);
    expect(saves,1);
  });

  test('changed revision, missing cloud, foreign owner all block inspection',
      () async {
    priority();
    await workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true);
    row=NativeCloudRow(ownerId:owner,updatedAt:'new-version',
      stateData:row.stateData);
    expect((await workflow.inspectPending()).status,
      NativeReviewStatus.revisionChanged);
    online=false;
    expect((await workflow.inspectPending()).status,
      NativeReviewStatus.missingCloudRow);
    online=true;
    row=NativeCloudRow(ownerId:'foreign',updatedAt:revision,
      stateData:row.stateData);
    expect((await workflow.inspectPending()).status,
      NativeReviewStatus.foreignAccount);
    expect(NativeCloudCapabilities.cloudWritesEnabled,isFalse);
  });

  test('simultaneous actions do not overwrite pending review',() async {
    priority();
    final first=workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true);
    await expectLater(workflow.stage(workspace:workspace,
      catalog:catalog, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsStateError);
    await first;
    expect(saves,1);
  });

  test('observed catalog cannot be substituted for different account state',
      () async {
    priority();
    final other=decodeMediaFlowState(row.stateData);
    await expectLater(workflow.stage(workspace:workspace,
      catalog:other, anchor:anchor, isDisplayedAuthoritativeCloud:true),
      throwsStateError);
    expect(reads,0);
  });
}
