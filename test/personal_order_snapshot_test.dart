import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';

void main() {
  test('Personal Order preserves saved title order and removes duplicates', () {
    final state = decodeMediaFlowState({
      'library': [{'id': 'a', 'title': 'Alpha'}, {'id': 'b', 'title': 'Beta'}],
      'orderPlan': {'titleIds': ['b', 'a', 'b', 'missing']},
    });
    expect(state.personalOrderIds, ['b', 'a', 'missing']);
  });

  test('Missing orderPlan uses empty native order', () {
    expect(decodeMediaFlowState({'library': []}).personalOrderIds, isEmpty);
  });

  test('Malformed orderPlan IDs are rejected', () {
    expect(() => decodeMediaFlowState({
      'orderPlan': {'titleIds': 'invalid'},
    }), throwsFormatException);
  });
}
