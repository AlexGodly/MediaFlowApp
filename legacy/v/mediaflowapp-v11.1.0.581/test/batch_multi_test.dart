// 8.2.0.576: Log any title with several titles is one Batch Log (website
// submitBatchLog with several rows), and its preview is what saving earns.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/logic/log_xp_preview.dart';
import 'package:mediaflow/src/logic/stats.dart' show xpMetrics;
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/util/js.dart';

Map<String, dynamic> _account() {
  final fx = jsonDecode(File('test/fixtures/log-mixed-batch.json').readAsStringSync()) as Map;
  return deepCopyState((fx['before'] as Map).cast<String, dynamic>());
}

void main() {
  test('several titles: one log, one Batch Log bonus, preview = award', () {
    final s = _account();
    final titles = asList(s['library'])
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .where((i) => jsStr(i['status']) != 'completed' && (jsNum(i['total']) == 0 || jsNum(i['progress']) + 2 < jsNum(i['total'])))
        .take(2)
        .toList();
    expect(titles.length, 2);
    final req = LogRequest(
      entries: [
        LogEntry(libraryId: jsStr(titles[0]['id']), amount: 1, minutes: 20),
        LogEntry(libraryId: jsStr(titles[1]['id']), amount: 2, minutes: 45),
      ],
      createdAt: DateTime.utc(2026, 11, 13, 12).millisecondsSinceEpoch,
      sessionIds: const ['m1', 'm2'],
      groupId: 'g_multi',
      eventId: 'e_multi',
    );
    final preview = previewLogXp(s, req);
    final before = xpMetrics(s).total;
    final events0 = (asMap(asMap(s['xpLedger'])?['v348ActionEvents']) ?? const {}).length;
    expect(applyLog(s, req).applied, isTrue);
    expect(preview, xpMetrics(s).total - before);
    final added = asList(s['sessions']).map(asMap).where((x) => jsStr(x?['batchGroupId']) == 'g_multi').toList();
    expect(added.length, 2, reason: 'one session per title, in one batch');
    final events = (asMap(asMap(s['xpLedger'])?['v348ActionEvents']) ?? const {}).length;
    expect(events - events0, 1, reason: 'the Batch Log bonus once per log');
  });
}
