// The app's per-record storage must write exactly the rows the website writes.
// Fixtures: tool/website_reference/generate_record_goldens.mjs runs the
// website's own v556 code (mf556Decompose / Compose / Positions / Hash).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/records.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/records-golden.json').readAsStringSync()) as Map<String, dynamic>;
  final state1 = (fx['state1'] as Map).cast<String, dynamic>();
  final state2 = (fx['state2'] as Map).cast<String, dynamic>();

  List<Map<String, Object?>> rows(Map<String, Rec> recs) => [
        for (final r in recs.values) {'k': r.k, 'i': r.i, 'pos': r.pos, 'j': r.j, 'h': recHash(r.j, r.pos)},
      ];
  List<Map<String, Object?>> want(String name) => [
        for (final r in fx[name] as List)
          {
            'k': r['k'],
            'i': r['i'],
            'pos': r['pos'] is num ? (r['pos'] as num).toDouble() : null,
            'j': r['j'],
            'h': r['h'],
          },
      ];

  test('hashes match the website', () {
    for (final pair in fx['hashes'] as List) {
      expect(recordHash(pair[0] as String), pair[1], reason: 'hash of ${(pair[0] as String).length} chars');
    }
  });

  test('positions match the website', () {
    for (final c in fx['positions'] as List) {
      final prev = (c['prev'] as Map).map((k, v) => MapEntry('$k', (v as num).toDouble()));
      final got = recordPositions((c['ids'] as List).cast<String>(), prev);
      expect(got, [for (final v in c['out'] as List) (v as num).toDouble()], reason: '${c['ids']}');
    }
  });

  test('a new account gives exactly the website\'s records', () {
    final got = rows(decomposeState(state1, (_) => null));
    expect(got, want('records1'));
  });

  test('after edits, records keep positions and match the website', () {
    final first = decomposeState(state1, (_) => null);
    final got = rows(decomposeState(state2, (key) => first[key]?.pos));
    expect(got, want('records2'));
  });

  test('records rebuild the account exactly', () {
    final recs = decomposeState(state2, (_) => null);
    expect(jsStringify(composeState(recs.values)), jsStringify(state2));
    final fromWebsite = [
      for (final r in fx['records2'] as List)
        Rec(r['k'] as String, r['i'] as String, r['pos'] is num ? (r['pos'] as num).toDouble() : null, r['j'] as String),
    ];
    expect(jsStringify(composeState(fromWebsite.reversed)), jsStringify(state2));
  });

  test('JSON text like JavaScript', () {
    expect(jsStringify({'a': 1.0, 'b': 2.5, 'c': -0.0, 'd': double.nan, 'e': [1e21, 1e-7], 'f': 'é"\n'}),
        '{"a":1,"b":2.5,"c":0,"d":null,"e":[1e+21,1e-7],"f":"é\\"\\n"}');
  });

  test('missing key list is reported, not guessed', () {
    expect(() => composeState([const Rec('library', 'x', 0, '{}')]), throwsA(isA<IncompleteRecords>()));
  });
}
