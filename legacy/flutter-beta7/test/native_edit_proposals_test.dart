import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/services/native_edit_proposals.dart';

void main() {
  final baseline = {
    'library': [
      {'id': 'a', 'title': 'Alpha', 'priority': 'medium', 'status': 'active'},
      {'id': 'b', 'title': 'Beta', 'priority': 'high', 'status': 'planned'},
    ],
    'orderPlan': {'titleIds': ['a', 'b']},
    'sessions': [{'id': 'history', 'xp': 900}],
    'settings': {'custom': {'doNotTouch': true}},
  };
  NativeEditProposal proposal(NativeEditKind kind, Map<String, Object?> payload,
      {String revision = 'rev-1', String user = 'owner'}) => NativeEditProposal(
    kind: kind, accountId: user, baseRevision: revision,
    createdAt: DateTime.now().toUtc(), payload: payload,
  );
  NativeEditPreview apply(NativeEditProposal edit) => previewNativeEdit(
    state: baseline, accountId: 'owner', revision: 'rev-1', proposal: edit,
  );

  test('Valid priority preview changes a copy and preserves unrelated fields', () {
    final before = jsonEncode(baseline);
    final result = apply(proposal(NativeEditKind.setTitlePriority,
        {'titleId': 'a', 'value': 'high'}));
    expect(result.valid, isTrue);
    final library = result.updatedState!['library'] as List;
    expect((library.first as Map)['priority'], 'high');
    expect(jsonEncode(baseline), before);
    expect(result.updatedState!['sessions'], baseline['sessions']);
    expect(result.updatedState!['settings'], baseline['settings']);
  });

  test('Rejects stale revisions and other accounts', () {
    expect(apply(proposal(NativeEditKind.setTitleStatus,
        {'titleId': 'a', 'value': 'completed'}, revision: 'stale')).valid, isFalse);
    expect(apply(proposal(NativeEditKind.setTitleStatus,
        {'titleId': 'a', 'value': 'completed'}, user: 'other')).valid, isFalse);
  });

  test('Reorder preserves exact membership, no duplicates or deletions', () {
    final valid = apply(proposal(NativeEditKind.reorderPersonalOrder,
        {'titleIds': ['b', 'a']}));
    expect(valid.valid, isTrue);
    expect((valid.updatedState!['orderPlan'] as Map)['titleIds'], ['b','a']);
    expect(apply(proposal(NativeEditKind.reorderPersonalOrder,
        {'titleIds': ['a']})).valid, isFalse);
    expect(apply(proposal(NativeEditKind.reorderPersonalOrder,
        {'titleIds': ['a', 'a']})).valid, isFalse);
  });

  test('Unknown titles and invalid status are rejected', () {
    expect(apply(proposal(NativeEditKind.setTitleStatus,
        {'titleId': 'unknown', 'value': 'completed'})).valid, isFalse);
    expect(apply(proposal(NativeEditKind.setTitleStatus,
        {'titleId': 'a', 'value': 'hacked'})).valid, isFalse);
  });

  test('Edit proposal survives JSON serialization', () {
    final original = proposal(NativeEditKind.setTitlePriority,
        {'titleId': 'b', 'value': 'low'});
    final restored = NativeEditProposal.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(original.toJson())) as Map));
    expect(restored.kind, original.kind);
    expect(restored.baseRevision, 'rev-1');
    expect(restored.payload['titleId'], 'b');
  });
}
