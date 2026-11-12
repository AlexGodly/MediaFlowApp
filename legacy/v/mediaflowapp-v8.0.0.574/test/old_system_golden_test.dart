// The Old System must write exactly what the website writes. Fixtures:
// tool/website_reference/generate_old_system_goldens.mjs runs the website's
// own pages/old-system code (v153 + v173 Date View) action by action.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/records.dart' show jsStringify;
import 'package:mediaflow/src/logic/old_system.dart';

Map<String, dynamic> _copy(Object? v) => (jsonDecode(jsonEncode(v)) as Map).cast<String, dynamic>();

Map<String, Object> _replay(OldSystemReplay r) {
  Map<String, num> round(Map<String, num> m) => {for (final e in m.entries) e.key: (e.value * 1e6).round() / 1e6};
  return {
    'rawTotals': round(r.rawTotals),
    'sessionCounts': round(r.sessionCounts),
    'minuteTotals': round(r.minuteTotals),
    'simulatedBalances': round(r.simulatedBalances),
    'simulatedSpent': round(r.simulatedSpent),
    'activityRows': r.activityRows,
  };
}

void main() {
  final fx = jsonDecode(File('test/fixtures/old-system-golden.json').readAsStringSync()) as Map<String, dynamic>;

  for (final raw in fx['scenarios'] as List) {
    final sc = (raw as Map).cast<String, dynamic>();
    test('old system: ${sc['name']}', () {
      final state = <String, dynamic>{
        'categories': [for (final c in sc['categories'] as List) _copy(c)],
        'sessions': [for (final s in (sc['sessions'] as List? ?? const [])) _copy(s)],
        'oldSystem': sc['oldSystem'] == null ? null : _copy(sc['oldSystem']),
      };
      var n = 0;
      String uid() => 'u${++n}';
      var now = fx['now'] as int;
      final want = (sc['expected'] as Map).cast<String, dynamic>();
      final steps = want['steps'] as List;
      final actions = sc['actions'] as List;
      for (var i = 0; i < actions.length; i++) {
        final a = (actions[i] as Map).cast<String, dynamic>();
        now = (a['at'] as int?) ?? now;
        final ops = OldSystemOps(state, now, uid);
        switch (a['op']) {
          case 'toggle':
            ops.toggleCategory(a['id'] as String);
          case 'addRule':
            ops.addRule();
          case 'updateRule':
            ops.updateRule(a['id'] as String, a['key'] as String, a['value']);
          case 'removeRule':
            ops.removeRule(a['id'] as String);
          case 'setBalance':
            ops.setBalance(a['id'] as String, a['value']);
          case 'consume':
            ops.consume(a['id'] as String, a['amount']);
          case 'undo':
            ops.undo();
          case 'mode':
            ops.setMode(a['mode'] as String);
          case 'date':
            ops.setDate(a['key'] as String, a['value'] as String);
          case 'clearDates':
            ops.clearDates();
        }
        expect(jsStringify(state['oldSystem']), (steps[i] as Map)['oldSystem'], reason: 'after ${a['op']} #$i');
      }
      expect(_replay(replayOldSystem(state)), want['view']);
      expect(_replay(replayOldSystem(state, dateRange: true)), want['dateView']);
    });
  }

  test('quantities read like the website', () {
    expect(fmtOldSystemQty(1234.5678), '1,234.568');
    expect(fmtOldSystemQty(-0.5), '-0.5');
    expect(fmtOldSystemQty(0.00000001), '0');
    expect(fmtOldSystemQty(2.9999), '3');
  });
}
