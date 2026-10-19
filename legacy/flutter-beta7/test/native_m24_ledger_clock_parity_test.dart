// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/services/native_xp_ledger_and_clock_parity.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';

void main() {
  final data = jsonDecode(File('test/fixtures/m24_ledger_clock_vectors.json')
      .readAsStringSync()) as Map<String, dynamic>;

  test('v120 first-time completion reward equals pinned original source', () {
    for (final raw in data['completionLedgers'] as List) {
      final v = Map<String, dynamic>.from(raw as Map);
      final before = Map<String, int>.from(v['existing'] as Map);
      final got = NativeXpLedgerParity.simulate(
        enabled: v['enabled'] as bool,
        configuredCompletionBonusXp: (v['rate'] as num).toDouble(),
        existingLedger: before,
        completedTitleIds: (v['ops'] as List).cast<String>(),
      );
      expect(got.awards, (v['awards'] as List).cast<int>(), reason: v['name'].toString());
      expect(got.projectedLedger, Map<String, int>.from(v['ledger'] as Map));
      expect(before, Map<String, int>.from(v['existing'] as Map));
      expect(got.canCommit, isFalse);
      expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    }
  });

  test('v331 per-title timestamp wins over group timestamp where valid', () {
    for (final raw in data['historyClocks'] as List) {
      final v = Map<String, dynamic>.from(raw as Map);
      final event = NativeHistoryEventClock.eventDate(
        sessionDate: v['sessionDate'] as String,
        sessionTimestamp: DateTime.fromMillisecondsSinceEpoch(
          v['sessionTimestamp'] as int,
        ),
        titleLoggedAt: DateTime.fromMillisecondsSinceEpoch(
          v['rowTimestamp'] as int,
        ),
        now: DateTime.fromMillisecondsSinceEpoch(v['now'] as int),
      );
      expect(event.millisecondsSinceEpoch, v['expected'], reason: v['name'].toString());
    }
  });

  test('zero-amount completion cannot be re-awarded after changing settings', () {
    final first = NativeXpLedgerParity.simulate(
      enabled: true, configuredCompletionBonusXp: 0,
      existingLedger: const {}, completedTitleIds: const ['a'],
    );
    expect(first.awards, [0]);
    expect(first.projectedLedger.containsKey('a'), isTrue);
    final second = NativeXpLedgerParity.simulate(
      enabled: true, configuredCompletionBonusXp: 100,
      existingLedger: first.projectedLedger,
      completedTitleIds: const ['a'],
    );
    expect(second.awards, [0]);
    expect(second.projectedLedger['a'], 0);
  });

  test('100k ledger baseline remains unmodified by synthetic planning', () {
    final before = {for (var i=0; i<100000; i++) 'title-' + i.toString(): i % 6};
    final timer = Stopwatch()..start();
    final got = NativeXpLedgerParity.simulate(
      enabled: true, configuredCompletionBonusXp: 25,
      existingLedger: before,
      completedTitleIds: const ['title-99999','new-title','new-title'],
    );
    expect(got.awards, [0,25,0]);
    expect(got.projectedLedger['new-title'], 25);
    expect(before.containsKey('new-title'), false);
    expect(before.length, 100000);
    // ignore: avoid_print
    print('M24_100K_LEDGER_MS=' + timer.elapsedMilliseconds.toString());
  }, timeout: const Timeout(Duration(minutes: 2)));
}
