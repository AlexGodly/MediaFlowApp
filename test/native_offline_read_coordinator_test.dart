import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/services/native_offline_read_coordinator.dart';
import 'package:mediaflow_app/services/native_offline_snapshot_store.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';

MediaFlowCatalog sample(String title) => MediaFlowCatalog(
  categories: [MediaFlowCategory.fromJson({
    'id': 'anime', 'name': 'Anime',
  })],
  library: [MediaFlowTitle.fromJson({
    'id': 't1', 'title': title, 'categoryId': 'anime',
  })],
);

void main() {
  var owner = 'a';
  var validOwner = true;
  var attempts = 0;
  var reads = 0;
  var writes = 0;
  var clears = 0;
  NativeCachedSnapshot? cached;
  late Future<MediaFlowCatalog> Function() cloud;
  late NativeOfflineReadCoordinator coordinator;
  final savedAt = DateTime.utc(2026, 10, 14, 9, 10);

  setUp(() {
    owner = 'a';
    validOwner = true;
    attempts = 0;
    reads = 0;
    writes = 0;
    clears = 0;
    cached = null;
    cloud = () async => sample('Cloud');
    coordinator = NativeOfflineReadCoordinator(
      ownerId: owner,
      isOwnerCurrent: () => validOwner && owner == 'a',
      readCloud: () { attempts++; return cloud(); },
      readDeviceCopy: (account) async {
        reads++;
        expect(account, 'a');
        return cached;
      },
      writeDeviceCopy: (account, snapshot) async {
        expect(account, 'a');
        writes++;
      },
      clearDeviceCopyStorage: (account) async {
        expect(account, 'a');
        clears++;
        cached = null;
      },
    );
  });
  tearDown(() => coordinator.dispose());

  test('cloud-first fetch cached in RAM, read-only recovery not uploaded', () async {
    final first = await coordinator.load();
    expect(first.library.single.title, 'Cloud');
    expect(coordinator.source.value, NativeSnapshotSource.cloud);
    expect(coordinator.refreshing.value, isFalse);
    expect((await coordinator.load()).library.single.title, 'Cloud');
    expect(attempts, 1);
    expect(reads, 0);
    expect(writes, 1);
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, isFalse);
  });

  test('transient connection failure uses verified device copy only', () async {
    cached = NativeCachedSnapshot(catalog: sample('Saved'),
      savedAt: savedAt, recoveredPrevious: false);
    cloud = () async => throw const SocketException('offline');
    final recovered = await coordinator.load();
    expect(recovered.library.single.title, 'Saved');
    expect(coordinator.source.value, NativeSnapshotSource.offline);
    expect(coordinator.offlineSavedAt.value, savedAt);
    expect(reads, 1);
    expect(writes, 0);
  });

  test('previous generation explicitly identified and still read-only', () async {
    cached = NativeCachedSnapshot(catalog: sample('Previous'),
      savedAt: savedAt, recoveredPrevious: true);
    cloud = () async => throw const SocketException('offline');
    expect((await coordinator.load()).library.single.title, 'Previous');
    expect(coordinator.source.value, NativeSnapshotSource.recoveredPrevious);
    expect(coordinator.offlineSavedAt.value, savedAt);
  });

  test('reconnect keeps offline warning during manual refresh, then clears', () async {
    cached = NativeCachedSnapshot(catalog: sample('Cached'),
      savedAt: savedAt, recoveredPrevious: false);
    cloud = () async => throw const SocketException('offline');
    await coordinator.load();
    final pending = Completer<MediaFlowCatalog>();
    cloud = () => pending.future;
    final refresh = coordinator.reload();
    expect(coordinator.source.value, NativeSnapshotSource.offline);
    expect(coordinator.refreshing.value, isTrue);
    expect(coordinator.offlineSavedAt.value, savedAt);
    pending.complete(sample('Fresh'));
    expect((await refresh).library.single.title, 'Fresh');
    expect(coordinator.source.value, NativeSnapshotSource.cloud);
    expect(coordinator.offlineSavedAt.value, isNull);
    expect(coordinator.refreshing.value, isFalse);
  });

  test('in-memory last good copy is used if encryption storage fails', () async {
    await coordinator.load();
    cloud = () async => throw const SocketException('offline');
    final result = await coordinator.reload();
    expect(result.library.single.title, 'Cloud');
    expect(coordinator.source.value, NativeSnapshotSource.offlineMemory);
    expect(coordinator.offlineSavedAt.value, isNull);
  });

  test('no cloud and no recovered copy fails closed, retry still possible', () async {
    cloud = () async => throw const SocketException('offline');
    await expectLater(coordinator.load(), throwsA(isA<SocketException>()));
    expect(coordinator.source.value, NativeSnapshotSource.unavailable);
    cloud = () async => sample('Restored');
    expect((await coordinator.load()).library.single.title, 'Restored');
    expect(attempts, 2);
  });

  test('malformed or missing cloud cannot silently fall back to old copy', () async {
    cached = NativeCachedSnapshot(catalog: sample('Unsafe backup'),
      savedAt: savedAt, recoveredPrevious: false);
    cloud = () async => throw const FormatException('Broken cloud JSON');
    await expectLater(coordinator.load(), throwsFormatException);
    expect(reads, 0);
    expect(coordinator.source.value, NativeSnapshotSource.invalidCloud);
    cloud = () async => throw const NativeMissingCloudRow();
    await expectLater(coordinator.reload(), throwsA(isA<NativeMissingCloudRow>()));
    expect(reads, 0);
    expect(coordinator.source.value, NativeSnapshotSource.invalidCloud);
  });

  test('older overlapping response cannot replace newer cloud result', () async {
    final earlier = Completer<MediaFlowCatalog>();
    final newer = Completer<MediaFlowCatalog>();
    var nth = 0;
    cloud = () => (++nth == 1 ? earlier.future : newer.future);
    final first = coordinator.load();
    final second = coordinator.reload();
    newer.complete(sample('Newer'));
    expect((await second).library.single.title, 'Newer');
    earlier.complete(sample('Old'));
    await expectLater(first, throwsStateError);
    expect((await coordinator.load()).library.single.title, 'Newer');
    expect(coordinator.source.value, NativeSnapshotSource.cloud);
    expect(writes, 1);
  });

  test('account switch invalidates a pending response and all fallback', () async {
    final pending = Completer<MediaFlowCatalog>();
    cloud = () => pending.future;
    final first = coordinator.load();
    owner = 'b'; validOwner = false;
    pending.complete(sample('Old owner secret'));
    await expectLater(first, throwsStateError);
    expect(writes, 0);
    expect(reads, 0);
  });

  test('sign-out invalidates in-flight requests and wipes device cache', () async {
    final pending = Completer<MediaFlowCatalog>();
    cloud = () => pending.future;
    final first = coordinator.load();
    await coordinator.closeAndPurge();
    pending.complete(sample('Old secret'));
    await expectLater(first, throwsStateError);
    expect(coordinator.source.value, NativeSnapshotSource.idle);
    expect(clears, 1);
    expect(writes, 0);
    expect(() => coordinator.reload(), throwsStateError);
  });

  test('clearing device copy keeps current view in RAM, not a cloud upload',
      () async {
    await coordinator.load();
    await coordinator.clearDeviceCopy();
    expect(clears, 1);
    cloud = () async => throw const SocketException('offline');
    final view = await coordinator.reload();
    expect(view.library.single.title, 'Cloud');
    expect(coordinator.source.value, NativeSnapshotSource.offlineMemory);
    expect(writes, 1);
  });

  test('failure to write encrypted cache does not falsify cloud status',
      () async {
    coordinator.dispose();
    coordinator = NativeOfflineReadCoordinator(
      ownerId: 'a',
      isOwnerCurrent: () => true,
      readCloud: () async => sample('Cloud readable'),
      readDeviceCopy: (_) async => null,
      writeDeviceCopy: (_, __) async =>
          throw StateError('OS key vault unavailable'),
      clearDeviceCopyStorage: (_) async {},
    );
    expect((await coordinator.load()).library.single.title, 'Cloud readable');
    // Cache save is async and expected to turn cloud into cloudNotCached.
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.source.value, NativeSnapshotSource.cloudNotCached);
    expect(coordinator.offlineSavedAt.value, isNull);
  });
}
