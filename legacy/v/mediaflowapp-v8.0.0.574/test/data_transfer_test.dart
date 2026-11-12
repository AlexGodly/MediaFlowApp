import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/data_transfer.dart';

Map<String, dynamic> _state() => {
      'savedAt': 5,
      'cloudSyncVersion': 201,
      'categories': [
        {'id': 'anime', 'name': 'Anime'},
        {'id': 'books', 'name': 'Books'},
      ],
      'categoryOrder': ['anime', 'books'],
      'library': [
        {'id': 't1', 'title': 'One'},
      ],
      'sessions': [
        {'id': 's1'},
      ],
      'settings': {'theme': 'dark', 'mysteryKey': 1},
      'collections': [
        {'id': 'c1', 'title': 'Mine', 'titleIds': ['t1'], 'updatedAt': 100},
      ],
      'collectionTombstones': [],
      'profileName': 'Alex',
      'futureField': {'kept': true},
    };

void main() {
  test('full backup has every account field and the website header', () {
    final b = buildFullBackup(_state(), DateTime.utc(2026, 11, 12));
    expect(b['backupFormat'], 'MediaFlow_Full_Backup');
    expect(b['backupSchemaVersion'], 29);
    expect(b['futureField'], {'kept': true});
    expect(b.containsKey('savedAt'), isFalse);
    expect(b.containsKey('cloudSyncVersion'), isFalse);
    expect((b['backupManifest'] as Map)['counts']['libraryTitles'], 1);
    expect(validateBackup(b), isNull);
  });

  test('restoring a backup replaces its fields and drops the header', () {
    final b = buildFullBackup(_state(), DateTime.utc(2026));
    b['library'] = [];
    final copy = {'library': [{'id': 'x'}], 'onlyHere': 1};
    applyFullBackup(copy, b);
    expect(copy['library'], isEmpty);
    expect(copy['onlyHere'], 1);
    expect(copy.containsKey('backupManifest'), isFalse);
    expect(copy['profileName'], 'Alex');
  });

  test('validation matches the website', () {
    expect(validateBackup([]), isNotNull);
    expect(validateBackup({'backupFormat': 'MediaFlow_Full_Backup'}), contains('incomplete'));
    expect(validateBackup({'categories': [], 'library': [], 'sessions': [], 'settings': {}, 'xpLedger': []}), contains('xpLedger'));
    expect(validateBackup({'categories': [], 'library': [], 'sessions': [], 'settings': {}}), isNull);
  });

  test('settings preset round trip keeps extra categories', () {
    final p = buildSettingsPreset(_state(), DateTime.utc(2026));
    expect(validateSettingsPreset(p), isNull);
    p['categories'] = [
      {'id': 'books', 'name': 'Novels'},
    ];
    p['categoryOrder'] = ['books'];
    final copy = _state();
    applySettingsPreset(copy, p);
    final cats = (copy['categories'] as List).cast<Map>();
    expect(cats.map((c) => c['id']), ['books', 'anime']);
    expect(cats.first['name'], 'Novels');
    expect((copy['settings'] as Map)['mysteryKey'], 1);
    expect((copy['settings'] as Map)['categoryOrder'], ['books', 'anime']);
    expect((copy['settings'] as Map)['backup'], isA<Map>());
  });

  test('collections import: newer wins, tombstones remove older', () {
    final copy = _state();
    final file = {
      'collections': [
        {'id': 'c1', 'title': 'Old copy', 'updatedAt': 50},
        {'id': 'c2', 'title': 'New', 'updatedAt': 200},
      ],
      'collectionTombstones': [
        {'id': 'c3', 'deletedAt': 10},
      ],
    };
    final r = importCollections(copy, file, 1000, () => 'uid');
    expect(r.imported, 1);
    expect(r.skipped, 1);
    final cols = (copy['collections'] as List).cast<Map>();
    expect(cols.firstWhere((c) => c['id'] == 'c1')['title'], 'Mine');
    expect(cols.firstWhere((c) => c['id'] == 'c2')['updatedAt'], 200);
    expect((copy['collectionTombstones'] as List).single['id'], 'c3');
    final again = importCollections(copy, {'collections': [], 'collectionTombstones': [{'id': 'c2', 'deletedAt': 300}]}, 1000, () => 'u');
    expect(again.removed, 1);
  });
}
