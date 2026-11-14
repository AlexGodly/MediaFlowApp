import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_ops.dart';
import 'package:mediaflow/src/data/edit_op.dart';
import 'package:mediaflow/src/logic/history_logic.dart';

Map<String, dynamic> _copy(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

Map<String, dynamic> _state() => {
      'savedAt': 1,
      'categories': [
        {'id': 'c', 'name': 'Anime', 'unit': 'episodes', 'minutesPerUnit': 24, 'target': 3, 'enabled': true},
      ],
      'library': [
        {'id': 'a', 'title': 'Alpha', 'categoryId': 'c', 'progress': 1, 'total': 12, 'status': 'active', 'modifiedAt': 10},
        {'id': 'b', 'title': 'Beta', 'categoryId': 'c', 'progress': 0, 'status': 'planned', 'modifiedAt': 10},
      ],
      'sessions': [
        {'id': 's1', 'date': '2026-10-30', 'timestamp': 1793300000000, 'categoryId': 'c', 'actualAmount': 2, 'minutes': 48, 'status': 'complete', 'xp': 100, 'unit': 'episodes'},
        {'id': 's2', 'date': '2026-10-31', 'timestamp': 1793400000000, 'categoryId': 'c', 'actualAmount': 1, 'minutes': 24, 'status': 'partial', 'xp': 50, 'unit': 'episodes'},
      ],
      'completionTimeline': [],
      'xpLedger': {'libraryAdditions': {}},
      'activityLog': [],
    };

void main() {
  test('a diff replays to the same account and survives JSON', () {
    final a = _state();
    final b = _copy(a);
    (b['library'] as List)[0]['progress'] = 5;
    (b['library'] as List).add({'id': 'n', 'title': 'New', 'categoryId': 'c'});
    (b['library'] as List).removeAt(1);
    (b['completionTimeline'] as List).add({'libraryId': 'a', 'completedAt': 5});
    b['xpLedger']['ratings'] = {'a': 10};
    final op = editFromStates(a, b, now: 100)!;
    final again = AccountOp.fromJson(jsonDecode(jsonEncode(op.toJson())) as Map<String, dynamic>);
    final target = _copy(a);
    expect(again.apply(target), isTrue);
    expect(jsonEncode(target..remove('savedAt')), jsonEncode(_copy(b)..remove('savedAt')));
    expect(again.apply(target), isFalse, reason: 'replaying twice changes nothing');
  });

  test('newest change wins per field; other fields are kept', () {
    final a = _state();
    final mine = _copy(a);
    (mine['library'] as List)[0]
      ..['progress'] = 5
      ..['rating'] = 8
      ..['modifiedAt'] = 100;
    final op = editFromStates(a, mine, now: 100)!;
    // The website changed progress later, on another device.
    final cloud = _copy(a);
    (cloud['library'] as List)[0]
      ..['progress'] = 7
      ..['modifiedAt'] = 200;
    op.apply(cloud);
    final item = (cloud['library'] as List)[0];
    expect(item['progress'], 7);
    expect(item['rating'], 8);
    expect(item['modifiedAt'], 200);
    // An older website change loses to this device's newer one.
    final older = _copy(a);
    (older['library'] as List)[0]
      ..['progress'] = 7
      ..['modifiedAt'] = 50;
    op.apply(older);
    expect((older['library'] as List)[0]['progress'], 5);
  });

  test('inverse changes undo an edit', () {
    final a = _state();
    final b = _copy(a);
    deleteSessions(b, {'s1'}, 1793433600000);
    final op = editFromStates(a, b, now: 1793433600000)!;
    expect((b['sessions'] as List).length, 1);
    expect((b['activityLog'] as List).single['action'], 'Delete history');
    final undone = _copy(b);
    for (final c in op.changes.reversed) {
      if (c.path.first != 'activityLog') applyChange(undone, c.inverse(), 1793433600001);
    }
    expect((undone['sessions'] as List).map((s) => s['id']), ['s1', 's2']);
  });

  test('editing a log recalculates its XP and unit', () {
    final s = _state();
    expect(editSession(s, 's2', 1793433600000,
        categoryId: 'c', date: '2026-10-31', status: 'complete', targetAmount: 3, actualAmount: 3, minutes: 72, note: 'x'), isTrue);
    final log = (s['sessions'] as List)[1];
    expect(log['actualAmount'], 3);
    expect(log['unit'], 'episodes');
    expect(log['note'], 'x');
    expect(log['xp'], greaterThan(0));
    expect(log['xpWithStreak'], isNotNull);
  });

  test('XP History lists logs and ledger rewards', () {
    final s = _state();
    s['xpLedger'] = {
      'ratings': {'a': 10},
      'v348EventMeta': {
        'k1': {'kind': 'ratings', 'xp': 4, 'timestamp': 5, 'subjectId': 'a', 'source': 'Rating reward'},
      },
    };
    final rows = xpHistory(s);
    expect(rows.where((r) => r.kind == 'consumption').length, 2);
    final legacy = rows.where((r) => r.id == 'legacy:ratings:a').single;
    expect(legacy.xp, 6);
    expect(xpHistoryCsv(rows), contains('Rating reward'));
  });
}
