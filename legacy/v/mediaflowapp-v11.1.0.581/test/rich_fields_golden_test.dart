// The title editor's rich fields save like the website (fixtures from
// tool/website_reference/generate_rich_fields_goldens.mjs).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/records.dart' show jsStringify;
import 'package:mediaflow/src/logic/rich_fields.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/rich-fields-golden.json').readAsStringSync()) as Map<String, dynamic>;
  const ids = {
    'year': 'l-rich-year', 'mediaFormat': 'l-rich-format', 'durationMinutes': 'l-rich-duration', 'releaseDate': 'l-rich-release-date',
    'seasonLabel': 'l-rich-season', 'ageRating': 'l-rich-age-rating', 'communityScore': 'l-rich-community-score', 'mediaSource': 'l-rich-source',
    'demographic': 'l-rich-demographic', 'studios': 'l-rich-studios', 'producers': 'l-rich-producers', 'genres': 'l-rich-genres',
    'themes': 'l-rich-themes', 'synopsis': 'l-rich-synopsis',
  };

  test('the same fields as the website', () => expect(kRichFields, fx['fields']));

  for (final raw in fx['cases'] as List) {
    final c = (raw as Map).cast<String, dynamic>();
    test('rich fields: ${c['name']}', () {
      final inputs = (c['inputs'] as Map).cast<String, dynamic>();
      final captured = captureRich({for (final e in ids.entries) e.key: '${inputs[e.value] ?? ''}'});
      final want = (c['expected'] as Map).cast<String, dynamic>();
      expect(jsStringify(captured), jsStringify(want['captured']));
      final item = (jsonDecode(jsonEncode(c['item'])) as Map).cast<String, dynamic>();
      final before = (jsonDecode(jsonEncode(c['item'])) as Map).cast<String, dynamic>();
      expect(applyRichEditorValues(item, before, captured, 1762600000000), want['changed']);
      expect(jsStringify(item), jsStringify(want['item']));
    });
  }

  test('a saved title fills the fields back', () {
    expect(richFieldText({'genres': ['A', 'B']}, 'genres'), 'A, B');
    expect(richFieldText({'communityScore': 8.5}, 'communityScore'), '8.5');
    expect(richFieldText({'year': null}, 'year'), '');
  });
}
