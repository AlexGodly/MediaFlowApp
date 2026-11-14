import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/state/state_codec.dart';
import 'package:mediaflow/src/util/js.dart';

void main() {
  test('reads the compressed format the website writes', () {
    final fx = jsonDecode(File('test/fixtures/website-compressed-state.json').readAsStringSync()) as Map;
    final decoded = decodeStateData(fx['state_data']);
    expect(jsonEncode(decoded), jsonEncode(fx['state']));
  });

  test('writes a format it can read back', () {
    final state = {'library': [{'id': 'a', 'title': 'Ünïcödé ✓', 'progress': 3}], 'sessions': []};
    final encoded = encodeStateData(state);
    expect(encoded['__mediaflowCompressed'], 'gzip');
    expect(decodeStateData(encoded), state);
  });

  test('accepts uncompressed legacy rows', () {
    expect(decodeStateData({'library': [], 'x': 1})['x'], 1);
  });

  test('JavaScript number semantics', () {
    expect(jsRound(2.5), 3);
    expect(jsRound(-2.5), -2);
    expect(jsNum(null), 0);
    expect(jsNum('12'), 12);
    expect(jsNum('abc'), 0);
    expect(jsOut(5.0), isA<int>());
    expect(jsOut(1.16), 1.16);
    expect(isoDateUtc(1793433600000), '2026-10-31');
    expect(shiftDayKey('2026-03-01', -1), '2026-02-28');
    expect(cleanTitle('  <![CDATA[Frieren]]> '), 'Frieren');
    expect(RegExp(r'^id_[0-9a-z]+_[0-9a-z]{6}$').hasMatch(mediaFlowUid()), isTrue);
  });
}
