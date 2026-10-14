import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_m33_draft_coordinator.dart';
import 'package:mediaflow_app/services/native_m33_offline_queue.dart';
import 'package:mediaflow_app/services/native_m34_conflict_review.dart';

void main() {
  const owner='m34-owner';
  final created=DateTime.utc(2026,10,14,19);
  NativeM33PriorityDraft edit(String id, String title,
      String before, String after) => NativeM33PriorityDraft(
    operationId:id,titleId:title,beforePriority:before,
    afterPriority:after,createdAt:created);
  NativeM33OfflineDraftQueue queue({
    List<NativeM33PriorityDraft>? entries,
    String source='offline',String? digest,String? stamp,
  }) => NativeM33OfflineDraftQueue(
    ownerId:owner,queueId:'m34_original',createdAt:created,source:source,
    fullCloudDigest:digest,cloudUpdatedAt:stamp,
    entries:entries ?? [
      edit('e1','t1','high','medium'),
      edit('e2','t2','low','high'),
      edit('e3','t3','high','low'),
      edit('e4','t4','low','medium'),
      edit('e5','t5','high','medium'),
      edit('e6','t6','low','medium'),
    ]);
  Map<String,dynamic> cloud() => {
    'library': [
      {'id':'t1','title':'Title One','priority':'high'},
      {'id':'t2','title':'Title Two','priority':'high'},
      {'id':'t3','title':'Title Three','priority':'medium'},
      {'id':'t5','title':'Duplicate A','priority':'high'},
      {'id':'t5','title':'Duplicate B','priority':'high'},
      {'id':'t6','title':'Invalid Priority','priority':'urgent'},
    ],
    'categories': <Object>[],
    'sessions': [{'id':'history-1','xp':120}],
    'settings': {'theme':'dark','unrecognized':{'preserve':true}},
    'xpLedger': {'total':899},
    'futureRoot':{'preserve':true},
  };
  NativeCloudRow row({String user=owner,String stamp='2026-10-14T12:00:00Z',
    Map<String,dynamic>? data}) => NativeCloudRow(
    ownerId:user,updatedAt:stamp,stateData:data??cloud());

  test('all six priority conflict categories show before/draft/cloud separately',
      () {
    final report=NativeM34ReviewEngine.inspect(
      queue:queue(),current:row(),signedInOwnerId:owner);
    expect(report.items.length,6);
    expect(report.items.map((e)=>e.status).toList(),[
      NativeM34ItemStatus.unchanged,
      NativeM34ItemStatus.alreadyDesired,
      NativeM34ItemStatus.changedElsewhere,
      NativeM34ItemStatus.missing,
      NativeM34ItemStatus.duplicated,
      NativeM34ItemStatus.invalidCloudPriority,
    ]);
    expect(report.conflicts,4);
    expect(report.items[0].title,'Title One');
    expect(report.items[0].beforePriority,'high');
    expect(report.items[0].desiredPriority,'medium');
    expect(report.items[0].cloudPriority,'high');
    expect(report.items[2].cloudPriority,'medium');
    expect(report.items[3].cloudPriority,isNull);
    expect(report.items[3].mayRecreate,false);
    expect(report.items[1].mayRecreate,false);
    expect(report.items[2].mayRecreate,true);
    expect(report.mayUpload,false);
    expect(cloud()['settings'],{'theme':'dark','unrecognized':{'preserve':true}});
  });

  test('changed full-state digest at same timestamp is flagged without mutation',
      () {
    final original=row();
    final anchored=queue(source:'cloud',
      digest:NativeM34ReviewEngine.cloudDigest(original),
      stamp:original.updatedAt);
    final same=NativeM34ReviewEngine.inspect(
      queue:anchored,current:original,signedInOwnerId:owner);
    expect(same.anchorChanged,false);
    final shifted=cloud();
    (shifted['xpLedger'] as Map)['total']=901;
    final changed=NativeM34ReviewEngine.inspect(
      queue:anchored,current:row(data:shifted),signedInOwnerId:owner);
    expect(changed.anchorChanged,true);
    expect(changed.conflicts,4);
    expect(changed.mayUpload,false);
    final newer=NativeM34ReviewEngine.inspect(
      queue:anchored,current:row(stamp:'new'),
      signedInOwnerId:owner);
    expect(newer.anchorChanged,true);
  });

  test('offline unavailable report exposes no fictitious cloud state',() {
    final old=queue(entries:[edit('e1','t1','high','medium')]);
    final report=NativeM34ReviewEngine.unavailable(
      queue:old,signedInOwnerId:owner);
    expect(report.hasFreshCloud,false);
    expect(report.items.single.status,NativeM34ItemStatus.unknownOffline);
    expect(report.items.single.cloudPriority,isNull);
    expect(report.mayUpload,false);
  });

  test('foreign owner and malformed cloud fail closed',() {
    expect(()=>NativeM34ReviewEngine.inspect(
      queue:queue(),current:row(user:'another'),signedInOwnerId:owner),
      throwsStateError);
    expect(()=>NativeM34ReviewEngine.inspect(
      queue:queue(),current:row(data:{'library':[]}),signedInOwnerId:owner),
      throwsFormatException);
  });

  late NativeM33OfflineDraftQueue? stored;
  late NativeCloudRow fresh;
  late NativeM33DraftCoordinator coordinator;
  bool alive=true,online=true;
  int writes=0,clears=0,cloudReads=0;
  List<NativeM33OfflineDraftQueue> savedHistory=[];

  void connect() {
    coordinator=NativeM33DraftCoordinator(
      ownerId:owner,isOwnerCurrent:()=>alive,
      readStored:(ownerId) async {
        expect(ownerId,owner);
        return stored;
      },
      writeStored:(ownerId,newValue) async {
        expect(ownerId,owner);
        stored=newValue;
        writes++;
      },
      replaceStored:(ownerId,next,previousId) async {
        expect(ownerId,owner);
        if(stored?.queueId!=previousId) {
          throw StateError('Changed queue');
        }
        savedHistory.add(stored!);
        stored=next;
        writes++;
      },
      deleteStored:(ownerId) async {
        expect(ownerId,owner);
        stored=null;
        clears++;
      },
      fetchFreshCloudRow:() async {
        cloudReads++;
        if(!online)throw const SocketException('offline');
        return fresh;
      },
    );
  }

  setUp((){
    stored=queue(entries:[
      edit('e1','t1','high','medium'),
      edit('e3','t3','high','low'),
      edit('e4','t4','low','medium'),
    ]);
    fresh=row();alive=true;online=true;
    writes=0;clears=0;cloudReads=0;savedHistory=[];
    connect();
  });

  test('recreate changed title uses new current priority and new ID, not upload',
      () async {
    final report=await coordinator.inspectDetailed();
    expect(report?.items[1].status,NativeM34ItemStatus.changedElsewhere);
    final changed=await coordinator.resolveDetailed(
      reviewed:report!,
      discardOperationIds:{'e4'},recreateOperationIds:{'e3'});
    expect(changed,isNotNull);
    expect(changed!.entries.length,2);
    expect(changed.source,'mixedManual');
    expect(changed.fullCloudDigest,isNull);
    final reproduced=changed.entries.singleWhere((e)=>e.titleId=='t3');
    expect(reproduced.operationId,isNot('e3'));
    expect(reproduced.beforePriority,'medium');
    expect(reproduced.afterPriority,'low');
    expect(changed.entries.first.operationId,'e1');
    expect(writes,1);
    expect(clears,0);
    expect((fresh.stateData['library'] as List)[2]['priority'],'medium');
    expect(report.mayUpload,false);
  });

  test('recreate all remaining intents is anchored to current full cloud',() async {
    stored=queue(entries:[edit('e3','t3','high','low')]);
    final report=(await coordinator.inspectDetailed())!;
    final next=(await coordinator.resolveDetailed(
      reviewed:report,discardOperationIds:{},
      recreateOperationIds:{'e3'}))!;
    expect(next.source,'cloud');
    expect(next.cloudUpdatedAt,fresh.updatedAt);
    expect(next.fullCloudDigest,NativeM34ReviewEngine.cloudDigest(fresh));
    expect(next.entries.single.beforePriority,'medium');
    expect(next.entries.single.operationId,isNot('e3'));
  });

  test('discard individual intents works offline without touching cloud',() async {
    online=false;
    final review=(await coordinator.inspectDetailed())!;
    expect(review.hasFreshCloud,false);
    final next=(await coordinator.resolveDetailed(
      reviewed:review,discardOperationIds:{'e4'},
      recreateOperationIds:{}))!;
    expect(next.entries.map((e)=>e.operationId),['e1','e3']);
    expect(cloudReads,1);
    expect(writes,1);
    expect(clears,0);
    expect(next.fullCloudDigest,isNull);
    expect((fresh.stateData['sessions'] as List).length,1);
  });

  test('discard all queued operations securely removes local copy',() async {
    final report=(await coordinator.inspectDetailed())!;
    final result=await coordinator.resolveDetailed(
      reviewed:report,
      discardOperationIds:{'e1','e3','e4'},
      recreateOperationIds:{});
    expect(result,isNull);
    expect(stored,isNull);
    expect(clears,1);
    expect(writes,0);
  });

  test('cloud shifts after review: recreation refused, drafts preserved',() async {
    final report=(await coordinator.inspectDetailed())!;
    final changed=cloud();
    (changed['settings'] as Map)['otherDeviceWrite']=true;
    fresh=row(data:changed); // SAME timestamp, DIFFERENT full wire data
    await expectLater(coordinator.resolveDetailed(
      reviewed:report,discardOperationIds:{},
      recreateOperationIds:{'e3'}),throwsStateError);
    expect(stored?.entries.length,3);
    expect(writes,0);
    expect(report.mayUpload,false);
  });

  test('queue mutation after review is quarantined even for discard',() async {
    final report=(await coordinator.inspectDetailed())!;
    stored=queue(entries:[edit('different','t3','high','low')]);
    await expectLater(coordinator.resolveDetailed(
      reviewed:report,discardOperationIds:{'e3'},
      recreateOperationIds:{}),throwsStateError);
    expect(writes,0);
  });

  test('missing/duplicate/already-desired titles cannot be recreated',() async {
    stored=queue(entries:[
      edit('e2','t2','low','high'),
      edit('e4','t4','low','medium'),
    ]);
    final report=(await coordinator.inspectDetailed())!;
    expect(report.items[0].status,NativeM34ItemStatus.alreadyDesired);
    expect(report.items[1].status,NativeM34ItemStatus.missing);
    await expectLater(coordinator.resolveDetailed(
      reviewed:report,discardOperationIds:{},
      recreateOperationIds:{'e2'}),throwsStateError);
    await expectLater(coordinator.resolveDetailed(
      reviewed:report,discardOperationIds:{},
      recreateOperationIds:{'e4'}),throwsStateError);
    expect(writes,0);
  });

  test('selections cannot overlap or point at unknown operation IDs',() async {
    final report=(await coordinator.inspectDetailed())!;
    await expectLater(coordinator.resolveDetailed(
      reviewed:report,discardOperationIds:{'e3'},
      recreateOperationIds:{'e3'}),throwsStateError);
    await expectLater(coordinator.resolveDetailed(
      reviewed:report,discardOperationIds:{'nonexistent'},
      recreateOperationIds:{}),throwsStateError);
    await expectLater(coordinator.resolveDetailed(
      reviewed:report,discardOperationIds:{},
      recreateOperationIds:{}),throwsStateError);
    expect(writes,0);
  });

  test('account switched during fresh check: no copied draft changed',() async {
    final report=(await coordinator.inspectDetailed())!;
    final different=NativeM33DraftCoordinator(
      ownerId:owner,isOwnerCurrent:()=>alive,
      readStored:(id) async => stored,
      writeStored:(id,q) async {},
      deleteStored:(id) async {},
      replaceStored:(id,next,old) async {throw StateError('must never run');},
      fetchFreshCloudRow:() async {
        alive=false;
        return fresh;
      },
    );
    await expectLater(different.resolveDetailed(
      reviewed:report,discardOperationIds:{},
      recreateOperationIds:{'e3'}),throwsStateError);
    expect(stored?.entries.length,3);
  });

  test('two clients editing the same priority never auto-win or replay',() {
    final first=row();
    final later=cloud();
    (later['library'] as List)[2]['priority']='low';
    final intents=queue(entries:[edit('e3','t3','high','low')]);
    final report=NativeM34ReviewEngine.inspect(
      queue:intents,current:row(data:later),signedInOwnerId:owner);
    expect(report.items.single.status,NativeM34ItemStatus.alreadyDesired);
    expect(report.mayUpload,false);
    expect((first.stateData['xpLedger'] as Map)['total'],899);
    expect((later['xpLedger'] as Map)['total'],899);
    expect(writes,0);
  });
}
