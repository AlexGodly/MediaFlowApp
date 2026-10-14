// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/services/native_m33_draft_store.dart';
import 'package:mediaflow_app/services/native_m33_offline_queue.dart';
import 'package:mediaflow_app/services/native_offline_key_vault.dart';

class M33MemoryVault implements NativeOfflineKeyVault {
  final Map<String,Uint8List> keys={};
  bool locked=false;
  @override
  Future<Uint8List?> read(String hash) async {
    if (locked) throw StateError('Secure vault locked');
    final bytes=keys[hash];
    return bytes==null?null:Uint8List.fromList(bytes);
  }
  @override
  Future<void> write(String hash,Uint8List value) async {
    if (locked) throw StateError('Secure vault locked');
    keys[hash]=Uint8List.fromList(value);
  }
  @override
  Future<void> delete(String hash) async {
    if (locked) throw StateError('Secure vault locked');
    keys.remove(hash);
  }
}

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const owner='account-private';
  final now=DateTime.utc(2026,10,14,20,0);
  NativeM33OfflineDraftQueue queue({String id='batch-one',String user=owner})
    => NativeM33OfflineDraftQueue(ownerId:user,queueId:id,
      source:'offline',createdAt:now,entries:[
        NativeM33PriorityDraft(
          operationId:'id-one',titleId:'PRIVATE-LIBRARY-ID',
          beforePriority:'low',afterPriority:'high',createdAt:now),
      ]);
  late Directory directory;
  late NativeM33DraftStore store;
  late M33MemoryVault keys;
  File file({String user=owner,String suffix=''}) {
    final hash=sha256.convert(utf8.encode('m33-device-drafts:'+user)).toString();
    return File(directory.path+Platform.pathSeparator+'mediaflow-m33-drafts'+
      Platform.pathSeparator+'queue-'+hash+'.json'+suffix);
  }

  setUp(() async {
    directory=await Directory.systemTemp.createTemp('m33-encrypted-test-');
    keys=M33MemoryVault();
    store=NativeM33DraftStore(
      directoryProvider:() async => directory,keyVault:keys);
  });
  tearDown(() async {
    if(await directory.exists())await directory.delete(recursive:true);
  });

  test('encrypted queue survives restart with account isolation',() async {
    await store.save(owner,queue());
    final plaintext=await file().readAsString();
    expect(plaintext,isNot(contains('PRIVATE-LIBRARY-ID')));
    expect(plaintext,isNot(contains('afterPriority')));
    expect(plaintext,isNot(contains('high')));
    final restarted=NativeM33DraftStore(
      directoryProvider:() async => directory,keyVault:keys);
    expect((await restarted.load(owner))?.entries.single.afterPriority,'high');
    expect(await restarted.load('other-user'),isNull);
    expect(keys.keys.length,1);
  });

  test('existing queue cannot be silently replaced or clobbered by foreign user',
      () async {
    await store.save(owner,queue());
    await expectLater(store.save(owner,queue(id:'newer')),throwsStateError);
    expect(() => store.save('other-user',queue()),throwsStateError);
    expect((await store.load(owner))?.queueId,'batch-one');
  });

  test('explicit same-queue replacement keeps previous generation for recovery',
      () async {
    await store.save(owner,queue());
    await store.save(owner,queue(id:'second'),
      explicitlyReplacingQueueId:'batch-one');
    expect((await store.load(owner))?.queueId,'second');
    expect(await file(suffix:'.previous').exists(),true);
    await file().writeAsString('{broken',flush:true);
    expect((await store.load(owner))?.queueId,'batch-one');
    await expectLater(store.save(owner,queue(id:'third')),throwsStateError);
  });

  test('ciphertext tamper and OS key loss both fail closed',() async {
    await store.save(owner,queue());
    final doc=jsonDecode(await file().readAsString()) as Map<String,dynamic>;
    doc['mac']=base64Encode(List<int>.filled(16,0));
    await file().writeAsString(jsonEncode(doc),flush:true);
    expect(await store.load(owner),isNull);
    await expectLater(store.save(owner,queue(id:'replacement')),
      throwsStateError);
    keys.keys.clear();
    expect(await store.load(owner),isNull);
    await expectLater(store.save(owner,queue(id:'replacement')),
      throwsStateError);
  });

  test('account key namespaces stay independent and clear only owner',() async {
    await store.save(owner,queue());
    await store.save('other-user',queue(id:'other-batch',user:'other-user'));
    expect(keys.keys.length,2);
    await store.clear(owner);
    expect(await store.load(owner),isNull);
    expect((await store.load('other-user'))?.queueId,'other-batch');
    expect(keys.keys.length,1);
  });

  test('simultaneous save+logout clear cannot resurrect old drafts',() async {
    final saving=store.save(owner,queue());
    final clearing=store.clear(owner);
    await Future.wait([saving,clearing]);
    expect(await store.load(owner),isNull);
    expect(await file().exists(),false);
    expect(keys.keys,isEmpty);
  });


  test('M34 targeted resolution removes prior rollback generation on success',
      () async {
    await store.save(owner,queue());
    await store.replaceForResolution(owner,queue(id:'m34-cleaned'),'batch-one');
    expect((await store.load(owner))?.queueId,'m34-cleaned');
    expect(await file(suffix:'.previous').exists(),false);
    // If the newly cleaned snapshot corrupts, an old discarded intent must
    // never reappear through the previous-generation fallback.
    await file().writeAsString('{corrupted',flush:true);
    expect(await store.load(owner),isNull);
  });

  test('secure storage unavailable fails safe, does not return plaintext',() async {
    await store.save(owner,queue());
    keys.locked=true;
    expect(await store.load(owner),isNull);
    await expectLater(store.clear(owner),throwsStateError);
    expect(await file().exists(),false);
    keys.locked=false;
    expect(await store.load(owner),isNull);
  });
}
