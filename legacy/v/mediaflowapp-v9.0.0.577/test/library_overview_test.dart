// Library Overview numbers match the website (fixtures from
// tool/website_reference/generate_library_overview_goldens.mjs).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/library_overview.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/library-overview-golden.json').readAsStringSync()) as Map<String, dynamic>;
  final cats = [for (final c in fx['categories'] as List) (c as Map).cast<String, dynamic>()];
  for (final e in (fx['cases'] as Map).entries) {
    test('library overview: ${e.key}', () {
      final c = (e.value as Map).cast<String, dynamic>();
      final want = (c['expected'] as Map).cast<String, dynamic>();
      final ov = libraryOverview({'categories': cats, 'library': c['library']}, categories: cats);
      expect(ov.overallPct, want['overallPct']);
      expect(ov.totalAll, want['totalAll']);
      final rows = want['rows'] as List;
      for (var i = 0; i < rows.length; i++) {
        final w = (rows[i] as Map).cast<String, dynamic>(), r = ov.rows[i];
        final got = {
          'id': r.id, 'items': r.items, 'done': r.done, 'knownDone': r.knownDone, 'total': r.total,
          'unknown': r.unknown, 'pct': r.pct, 'estimated': r.estimated,
        };
        expect(got, w, reason: w['id'] as String);
      }
    });
  }

  test('labels read like the website', () {
    final cats = <Map<String, dynamic>>[{'id': 'a', 'target': 1}, {'id': 'b'}];
    final ov = libraryOverview({
      'library': [
        {'categoryId': 'a', 'progress': 3, 'total': 12},
        {'categoryId': 'b', 'progress': 2},
      ],
    }, categories: cats);
    expect(ov.rows[0].label, '3 / 12 (25%)');
    expect(ov.rows[1].label, '2 / ≈12 (~17%)');
    expect(libraryOverview({'library': []}, categories: cats).rows[0].label, '0 / -');
  });
}
