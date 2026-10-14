import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_offline_projection_codec.dart';
import 'package:mediaflow_app/services/native_offline_snapshot_store.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late NativeOfflineSnapshotStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mf-native-m17-');
    store = NativeOfflineSnapshotStore(
      directoryProvider: () async => directory,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('projection roundtrip retains native fields, not unknown web state',
      () {
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
    expect(() => NativeOfflineProjectionCodec.decode({
      'format': 'wrong', 'snapshot': {},
    }), throwsFormatException);
  });

  test('device cache is account isolated and never enables cloud writes',
      () async {
    await store.save('account-a', catalog('Private A'));
    await store.save('account-b', catalog('Private B'));
    expect((await store.load('account-a'))?.catalog.library.single.title,
        'Private A');
    expect((await store.load('account-b'))?.catalog.library.single.title,
        'Private B');
    await store.clear('account-a');
    expect(await store.load('account-a'), isNull);
    expect((await store.load('account-b'))?.catalog.library.single.title,
        'Private B');
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, isFalse);
  });

  test('corrupt current generation falls back to previous verified copy',
      () async {
    await store.save('account-a', catalog('Older'));
    await store.save('account-a', catalog('Newer'));
    final folder = Directory(directory.path + Platform.pathSeparator +
        'mediaflow-offline');
    final id = sha256.convert(utf8.encode('account-a')).toString();
    final primary = File(folder.path + Platform.pathSeparator +
        'snapshot-' + id + '.json');
    expect(await primary.exists(), true);
    await primary.writeAsString('{"partial":', flush: true);
    final recovered = await store.load('account-a');
    expect(recovered?.recoveredPrevious, true);
    expect(recovered?.catalog.library.single.title, 'Older');
  });

  test('tampered checksum and foreign owner never load', () async {
    await store.save('account-a', catalog('Private A'));
    final id = sha256.convert(utf8.encode('account-a')).toString();
    final primary = File(directory.path + Platform.pathSeparator +
        'mediaflow-offline' + Platform.pathSeparator +
        'snapshot-' + id + '.json');
    final raw = jsonDecode(await primary.readAsString()) as Map<String, dynamic>;
    raw['ownerHash'] = 'foreign';
    await primary.writeAsString(jsonEncode(raw), flush: true);
    expect(await store.load('account-a'), isNull);
    expect(await store.load('account-b'), isNull);
  });

  test('unfinished pending file is never restored', () async {
    await store.save('account-a', catalog('Committed'));
    final id = sha256.convert(utf8.encode('account-a')).toString();
    final pending = File(directory.path + Platform.pathSeparator +
        'mediaflow-offline' + Platform.pathSeparator +
        'snapshot-' + id + '.json.pending');
    await pending.writeAsString('a partial save');
    expect((await store.load('account-a'))?.catalog.library.single.title,
        'Committed');
    await store.clear('account-a');
    expect(await pending.exists(), false);
  });

  test('queued saves cannot repopulate cache after sign-out purge',
      () async {
    final save = store.save('account-a', catalog('Earlier'));
    final purge = store.clear('account-a');
    await Future.wait([save, purge]);
    expect(await store.load('account-a'), isNull);
  });

  test('100000-title synthetic snapshot roundtrips without cloud writes',
      () async {
    final timer = Stopwatch()..start();
    await store.save('scale-account', catalog('unused', count: 100000));
    final result = await store.load('scale-account');
    expect(result?.catalog.library.length, 100000);
    expect(result?.catalog.library[99999].id, 'id-99999');
    expect(result?.catalog.personalOrderIds.single, 'id-0');
    // Telemetry only: this does not certify real-device performance.
    // ignore: avoid_print
    print('OFFLINE_SNAPSHOT_100K_MS=' + timer.elapsedMilliseconds.toString());
  }, timeout: const Timeout(Duration(minutes: 4)));
}
