// 8.0.0.573: Batch Log can set the exact time of a log (website v573).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/util/js.dart';

Map<String, dynamic> _account() {
  final fx = jsonDecode(File('test/fixtures/log-mixed-batch.json').readAsStringSync()) as Map;
  return deepCopyState((fx['before'] as Map).cast<String, dynamic>());
}

void main() {
  final now = DateTime(2026, 11, 12, 22, 30).millisecondsSinceEpoch;

  test('date + time, never in the future', () {
    expect(logTimeMs('2026-11-10', '08:15', now), DateTime(2026, 11, 10, 8, 15).millisecondsSinceEpoch);
    expect(logTimeMs('2026-11-12', '23:59', now), now, reason: 'later today: clamped to now');
    expect(logTimeMs('2026-11-10', null, now), isNull);
    expect(logTimeMs('2026-11-10', '25:00', now), isNull);
    expect(logTimeMs('2026-11-10', 'x', now), isNull);
  });

  test('the log is saved at that time, and the time survives a replay', () {
    final s = _account();
    final title = asList(s['library']).map(asMap).firstWhere((i) => jsStr(i!['status']) != 'completed' && (jsNum(i['total']) == 0 || jsNum(i['progress']) < jsNum(i['total'])))!;
    final req = LogRequest(
      entries: [LogEntry(libraryId: jsStr(title['id']), amount: 1, minutes: 20)],
      createdAt: now,
      date: '2026-11-10',
      time: '08:15',
      sessionIds: const ['s_time'],
      groupId: 'g_time',
      eventId: 'e_time',
    );
    final back = LogRequest.fromJson(jsonDecode(jsonEncode(req.toJson())) as Map<String, dynamic>);
    expect(back.time, '08:15');
    expect(applyLog(s, back).applied, isTrue);
    final session = asList(s['sessions']).map(asMap).firstWhere((x) => jsStr(x!['id']) == 's_time')!;
    final at = DateTime(2026, 11, 10, 8, 15).millisecondsSinceEpoch;
    expect(session['timestamp'], at);
    expect(session['date'], '2026-11-10');
    expect(asMap(asList(session['titles']).first)!['loggedAt'], at);
  });
}
