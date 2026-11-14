// Website v565: XP for every action, background work and time away.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/account_ops.dart';
import 'package:mediaflow/src/logic/action_xp.dart';
import 'package:mediaflow/src/util/js.dart';

Map<String, dynamic> _state() => <String, dynamic>{
      'settings': <String, dynamic>{'leveling': <String, dynamic>{'activeTimeXPPerMinute': 2}},
      'sessions': <dynamic>[],
      'xpLedger': <String, dynamic>{},
    };

void main() {
  test('edits are grouped by what they change; edits with their own XP earn none', () {
    expect(editGroup([['sessions', 's1', 'minutes']])?.group, 'history');
    expect(editGroup([['library', 't1', 'tags']]), (group: 'library', subject: 't1'));
    expect(editGroup([['categories', 'c1', 'name']])?.group, 'categories');
    expect(editGroup([['settings', 'v441RecoveryUI']])?.group, 'settings');
    expect(editGroup([['settings', 'themeId']])?.group, 'appearance');
    expect(editGroup([['library', 't1', 'title'], ['xpLedger', 'libraryEdits', 't1']]), isNull, reason: 'Library edit XP already paid');
    expect(editGroup([['activityLog', '0']]), isNull);
    expect(editGroup(const []), isNull);
  });

  test('the same action on the same thing earns once per 5 minutes', () {
    final r = ActionRepeat();
    expect(r.allow('library\u0001t1', 0), isTrue);
    expect(r.allow('library\u0001t1', 60000), isFalse);
    expect(r.allow('library\u0001t2', 60000), isTrue, reason: 'different things always earn');
    expect(r.allow('library\u0001t1', 5 * 60000), isTrue);
  });

  test('an action event is written once under its key, in the website ledger format', () {
    final s = _state();
    final e = ActionXpOp(key: 'mf565Action:k', kind: 'mf565Action.library', base: 3, source: 'Library tools', at: 1000, subjectId: 't1');
    expect(e.write(s), greaterThan(0));
    expect(e.write(s), 0, reason: 'a replay never counts twice');
    final meta = asMap(asMap(asMap(s['xpLedger'])!['v348EventMeta'])!['mf565Action:k'])!;
    expect(meta.keys, containsAll(['kind', 'baseXP', 'multiplier', 'xp', 'timestamp', 'source', 'details', 'subjectId']));
    expect(meta['kind'], 'mf565Action.library');
    expect(meta['baseXP'], 3);
  });

  test('away time is credited once, and not when MediaFlow was seen meanwhile', () {
    const min = 60000;
    final s = _state();
    asMap(s['xpLedger'])!['mf565LastSeenAt'] = 0;
    final op = AwayXpOp(from: 1000, to: 1000 + 60 * min);
    expect(op.apply(s), isTrue);
    final ledger = asMap(s['xpLedger'])!;
    expect(asMap(ledger['v348ActionEvents'])!['mf565Away:1000'], 30, reason: '60 min × 0.5 (a quarter of 2 XP a minute)');
    expect(ledger['mf565LastSeenAt'], 1000 + 60 * min);
    expect(AwayXpOp(from: 1000, to: 1000 + 60 * min).apply(s), isFalse, reason: 'never twice');

    final seen = _state();
    asMap(seen['xpLedger'])!['mf565LastSeenAt'] = 1000 + 30 * min; // the website was open meanwhile
    AwayXpOp(from: 1000, to: 1000 + 60 * min).apply(seen);
    expect(asMap(asMap(seen['xpLedger'])!['v348ActionEvents'])?['mf565Away:1000'], isNull);

    final short = _state();
    AwayXpOp(from: 1000, to: 1000 + 10 * min).apply(short);
    expect(asMap(asMap(short['xpLedger'])!['v348ActionEvents'])?['mf565Away:1000'], isNull, reason: 'under 15 minutes is not away');
  });
}
