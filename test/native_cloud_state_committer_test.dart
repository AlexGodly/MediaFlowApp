import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_full_state.dart';
import 'package:mediaflow_app/services/native_cloud_state_committer.dart';

void main() {
  Map<String, Object?> state({
    required double progress,
    bool includeFutureField = true,
  }) => {
    'library': [
      {'id': 'title-1', 'progress': progress},
    ],
    'categories': <Object?>[],
    'sessions': <Object?>[],
    'settings': <String, Object?>{},
    if (includeFutureField) 'futureWebsiteField': {'preserve': true},
  };

  test('allows a complete changed payload while preserving unknown fields', () {
    final before = MediaFlowFullState.parse(state(progress: 2));
    final after = MediaFlowFullState.parse(state(progress: 3));

    expect(
      () => NativeCloudStateCommitter.validatePreservation(before, after),
      returnsNormally,
    );
  });

  test('rejects a payload that drops an unknown website root', () {
    final before = MediaFlowFullState.parse(state(progress: 2));
    final after = MediaFlowFullState.parse(
      state(progress: 3, includeFutureField: false),
    );

    expect(
      () => NativeCloudStateCommitter.validatePreservation(before, after),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects changing the original wire format', () {
    final objectState = state(progress: 2);
    final before = MediaFlowFullState.parse(objectState);
    final after = MediaFlowFullState.parse(
      '{"library":[{"id":"title-1","progress":3}],'
      '"categories":[],"sessions":[],"settings":{},'
      '"futureWebsiteField":{"preserve":true}}',
    );

    expect(
      () => NativeCloudStateCommitter.validatePreservation(before, after),
      throwsA(isA<FormatException>()),
    );
  });
}
