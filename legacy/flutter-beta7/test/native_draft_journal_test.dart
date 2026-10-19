import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/features/settings/draft_sandbox_panel.dart';
import 'package:mediaflow_app/services/native_cas_protocol.dart';
import 'package:mediaflow_app/services/native_draft_journal.dart';
import 'package:mediaflow_app/services/native_edit_proposals.dart';
import 'package:mediaflow_app/services/native_snapshot_codec.dart';

void main() {
  const owner = 'test-account';
  const revision = '2026-10-14T00:00:00.000000+00:00';
  final original = <String, dynamic>{
    'library': [
      {'id': 'first', 'priority': 'low', 'title': 'First'},
      {'id': 'second', 'priority': 'low', 'title': 'Second'},
    ],
    'sessions': [
      {'id': 'log', 'xp': 300},
    ],
    'categories': [
      {'id': 'anime', 'name': 'Anime'},
    ],
    'settings': {'theme': 'dark'},
    'xpLedger': {'total': 300},
    'futureField': {'untouched': true},
  };

  NativeDraftEntry draft(String id, String title, String value, {
    String account = owner,
    String base = revision,
  }) => NativeDraftEntry(
    operationId: id,
    proposal: NativeEditProposal(
      kind: NativeEditKind.setTitlePriority,
      accountId: account,
      baseRevision: base,
      createdAt: DateTime.utc(2026, 10, 14),
      payload: {'titleId': title, 'value': value},
    ),
  );

  NativeCloudRow row({String stamp = revision}) =>
      NativeCloudRow(ownerId: owner, updatedAt: stamp, stateData: original);

  test('two local drafts combine into one immutable full-state CAS preview', () {
    final journal = NativeDraftJournal(accountId: owner);
    journal.add(draft('one', 'first', 'high'));
    journal.add(draft('two', 'second', 'medium'));
    final result = journal.preview(row());
    expect(result.isValid, isTrue, reason: result.reason);
    final updated = NativeSnapshotCodec.decode(
      result.plan!.proposedStateData,
    );
    expect((updated['library'] as List).map((item) =>
        (item as Map)['priority']).toList(), ['high', 'medium']);
    for (final key in ['sessions', 'categories', 'settings', 'xpLedger',
      'futureField']) {
      expect(NativeSnapshotCodec.equivalent(updated[key], original[key]),
          isTrue, reason: 'Changed $key');
    }
    expect(NativeSnapshotCodec.equivalent(original, row().stateData), isTrue);
  });

  test('newer cloud revision quarantines the entire batch', () {
    final journal = NativeDraftJournal(accountId: owner);
    journal.add(draft('one', 'first', 'high'));
    final result = journal.preview(row(stamp: 'another-revision'));
    expect(result.isValid, isFalse);
    expect(result.reason, contains('revision'));
    expect(journal.entries.length, 1);
  });

  test('invalid second draft cannot partially commit the first', () {
    final journal = NativeDraftJournal(accountId: owner);
    journal.add(draft('one', 'first', 'high'));
    journal.add(draft('two', 'does-not-exist', 'medium'));
    expect(journal.preview(row()).isValid, isFalse);
    expect(original['library'], isNotEmpty);
  });

  test('rejects account crossover, duplicate IDs and mixed revisions', () {
    final journal = NativeDraftJournal(accountId: owner);
    expect(() => journal.add(draft('foreign', 'first', 'high',
        account: 'other')), throwsStateError);
    journal.add(draft('one', 'first', 'high'));
    expect(() => journal.add(draft('one', 'second', 'medium')),
        throwsStateError);
    expect(() => journal.add(draft('new', 'second', 'medium',
        base: 'newer')), throwsStateError);
    expect(journal.entries.length, 1);
    expect(journal.discard('one'), isTrue);
    expect(journal.discard('one'), isFalse);
    expect(journal.entries, isEmpty);
  });

  test('draft export requires exact signed-in account', () {
    final journal = NativeDraftJournal(accountId: owner);
    journal.add(draft('one', 'first', 'high'));
    final encoded = NativeDraftFormat.encode(journal);
    expect(NativeDraftFormat.decode(encoded, owner).entries.length, 1);
    expect(() => NativeDraftFormat.decode(encoded, 'other'),
        throwsFormatException);
    expect(() => NativeDraftFormat.decode('{"format":"wrong"}', owner),
        throwsFormatException);
  });

  test('repeated identical change is blocked as no-op, never uploaded', () {
    final journal = NativeDraftJournal(accountId: owner);
    journal.add(draft('one', 'first', 'high'));
    journal.add(draft('two', 'first', 'high'));
    expect(journal.preview(row()).isValid, isFalse);
  });

  testWidgets('synthetic Settings lab previews and detects a conflict',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: DraftSandboxPanel()),
    )));
    expect(find.textContaining('Synthetic sample data'), findsOneWidget);
    await tester.tap(find.text('Stage demo change'));
    await tester.pump();
    await tester.tap(find.text('Test local preview'));
    await tester.pump();
    expect(find.textContaining('Local simulation succeeded'), findsOneWidget);
    await tester.tap(find.text('Simulate cloud conflict'));
    await tester.pump();
    await tester.tap(find.text('Test local preview'));
    await tester.pump();
    expect(find.textContaining('Cloud revision changed'), findsOneWidget);
    await tester.tap(find.text('Discard drafts'));
    await tester.pump();
    expect(find.textContaining('All synthetic drafts discarded'),
        findsOneWidget);
  });
}
