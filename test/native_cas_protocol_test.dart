import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_edit_proposals.dart';
import 'package:mediaflow_app/services/native_snapshot_codec.dart';

void main() {
  final baseline = <String, dynamic>{
    'library': [
      {'id': 'a', 'title': 'Alpha', 'priority': 'medium', 'status': 'active'},
      {'id': 'b', 'title': 'Beta', 'priority': 'low', 'status': 'planned'},
    ],
    'sessions': [
      {'id': 'log-1', 'status': 'complete', 'xp': 900},
    ],
    'categories': [
      {'id': 'anime', 'name': 'Anime'},
    ],
    'settings': {
      'nestedTheme': {'color': 'custom', 'unchanged': true},
    },
    'orderPlan': {'titleIds': ['a', 'b']},
    'collections': [
      {'id': 'favorites', 'titleIds': ['b']},
    ],
    'xpLedger': {'libraryAdditions': {'a': 1500}},
    'cloudSyncVersion': 410,
    'unknownFutureFeature': {'preserveMe': ['one', 'two']},
  };
  const owner = 'user-test';
  const revision = '2026-10-13T23:59:59.123456+00:00';

  NativeEditProposal edit(
    NativeEditKind kind,
    Map<String, Object?> payload, {
    String account = owner,
    String base = revision,
  }) => NativeEditProposal(
    kind: kind,
    accountId: account,
    baseRevision: base,
    createdAt: DateTime.utc(2026, 10, 13, 23, 59, 59),
    payload: payload,
  );

  NativeCloudRow row(Map<String, dynamic> data, {
    String id = owner,
    String stamp = revision,
  }) => NativeCloudRow(ownerId: id, updatedAt: stamp, stateData: data);

  test('gzip round-trip preserves every unknown v410/future field', () {
    final source = {
      '__mediaflowCompressed': 'gzip',
      'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(baseline)))),
      'outerFutureMetadata': {'flag': true},
    };
    final restored = NativeSnapshotCodec.decode(source);
    expect(NativeSnapshotCodec.equivalent(restored, baseline), isTrue);
    final packed = NativeSnapshotCodec.encodeLike(restored, source);
    expect(packed['outerFutureMetadata'], {'flag': true});
    expect(NativeSnapshotCodec.equivalent(
        NativeSnapshotCodec.decode(packed), baseline), isTrue);
    expect(NativeSnapshotCodec.equivalent(source, packed), isTrue);
  });

  test('local preflight stages only targeted priority on a full gzip state', () {
    final original = {
      '__mediaflowCompressed': 'gzip',
      'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(baseline)))),
    };
    final snapshot = row(original);
    final result = NativeSyncPreflight.prepare(
      row: snapshot,
      proposal: edit(NativeEditKind.setTitlePriority, {
        'titleId': 'a', 'value': 'high',
      }),
    );
    expect(result.isReadyForSimulation, isTrue, reason: result.reason);
    final plan = result.plan!;
    expect(plan.expectedUpdatedAt, revision);
    expect(NativeSnapshotCodec.equivalent(
        plan.expectedStateData, original), isTrue);
    final proposed = NativeSnapshotCodec.decode(plan.proposedStateData);
    final beforeLibrary = baseline['library'] as List;
    final afterLibrary = proposed['library'] as List;
    expect((afterLibrary.first as Map)['priority'], 'high');
    expect((beforeLibrary.first as Map)['priority'], 'medium');
    for (final field in [
      'sessions', 'settings', 'collections', 'xpLedger',
      'cloudSyncVersion', 'unknownFutureFeature', 'orderPlan',
    ]) {
      expect(
        NativeSnapshotCodec.equivalent(proposed[field], baseline[field]),
        isTrue, reason: 'Unexpected mutation in $field',
      );
    }
    // Both exposed raw-payload getters return isolated copies.
    plan.proposedStateData['unexpected'] = 'not persisted';
    expect(plan.proposedStateData.containsKey('unexpected'), isFalse);
  });

  test('simulates two clients racing on the same revision', () {
    final snapshot = row(baseline);
    final first = NativeSyncPreflight.prepare(
      row: snapshot,
      proposal: edit(NativeEditKind.setTitlePriority, {
        'titleId': 'a', 'value': 'high',
      }),
    ).plan!;
    final second = NativeSyncPreflight.prepare(
      row: snapshot,
      proposal: edit(NativeEditKind.setTitlePriority, {
        'titleId': 'b', 'value': 'high',
      }),
    ).plan!;
    expect(NativeCasSimulator.check(
        plan: first, current: snapshot), NativeCasCheck.wouldApply);
    final advanced = row(first.proposedStateData, stamp: 'revision-2');
    expect(NativeCasSimulator.check(
        plan: second, current: advanced), NativeCasCheck.conflict);
    expect(NativeCasSimulator.check(
        plan: first, current: advanced), NativeCasCheck.conflict);
  });

  test('same updated_at but different payload is a conflict', () {
    final staged = NativeSyncPreflight.prepare(
      row: row(baseline),
      proposal: edit(NativeEditKind.setTitlePriority, {
        'titleId': 'a', 'value': 'high',
      }),
    ).plan!;
    final other = NativeSnapshotCodec.deepClone(baseline);
    (other['sessions'] as List).add({'id': 'new-log'});
    expect(
      NativeCasSimulator.check(plan: staged, current: row(other)),
      NativeCasCheck.conflict,
    );
  });

  test('offline/missing/foreign state never turns into a write', () {
    final proposal = edit(NativeEditKind.setTitlePriority,
        {'titleId': 'a', 'value': 'high'});
    final prepared = NativeSyncPreflight.prepare(
      row: row(baseline), proposal: proposal,
    ).plan!;
    expect(NativeCasSimulator.check(plan: prepared, current: null),
        NativeCasCheck.missing);
    expect(NativeCasSimulator.check(
      plan: prepared, current: row(baseline, id: 'another-user')),
      NativeCasCheck.accessDenied);
    expect(NativeSyncPreflight.prepare(
      row: row(baseline, id: 'another-user'), proposal: proposal,
    ).isReadyForSimulation, isFalse);
    expect(NativeSyncPreflight.prepare(
      row: row(baseline, stamp: 'newer'), proposal: proposal,
    ).isReadyForSimulation, isFalse);
    expect(NativeSyncPreflight.prepare(
      row: row({'__mediaflowCompressed': 'gzip', 'data': 'broken'}),
      proposal: proposal,
    ).isReadyForSimulation, isFalse);
    expect(NativeSyncPreflight.prepare(
      row: row({'library': []}), proposal: proposal,
    ).isReadyForSimulation, isFalse);
  });

  test('status side effects are blocked, and a no-op is not staged', () {
    expect(NativeSyncPreflight.prepare(
      row: row(baseline),
      proposal: edit(NativeEditKind.setTitleStatus, {
        'titleId': 'a', 'value': 'completed',
      }),
    ).isReadyForSimulation, isFalse);
    expect(NativeSyncPreflight.prepare(
      row: row(baseline),
      proposal: edit(NativeEditKind.setTitlePriority, {
        'titleId': 'a', 'value': 'medium',
      }),
    ).isReadyForSimulation, isFalse);
  });

  test('personal order reorder preserves saved membership and data', () {
    final plan = NativeSyncPreflight.prepare(
      row: row(baseline),
      proposal: edit(NativeEditKind.reorderPersonalOrder, {
        'titleIds': ['b', 'a'],
      }),
    ).plan!;
    final after = NativeSnapshotCodec.decode(plan.proposedStateData);
    expect((after['orderPlan'] as Map)['titleIds'], ['b', 'a']);
    expect(after['sessions'], baseline['sessions']);
    expect(after['library'], baseline['library']);
    expect(NativeSyncPreflight.prepare(
      row: row(baseline),
      proposal: edit(NativeEditKind.reorderPersonalOrder, {
        'titleIds': ['a'],
      }),
    ).isReadyForSimulation, isFalse);
  });

  test('production write capability remains explicitly disabled', () {
    expect(NativeCloudCapabilities.cloudWritesEnabled, isFalse);
    expect(NativeCloudCapabilities.hasServerSideCas, isFalse);
    expect(NativeCloudCapabilities.offlineWriteQueueEnabled, isFalse);
  });
}
