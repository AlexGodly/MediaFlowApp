// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_offline_key_vault.dart';
import 'package:mediaflow_app/services/native_offline_projection_codec.dart';
import 'package:mediaflow_app/services/native_offline_snapshot_store.dart';

class MemoryKeyVault implements NativeOfflineKeyVault {
  final Map<String, Uint8List> keys = {};
  bool unavailable = false;

  @override
  Future<Uint8List?> read(String ownerHash) async {
    if (unavailable) throw StateError('Locked secure key store');
    final bytes = keys[ownerHash];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> write(String ownerHash, Uint8List keyBytes) async {
    if (unavailable) throw StateError('Locked secure key store');
    keys[ownerHash] = Uint8List.fromList(keyBytes);
  }

  @override
  Future<void> delete(String ownerHash) async {
    if (unavailable) throw StateError('Locked secure key store');
    keys.remove(ownerHash);
  }
}

MediaFlowCatalog catalog(String title, {int count = 1}) => MediaFlowCatalog(
  categories: [MediaFlowCategory.fromJson({
    'id': 'anime', 'name': 'Anime', 'icon': 'A',
  })],
  library: [
    for (var i = 0; i < count; i++)
      MediaFlowTitle.fromJson({
        'id': 'id-' + i.toString(),
        'title': count == 1 ? title : 'Title ' + i.toString(),
        'categoryId': 'anime', 'status': 'watching', 'priority': 'high',
        'progress': i % 30, 'total': 30, 'rating': 7.5,
        'tags': ['tag'], 'createdAt': '2026-10-13T12:00:00Z',
        'seasons': [{'name': 'Season 1', 'progress': 1, 'total': 12}],
      }),
  ],
  personalOrderIds: const ['id-0'],
  collections: [
    MediaFlowCollection.fromJson({
      'id': 'c1', 'title': 'Favorites', 'titleIds': ['id-0'],
    }),
  ],
  sessions: [
    MediaFlowSession.fromJson({
      'id': 's1', 'date': '2026-10-13', 'xp': 25, 'minutes': 45,
      'titles': [{'title': title, 'libraryId': 'id-0', 'qty': 1}],
    }),
  ],
  currentTask: MediaFlowTask.fromJson({
    'categoryId': 'anime', 'title': title, 'low': 1, 'high': 2,
    'reasons': ['Example'],
  }),
  sessionActive: true,
  tasksPerDay: 3,
  dailyMinutes: 90,
  updatedAt: DateTime.utc(2026, 10, 13),
);

String ownerHash(String owner) => sha256.convert(utf8.encode(owner)).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MemoryKeyVault keys;
  late NativeOfflineSnapshotStore store;

  File snapshot(String account, {String suffix = ''}) => File(
      directory.path + Platform.pathSeparator + 'mediaflow-offline-v2' +
      Platform.pathSeparator + 'snapshot-' + ownerHash(account) +
      '.json' + suffix);

  File oldSnapshot(String account, {String suffix = ''}) => File(
      directory.path + Platform.pathSeparator + 'mediaflow-offline' +
      Platform.pathSeparator + 'snapshot-' + ownerHash(account) +
      '.json' + suffix);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mf-native-m18-');
    keys = MemoryKeyVault();
    store = NativeOfflineSnapshotStore(
      directoryProvider: () async => directory,
      keyVault: keys,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('projection codec roundtrip retains native-only read data', () {
    final original = catalog('Hotel');
    final encoded = NativeOfflineProjectionCodec.encode(original);
    expect(encoded['format'], NativeOfflineProjectionCodec.format);
    final decoded = NativeOfflineProjectionCodec.decode(encoded);
    expect(decoded.library.single.title, 'Hotel');
    expect(decoded.library.single.seasons.single.total, 12);
    expect(decoded.sessions.single.xp, 25);
    expect(decoded.collections.single.titleIds, ['id-0']);
    expect(decoded.personalOrderIds, ['id-0']);
    expect(decoded.currentTask?.title, 'Hotel');
    expect(decoded.sessionActive, true);
    expect(decoded.dailyMinutes, 90);
    expect(decoded.updatedAt, DateTime.utc(2026, 10, 13));
  });

  test('AES-GCM payload is not plaintext and roundtrips after app restart',
      () async {
    await store.save('account-a', catalog('Super Private Title'));
    final disk = await snapshot('account-a').readAsString();
    expect(disk, contains(NativeOfflineSnapshotStore.format));
    expect(disk, isNot(contains('Super Private Title')));
    expect(disk, isNot(contains('"library"')));
    expect(disk, isNot(contains('state_data')));
    expect(keys.keys[ownerHash('account-a')]?.length, 32);
    final restarted = NativeOfflineSnapshotStore(
      directoryProvider: () async => directory, keyVault: keys,
    );
    final data = await restarted.load('account-a');
    expect(data?.catalog.library.single.title, 'Super Private Title');
    expect(data?.catalog.sessions.single.xp, 25);
  });

  test('encrypted device cache is isolated and clearing removes key',
      () async {
    await store.save('account-a', catalog('Private A'));
    await store.save('account-b', catalog('Private B'));
    expect((await store.load('account-a'))?.catalog.library.single.title,
        'Private A');
    expect((await store.load('account-b'))?.catalog.library.single.title,
        'Private B');
    await store.clear('account-a');
    expect(await store.load('account-a'), isNull);
    expect(await snapshot('account-a').exists(), false);
    expect(keys.keys.containsKey(ownerHash('account-a')), false);
    expect((await store.load('account-b'))?.catalog.library.single.title,
        'Private B');
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, isFalse);
  });

