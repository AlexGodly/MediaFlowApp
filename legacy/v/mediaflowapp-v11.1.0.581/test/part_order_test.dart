// 11.1.0 (website v581): a title's parts can be reordered in Edit title; the
// saved order (parts have no number, like the website's v577 capture) is the
// order Logging and Log any title list them in.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/title_parts.dart';

void main() {
  test('parts follow the saved order', () {
    final item = <String, dynamic>{
      'mf577LogMode': 'parts',
      'seasons': [
        {'id': 'c', 'name': 'Charlie', 'progress': 3, 'number': null},
        {'id': 'd', 'name': 'Delta', 'progress': 4, 'number': null},
        {'id': 'a', 'name': 'Alpha', 'progress': 1, 'number': null},
        {'id': 'b', 'name': 'Bravo', 'progress': 2, 'number': null},
      ],
    };
    expect(titleParts(item).map((p) => p['name']), ['Charlie', 'Delta', 'Alpha', 'Bravo']);
    expect(titleParts(item).map((p) => p['progress']), [3, 4, 1, 2], reason: 'each part keeps its counter');
  });

  test('numbered parts (old data) would sort by number — saving clears them', () {
    final numbered = <String, dynamic>{
      'mf577LogMode': 'parts',
      'seasons': [
        {'id': 'b', 'name': 'Bravo', 'number': 2},
        {'id': 'a', 'name': 'Alpha', 'number': 1},
      ],
    };
    expect(titleParts(numbered).map((p) => p['name']), ['Alpha', 'Bravo']);
    final saved = {
      ...numbered,
      'seasons': [for (final s in numbered['seasons'] as List) {...(s as Map<String, dynamic>), 'number': null}],
    };
    expect(titleParts(saved).map((p) => p['name']), ['Bravo', 'Alpha'], reason: 'the order the user set');
  });
}
