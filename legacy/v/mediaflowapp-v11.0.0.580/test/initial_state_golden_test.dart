// A new account's first save matches the website's (fixture from
// tool/website_reference/generate_initial_state_goldens.mjs).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/records.dart' show jsStringify;
import 'package:mediaflow/src/logic/initial_state.dart';

void main() {
  test('new account state is the website\'s', () {
    final fx = jsonDecode(File('test/fixtures/initial-state-golden.json').readAsStringSync()) as Map<String, dynamic>;
    expect(jsStringify(newAccountState(fx['now'] as int)), jsStringify(fx['state']));
  });
}
