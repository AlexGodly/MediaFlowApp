// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_library_repository.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/settings/native_xp_ledger_audit_panel.dart';
import 'package:mediaflow_app/services/native_action_xp_parity.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_offline_projection_codec.dart';

class TestRepository extends MediaFlowLibraryRepository {
  TestRepository(this.catalog);
  final MediaFlowCatalog catalog;
  @override
  Future<MediaFlowCatalog> load() async => catalog;
}

void main() {
  final data = jsonDecode(
    File('test/fixtures/m25_action_xp_vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  MediaFlowXpEvidence settings(Object? leveling, {Object? ledgers}) =>
      MediaFlowXpEvidence.fromState({
        'settings': {'leveling': leveling},
        'xpLedger': ledgers ?? {},
      });

  test('pinned v348 original JavaScript and Dart action vectors agree', () {
    for (final raw in data['actions'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final evidence = settings(row['leveling']);
      final actual = NativeActionXpParity.action(
        settings: evidence, kind: row['kind'] as String,
        amount: (row['amount'] as num).toDouble(),
        streak: row['streak'] as int,
      );
      expect(NativeActionXpParity.rate(evidence, actual.kind),
          row['expectedRate'], reason: row['name'].toString());
      expect(actual.streakMultiplier, row['expectedMultiplier'],
          reason: row['name'].toString());
      expect(actual.provisionalXp, row['expectedXp'],
          reason: row['name'].toString());
      expect(actual.canCommit, isFalse);
      expect(actual.mayAward, isFalse);
    }
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, isFalse);
  });

  test('v348RaiseNewRewards only increases NEW fixed rewards', () {
    for (final raw in data['increments'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final result = NativeActionXpParity.extraForNewFixedReward(
        settings: settings(row['leveling']),
        before: (row['before'] as num).toDouble(),
        after: (row['after'] as num).toDouble(),
        streak: row['streak'] as int,
      );
      expect(result, row['expectedExtra'], reason: row['name'].toString());
    }
  });

  test('only 3 v348 bonus ledgers count, not completion XP again', () {
    final entry = Map<String, dynamic>.from(
        (data['ledgerExtras'] as List).first as Map);
    final evidence = settings({}, ledgers: entry['ledger']);
    expect(evidence.knownExtraXp, entry['expected']);
    expect(NativeActionXpParity.knownExtraXp(evidence), 25.5);
    expect(evidence.actionEventCount, 2);
    expect(evidence.ledgerCounts['logCompletions'], 1);
    expect(evidence.invalidLedgerValues, 0);
    expect(evidence.completeAccountXp, isFalse);
    expect(evidence.canWrite, isFalse);
  });

  test('defensively validate malformed settings, huge and invalid ledgers', () {
    final sample = MediaFlowXpEvidence.fromState({
      'settings': {'leveling': {'enabled': false,
        'globalStreakMultiplierEnabled': false,
        'batchLogXP': -23,
        'orderAddTitleXP': 700000,
        'collectionAddTitleXP': 'NaN'}},
      'xpLedger': {
        'v348ActionEvents': {'bad':'nope','infinity':'Infinity',
          'negative':-100,'valid':4},
        'v348LibraryAdditionBonus': ['untrusted', 1],
      },
    });
    expect(NativeActionXpParity.rate(sample, 'batchLogXP'), 0);
    expect(NativeActionXpParity.rate(sample, 'orderAddTitleXP'), 100000);
    expect(NativeActionXpParity.rate(sample, 'collectionAddTitleXP'), 8);
    expect(sample.invalidLedgerValues, 3);
    expect(sample.knownExtraXp, 4);
    expect(() => NativeActionXpParity.rate(sample, 'unknown'),
        throwsFormatException);
    expect(() => NativeActionXpParity.action(
      settings: sample, kind: 'batchLogXP',
      amount: double.nan, streak: 1,
    ), throwsFormatException);
    expect(() => NativeActionXpParity.extraForNewFixedReward(
      settings: sample, before: double.infinity,
      after: 5, streak: 1,
    ), throwsFormatException);
  });

  test('cloud read-only extraction and encrypted projection retain summaries',
      () {
    final rawState = {
      'categories': <Object>[], 'library': <Object>[],
      'settings': {'leveling': {
        'enabled': true, 'globalStreakMultiplierEnabled': false,
        'orderAddTitleXP': -19,
      }},
      'xpLedger': {
        'v348ActionEvents': {'a':10,'b':3},
        'v348LibraryAdditionBonus': {'c':7},
        'v348LibraryCompletionBonus': {'d':4},
        'logCompletions': {'e':45},
      },
    };
    final catalog = decodeMediaFlowState(rawState);
    expect(catalog.xpEvidence?.knownExtraXp, 24);
    final projected = NativeOfflineProjectionCodec.encode(catalog);
    final restored = NativeOfflineProjectionCodec.decode(projected);
    final xp = restored.xpEvidence!;
    expect(xp.settingsPresent, true);
    expect(xp.globalStreakEnabled, false);
    expect(NativeActionXpParity.rate(xp, 'orderAddTitleXP'), 0);
    expect(xp.knownExtraXp, 24);
    expect(xp.ledgerCounts['logCompletions'], 1);
    final json = jsonEncode(projected);
    expect(json, isNot(contains('logCompletions":{"e"')));
    expect(json, isNot(contains('"v348ActionEvents":{"a"')));
    expect(xp.canWrite, isFalse);
  });

  test('100000 XP event keys compress to bounded summary without mutation',
      () {
    final values = {for (var i = 0; i < 100000; i++)
      'action-' + i.toString(): 1};
    final state = {
      'settings': {'leveling': {'enabled': true}},
      'xpLedger': {'v348ActionEvents': values},
    };
    final clock = Stopwatch()..start();
    final evidence = MediaFlowXpEvidence.fromState(state);
    expect(evidence.knownExtraXp, 100000);
    expect(evidence.actionEventCount, 100000);
    expect(values.length, 100000);
    expect(values['action-99999'], 1);
    expect(jsonEncode(evidence.toProjection()).length, lessThan(2000));
    expect(evidence.canWrite, false);
    // ignore: avoid_print
    print('M25_100K_LEDGER_AUDIT_MS=' + clock.elapsedMilliseconds.toString());
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('Settings reads XP evidence and never offers save or award',
      (tester) async {
    final catalog = decodeMediaFlowState({
      'library': <Object>[], 'categories': <Object>[],
      'settings': {'leveling': {'enabled': true}},
      'xpLedger': {'v348ActionEvents': {'event':9}},
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SingleChildScrollView(child: NativeXpLedgerAuditPanel(
        repository: TestRepository(catalog),
      )),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Native XP & ledger audit'), findsOneWidget);
    expect(find.textContaining('Known v348 bonus ledger total: 9.0'),
        findsOneWidget);
    expect(find.byKey(const Key('native-xp-action')), findsOneWidget);
    expect(find.byKey(const Key('native-xp-hypothetical')), findsOneWidget);
    expect(find.textContaining('NOT total account XP'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Award XP'), findsNothing);
  });
}