  test('corrupt primary recovers the prior encrypted generation', () async {
    await store.save('account-a', catalog('Older'));
    await store.save('account-a', catalog('Newer'));
    expect(await snapshot('account-a', suffix: '.previous').exists(), true);
    await snapshot('account-a').writeAsString('{"partial":', flush: true);
    final recovered = await store.load('account-a');
    expect(recovered?.recoveredPrevious, true);
    expect(recovered?.catalog.library.single.title, 'Older');
  });

  test('authenticated metadata tampering is rejected', () async {
    await store.save('account-a', catalog('Private A'));
    final file = snapshot('account-a');
    final original = jsonDecode(await file.readAsString())
        as Map<String, dynamic>;
    for (final change in ['ownerHash', 'savedAt', 'mac', 'nonce']) {
      final altered = Map<String, dynamic>.from(original);
      switch (change) {
        case 'ownerHash':
          altered[change] = ownerHash('account-b');
          break;
        case 'savedAt':
          altered[change] = '2020-01-01T00:00:00.000Z';
          break;
        case 'mac':
          altered[change] = base64Encode(List<int>.filled(16, 0));
          break;
        case 'nonce':
          altered[change] = base64Encode(List<int>.filled(12, 0));
          break;
      }
      await file.writeAsString(jsonEncode(altered), flush: true);
      expect(await store.load('account-a'), isNull, reason: change);
    }
    await file.writeAsString(jsonEncode(original), flush: true);
    expect((await store.load('account-a'))?.catalog.library.single.title,
        'Private A');
  });

  test('lost key never causes plaintext fallback or unauthenticated access',
      () async {
    await store.save('account-a', catalog('Private A'));
    keys.keys.remove(ownerHash('account-a'));
    expect(await store.load('account-a'), isNull);
    // Once the live signed-in client re-fetches cloud data, it can establish
    // a new key and replace the unrecoverable copy without touching Supabase.
    await store.save('account-a', catalog('Cloud Recovered'));
    expect((await store.load('account-a'))?.catalog.library.single.title,
        'Cloud Recovered');
  });

  test('secure-key provider failure blocks saving and recovers no cache',
      () async {
    keys.unavailable = true;
    await expectLater(store.save('account-a', catalog('Secret')),
        throwsStateError);
    expect(await store.load('account-a'), isNull);
    expect(await snapshot('account-a').exists(), false);
  });

  test('M17 plaintext cache is purged and never used as a fallback', () async {
    final legacy = oldSnapshot('account-a');
    await legacy.parent.create(recursive: true);
    await legacy.writeAsString('{"library":[{"title":"EXPOSED"}]}');
    await oldSnapshot('account-a', suffix: '.previous').writeAsString('old');
    await oldSnapshot('account-a', suffix: '.pending').writeAsString('old');
    expect(await store.load('account-a'), isNull);
    expect(await legacy.exists(), false);
    expect(await oldSnapshot('account-a', suffix: '.previous').exists(), false);
    expect(await oldSnapshot('account-a', suffix: '.pending').exists(), false);
    await store.save('account-a', catalog('New encrypted copy'));
    expect((await store.load('account-a'))?.catalog.library.single.title,
        'New encrypted copy');
  });

  test('pending writes do not become committed snapshots', () async {
    await store.save('account-a', catalog('Committed'));
    final pending = snapshot('account-a', suffix: '.pending');
    await pending.writeAsString('a partial save');
    expect((await store.load('account-a'))?.catalog.library.single.title,
        'Committed');
    await store.clear('account-a');
    expect(await pending.exists(), false);
  });

  test('queued save cannot recreate device data after sign-out purge',
      () async {
    final save = store.save('account-a', catalog('Earlier'));
    final purge = store.clear('account-a');
    await Future.wait([save, purge]);
    expect(await store.load('account-a'), isNull);
    expect(keys.keys.containsKey(ownerHash('account-a')), false);
  });

  test('100000-title synthetic encrypted snapshot roundtrip', () async {
    final timer = Stopwatch()..start();
    await store.save('scale-account', catalog('unused', count: 100000));
    final result = await store.load('scale-account');
    expect(result?.catalog.library.length, 100000);
    expect(result?.catalog.library[99999].id, 'id-99999');
    expect(result?.catalog.personalOrderIds.single, 'id-0');
    // Timing is CI telemetry, not a real-device performance guarantee.
    // ignore: avoid_print
    print('ENCRYPTED_OFFLINE_100K_MS=' +
        timer.elapsedMilliseconds.toString());
  }, timeout: const Timeout(Duration(minutes: 4)));
}
