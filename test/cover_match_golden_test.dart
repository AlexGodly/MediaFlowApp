// Cover Recovery matches titles like the website (v424 mf424Match): every
// name a provider record has is compared, and the confidences are the
// website's. Fixtures: tool/website_reference/generate_cover_match_goldens.mjs.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/recovery.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/cover-match-golden.json').readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> m(Object? v) => (v as Map).cast<String, dynamic>();

  test('names are normalized like the website', () {
    for (final pair in fx['normalize'] as List) {
      expect(coverNorm(pair[0]), pair[1], reason: '${pair[0]}');
    }
  });

  test('every name a record carries is compared', () {
    final records = m(fx['records']);
    for (final e in m(fx['titles']).entries) {
      expect(coverRecordTitles(m(records[e.key])), e.value, reason: e.key);
    }
  });

  test('confidences and reasons match the website', () {
    final items = m(fx['items']), records = m(fx['records']);
    for (final raw in fx['matches'] as List) {
      final c = m(raw);
      final got = coverMatch(m(items[c['item']]), m(records[c['record']]), c['idMatch'] as bool);
      final want = m(c['expected']);
      expect({'confidence': got.confidence, 'reason': got.reason}, {'confidence': (want['confidence'] as num).toDouble(), 'reason': want['reason']},
          reason: '${c['item']} × ${c['record']} (id: ${c['idMatch']})');
    }
  });
}
