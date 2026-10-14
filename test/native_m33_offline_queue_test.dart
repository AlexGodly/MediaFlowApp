import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_editing_workspace.dart';
import 'package:mediaflow_app/services/native_m33_draft_coordinator.dart';
import 'package:mediaflow_app/services/native_m33_offline_queue.dart';
import 'package:mediaflow_app/services/native_offline_read_coordinator.dart';
import 'package:mediaflow_app/services/native_priority_review_coordinator.dart';
import 'package:mediaflow_app/services/native_snapshot_codec.dart';

void main() {
  const owner = 'owner-test';
  final date = DateTime.utc(2026,10,14,18,10);
  NativeM33PriorityDraft draft({
    String id = 'op_1',
    String title = 'anime-a',
    String before = 'high',
    String after = 'medium',
  }) => NativeM33PriorityDraft(
    operationId:id, titleId:title, beforePriority:before,
    afterPriority:after, createdAt:date);

  NativeM33OfflineDraftQueue queue({
    String account = owner,
    String source = 'offline',
    String? fullDigest,
    String? updatedAt,
    List<NativeM33PriorityDraft>? entries,
  }) => NativeM33OfflineDraftQueue(
    ownerId:account, queueId:'queue_one', source:source, createdAt:date,
    fullCloudDigest:fullDigest, cloudUpdatedAt:updatedAt,
    entries:entries ?? [draft()],
  );

  Map<String,dynamic> state() => {
    'library':[
      {'id':'anime-a', 'title':'A', 'priority':'high', 'status':'active',
       'progress':2, 'total':12, 'rating':8},
      {'id':'anime-b', 'title':'B', 'priority':'low', 'status':'active',
       'progress':0, 'total':12, 'rating':7},
    ],
    'sessions':[{'id':'history-record','xp':75}],
    'settings':{'futureSetting':{'custom':true}},
    'categories':[{'id':'anime','name':'Anime'}],
    'xpLedger':{'pending':{'unknown':99}},
    'futureRoot':{'opaque':['hello']},
  };

  NativeCloudRow row({String account=owner, String timestamp='web-time',
    Map<String,dynamic>? payload}) => NativeCloudRow(
    ownerId:account,updatedAt:timestamp,stateData:payload??state());

  test('strict offline data format and owner binding reject unsafe operations',(){
    final original=queue();
    final clone=NativeM33OfflineDraftQueue.fromJson(
      Map<String,dynamic>.from(jsonDecode(jsonEncode(original.toJson())) as Map),
      signedInOwnerId:owner);
    expect(clone.entries.single.afterPriority,'medium');
    expect(clone.source,'offline');
    expect(()=>NativeM33OfflineDraftQueue.fromJson(
      Map<String,dynamic>.from(original.toJson()),
      signedInOwnerId:'foreign'),throwsFormatException);
    expect(()=>draft(before:'high',after:'high'),throwsFormatException);
    expect(()=>draft(after:'completed'),throwsFormatException);
    expect(()=>draft(id:'../../evil'),throwsFormatException);
    expect(()=>queue(source:'untrusted'),throwsFormatException);
    expect(()=>queue(source:'offline',fullDigest:'a'*64,updatedAt:'v1'),
      throwsFormatException);
    expect(()=>queue(entries:[draft(),draft(id:'op_2')]),
      throwsFormatException);
    expect(()=>queue(entries:[]),throwsFormatException);
  });

  test('manual unanchored offline check compares priorities without enabling saves',(){
    final original=row();
    final decision=NativeM33ManualReview.inspect(queue:queue(),
      current:original,signedInOwnerId:owner);
    expect(decision.status,NativeM33CheckStatus.needsManualCloudReview);
    expect(decision.matchedCount,1);
    expect(decision.mayUpload,isFalse);
    expect(original.stateData['sessions'],state()['sessions']);
    expect(NativeCloudCapabilities.cloudWritesEnabled,false);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled,false);
  });

  test('matching target cannot be claimed as an applied offline change',(){
    final changed=state();
    (changed['library'] as List).first['priority']='medium';
    final review=NativeM33ManualReview.inspect(queue:queue(),
      current:row(payload:changed),signedInOwnerId:owner);
    expect(review.status,NativeM33CheckStatus.alreadyMatchesTarget);
    expect(review.message,contains('does NOT prove'));
    expect(review.mayUpload,false);
  });

  test('same timestamp with changed root causes anchored full-payload conflict',(){
    final original=row();
    final digest=sha256.convert(
      utf8.encode(NativeSnapshotCodec.canonicalJson(original.stateData)),
    ).toString();
    final anchored=queue(source:'cloud',fullDigest:digest,updatedAt:'web-time');
    final changed=state();
    (changed['xpLedger'] as Map)['pending']={'unknown':100};
    final report=NativeM33ManualReview.inspect(queue:anchored,
      current:row(payload:changed),signedInOwnerId:owner);
    expect(report.status,NativeM33CheckStatus.unrelatedCloudChanges);
    expect(report.mayUpload,false);
    final okay=NativeM33ManualReview.inspect(queue:anchored,
      current:original,signedInOwnerId:owner);
    expect(okay.status,NativeM33CheckStatus.needsManualCloudReview);
    final newTimestamp=NativeM33ManualReview.inspect(queue:anchored,
      current:row(timestamp:'new-time'),signedInOwnerId:owner);
    expect(newTimestamp.status,NativeM33CheckStatus.unrelatedCloudChanges);
  });

  test('unknown/duplicate title and unrelated priority conflict are blocked',(){
    final missing=state();
    (missing['library'] as List).clear();
    expect(NativeM33ManualReview.inspect(queue:queue(),
      current:row(payload:missing),signedInOwnerId:owner).status,
      NativeM33CheckStatus.missingOrDuplicateTitle);
    final duplicate=state();
    (duplicate['library'] as List).add(
      jsonDecode(jsonEncode((duplicate['library'] as List).first)));
    expect(NativeM33ManualReview.inspect(queue:queue(),
      current:row(payload:duplicate),signedInOwnerId:owner).status,
      NativeM33CheckStatus.missingOrDuplicateTitle);
    final modified=state();
    (modified['library'] as List).first['priority']='low';
    expect(NativeM33ManualReview.inspect(queue:queue(),
      current:row(payload:modified),signedInOwnerId:owner).status,
      NativeM33CheckStatus.titleConflict);
  });

  test('no foreign owner or invalid cloud can be reviewed',(){
    expect(NativeM33ManualReview.inspect(queue:queue(),
      current:row(account:'another'),signedInOwnerId:owner).status,
      NativeM33CheckStatus.foreignAccount);
    expect(NativeM33ManualReview.inspect(queue:queue(),
      current:row(payload:{'library':[]}),signedInOwnerId:owner).status,
      NativeM33CheckStatus.invalidCloud);
  });

  MediaFlowCatalog catalog() => MediaFlowCatalog(
    categories: const [],
    library:[MediaFlowTitle.fromJson({
      'id':'anime-a','title':'A','priority':'high','status':'active',
      'categoryId':'anime','progress':2,'total':12,'rating':8,
    })],
  );

  late NativeEditingWorkspace workspace;
  late MediaFlowCatalog base;
  NativeM33OfflineDraftQueue? saved;
  bool ownerAlive=true,online=true;
  int savedCount=0,readCount=0,removedCount=0;
  late NativeM33DraftCoordinator coordinator;

  setUp((){
    base=catalog();
    workspace=NativeEditingWorkspace(ownerId:owner)..observe(base);
    saved=null; ownerAlive=true; online=true;
    savedCount=0;readCount=0;removedCount=0;
    coordinator=NativeM33DraftCoordinator(
      ownerId:owner,isOwnerCurrent:()=>ownerAlive,
      readStored:(id) async {
        expect(id,owner);
        readCount++;
        return saved;
      },
      writeStored:(id,queue) async {
        expect(id,owner);
        savedCount++;
        saved=queue;
      },
      deleteStored:(id) async {
        expect(id,owner);
        removedCount++;
        saved=null;
      },
      fetchFreshCloudRow:() async {
        if(!online) throw const SocketException('offline');
        return row();
      },
    );
  });
  tearDown(()=>workspace.dispose());

  void stagePriority({String status='active',double progress=2,
      double? rating=8}) => workspace.stageTitle(
    catalog:base,titleId:'anime-a',priority:'medium',status:status,
    progress:progress,rating:rating);

  test('offline local sketch remains encrypted-only with no cloud baseline',
      () async {
    stagePriority();
    final kept=await coordinator.keep(
      workspace:workspace,catalog:base,
      source:NativeSnapshotSource.offline);
    expect(kept.ownerId,owner);
    expect(kept.source,'offline');
    expect(kept.fullCloudDigest,isNull);
    expect(kept.cloudUpdatedAt,isNull);
    expect(kept.entries.single.beforePriority,'high');
    expect(kept.entries.single.afterPriority,'medium');
    expect(savedCount,1);
    expect(workspace.titleCount,1);
    expect((await coordinator.load())?.queueId,kept.queueId);
    expect(readCount, greaterThan(0));
    expect((await coordinator.inspect()).status,
      NativeM33CheckStatus.needsManualCloudReview);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled,false);
  });

  test('cloud intents require exact original cloud anchor',() async {
    stagePriority();
    await expectLater(coordinator.keep(workspace:workspace,catalog:base,
      source:NativeSnapshotSource.cloud),throwsStateError);
    final digest=sha256.convert(
      utf8.encode(NativeSnapshotCodec.canonicalJson(row().stateData)),
    ).toString();
    final anchored=await coordinator.keep(workspace:workspace,catalog:base,
      source:NativeSnapshotSource.cloud,
      liveCloudAnchor:NativePriorityCloudAnchor(
        ownerId:owner,revision:'web-time',fullPayloadDigest:digest));
    expect(anchored.source,'cloud');
    expect(anchored.fullCloudDigest,digest);
    expect((await coordinator.inspect()).status,
      NativeM33CheckStatus.needsManualCloudReview);
  });

  test('status/rating/logging not eligible for offline pending priority',() async {
    stagePriority(status:'completed');
    await expectLater(coordinator.keep(workspace:workspace,catalog:base,
      source:NativeSnapshotSource.offline),throwsStateError);
    workspace.discardAll();workspace.observe(base);
    stagePriority(rating:9);
    await expectLater(coordinator.keep(workspace:workspace,catalog:base,
      source:NativeSnapshotSource.offline),throwsStateError);
    expect(savedCount,0);
  });

  test('reject stale workspace, invalid source, repeated queue and other owners',
      () async {
    stagePriority();
    await expectLater(coordinator.keep(workspace:workspace,catalog:base,
      source:NativeSnapshotSource.invalidCloud),throwsStateError);
    await coordinator.keep(workspace:workspace,catalog:base,
      source:NativeSnapshotSource.recoveredPrevious);
    await expectLater(coordinator.keep(workspace:workspace,catalog:base,
      source:NativeSnapshotSource.recoveredPrevious),throwsStateError);
    expect(savedCount,1);
    await coordinator.discard();
    expect(removedCount,1);
    expect(await coordinator.load(),isNull);
    ownerAlive=false;
    await expectLater(coordinator.load(),throwsStateError);
  });

  test('offline check never retries or removes saved intent automatically',
      () async {
    stagePriority();
    await coordinator.keep(workspace:workspace,catalog:base,
      source:NativeSnapshotSource.offlineMemory);
    online=false;
    final check=await coordinator.inspect();
    expect(check.status,NativeM33CheckStatus.unavailable);
    expect(check.mayUpload,false);
    expect(saved,isNotNull);
    expect(savedCount,1);
    expect(removedCount,0);
  });

  test('owner switch during async manual cloud read cannot show old data',
      () async {
    stagePriority();
    await coordinator.keep(workspace:workspace,catalog:base,
      source:NativeSnapshotSource.offline);
    final switched=NativeM33DraftCoordinator(
      ownerId:owner,isOwnerCurrent:()=>ownerAlive,
      readStored:(id) async => saved,
      writeStored:(id,q) async {},
      deleteStored:(id) async {},
      fetchFreshCloudRow:() async {
        await Future<void>.delayed(const Duration(milliseconds:3));
        ownerAlive=false;
        return row();
      },
    );
    await expectLater(switched.inspect(),throwsStateError);
    expect(saved,isNotNull);
  });
}
