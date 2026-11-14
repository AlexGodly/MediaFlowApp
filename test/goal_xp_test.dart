// 11.0.0 (website v580): task goal XP — +100 at the minimum, +300 more at the
// maximum, +10 per unit past it (up to +100), once per task by any log; it is
// part of the log's base XP (the day streak multiplies it) and of the total.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/goal_xp.dart';
import 'package:mediaflow/src/logic/leveling.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/state/models.dart';
import 'package:mediaflow/src/util/js.dart';

Map<String, dynamic> state(int now) => {
      'categories': [
        {'id': 'comics', 'name': 'Comics', 'unit': 'issues', 'minutesPerUnit': 10},
      ],
      'library': [
        for (var i = 0; i < 3; i++) {'id': 't$i', 'title': 'Comic $i', 'categoryId': 'comics', 'status': 'active', 'progress': 1},
      ],
      'sessions': <dynamic>[],
      'settings': <String, dynamic>{},
      'currentTask': {'id': 'task1', 'categoryId': 'comics', 'low': 2, 'high': 4, 'targetMid': 3, 'createdAt': now - 60000},
    };

void main() {
  test('tiers and settings', () {
    const c = GoalXPConfig.defaults;
    double t(double a) => goalTiers(a, 5, 7, c).total;
    expect([t(2), t(5), t(7), t(9), t(40)], [0, 100, 400, 420, 500]);
    final custom = GoalXPConfig.of({
      'mf580GoalXP': {'min': 25, 'max': 75, 'perExtra': 2, 'extraCap': 20},
    });
    expect(goalTiers(9, 5, 7, custom).total, 25 + 75 + 4);
    expect(goalTiers(9, 5, 7, GoalXPConfig.of({'mf580GoalXP': {'enabled': false}})).total, 0);
    expect(goalBounds({'targetMid': 3}), (low: 3, high: 3));
  });

  test('Log any title: once per task, each part paid by the log that reaches it', () {
    final now = DateTime.utc(2026, 11, 14, 12).millisecondsSinceEpoch;
    final s = state(now);
    LogOutcome log(String id, double amount, int at) =>
        applyLog(s, LogRequest.create([LogEntry(libraryId: id, amount: amount, minutes: amount * 10)], now: at));

    expect(log('t0', 1, now).applied, isTrue);
    expect(asList(s['sessions']).where((x) => asMap(x)!['mf580GoalTaskId'] != null), isEmpty, reason: 'below the minimum');

    log('t1', 2, now + 1000); // 3 issues: the minimum (2)
    final first = asList(s['sessions']).map(asMap).firstWhere((x) => x!['mf580GoalTaskId'] == 'task1')!;
    expect(jsNum(first['mf580GoalXP']), 100);
    expect(first['mf580Goal'], {'min': 100, 'max': 0, 'extra': 0, 'low': 2, 'high': 4, 'amount': 3, 'version': 580});
    final l = Leveling(s);
    expect(jsNum(first['streakBaseXP']), jsNum(first['xp']) + 100, reason: 'part of the base XP');
    expect(baseSessionXP(first, l, () => AccountView(s)), jsNum(first['xp']) + 100);

    log('t2', 4, now + 2000); // 7 issues: the maximum (4) and 3 past it
    final paid = [
      for (final x in asList(s['sessions']).map(asMap))
        if (x!['mf580GoalTaskId'] == 'task1') jsNum(x['mf580GoalXP']),
    ];
    expect(paid, [100, 330]);

    log('t0', 20, now + 3000); // the extra is capped at +100: 70 more
    expect(asList(s['sessions']).map(asMap).where((x) => x!['mf580GoalTaskId'] == 'task1').map((x) => jsNum(x!['mf580GoalXP'])),
        [100, 330, 70]);
    log('t1', 5, now + 4000);
    expect(asList(s['sessions']).map(asMap).where((x) => x!['mf580GoalTaskId'] == 'task1').length, 3, reason: 'nothing left to pay');
  });
}
