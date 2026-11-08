// External Media IDs: the website's provider list and validation (fixture
// from tool/website_reference/generate_external_id_goldens.mjs), and how an
// edit is saved (v377).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/external_ids.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/external-ids-golden.json').readAsStringSync()) as Map<String, dynamic>;

  test('the website\'s providers', () {
    expect([for (final p in kExternalIdProviders) [p.$1, p.$2, p.$3]], fx['providers']);
  });

  test('validation matches the website', () {
    for (final c in fx['cases'] as List) {
      expect(externalIdValid(c[0] as String, c[1] as String), c[2], reason: '${c[0]} = "${c[1]}"');
    }
  });

  test('changed IDs are saved and remembered as the person\'s choice', () {
    final before = <String, dynamic>{
      'externalIds': {'mal': '1', 'tmdb': '55'},
      'malId': 1,
      'modifiedAt': 10,
    };
    final item = Map<String, dynamic>.of(before);
    expect(applyExternalIdEdits(item, before, {'mal': '', 'tmdb': '55', 'anilist': '154587'}, 20), isNull);
    expect(item['externalIds'], {'tmdb': '55', 'anilist': '154587'});
    expect(item['v377ManualExternalIds'], {'mal': null, 'anilist': '154587'});
    expect(item.containsKey('malId'), isFalse);
    expect(item['modifiedAt'], 20);
    expect(applyExternalIdEdits(Map.of(before), before, {'imdb': 'nope'}, 20), 'Invalid IMDB ID. Please correct it before saving.');
  });
}
