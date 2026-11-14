// 10.0.0: another device's records applied to the device's own copy give
// exactly what rebuilding the account from all records gives.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/records.dart';

Map<String, dynamic> _state() => {
      'categories': [{'id': 'c', 'name': 'C'}],
      'library': [for (var i = 0; i < 50; i++) {'id': 't$i', 'title': 'Title $i', 'progress': i}],
      'sessions': [for (var i = 0; i < 20; i++) {'id': 's$i', 'minutes': i}],
      'settings': {'theme': 'dark', 'tasksPerDay': 5},
      'savedAt': 1,
    };

RecordIndex _index(Map<String, Rec> recs) =>
    RecordIndex(entries: {for (final r in recs.values) r.key: (r.pos, recHash(r.j, r.pos))}, cursor: 'x');

void main() {
  test('patching equals rebuilding', () {
    final base = _state();
    final recs = decomposeState(base, (_) => null);
    final display = composeState(recs.values);
    expect(jsonEncode(display), jsonEncode(base));

    // Another device: edits a title, deletes a log, adds a title between two
    // others, edits a setting and savedAt.
    final rows = <RecordRow>[];
    void put(String k, String i, double? pos, Object value) {
      final j = jsStringify(value);
      recs[recordKey(k, i)] = Rec(k, i, pos, j);
      rows.add(RecordRow(kind: k, recordId: i, pos: pos, data: j));
    }

    final p5 = recs[recordKey('library', 't5')]!.pos;
    put('library', 't5', p5, {'id': 't5', 'title': 'Renamed', 'progress': 99});
    final p10 = recs[recordKey('library', 't10')]!.pos!, p11 = recs[recordKey('library', 't11')]!.pos!;
    put('library', 'new', (p10 + p11) / 2, {'id': 'new', 'title': 'Added elsewhere'});
    final p20 = recs[recordKey('library', 't20')]!.pos!;
    put('library', 't3', p20 + 1, {'id': 't3', 'title': 'Moved', 'progress': 3});
    recs.remove(recordKey('sessions', 's7'));
    rows.add(RecordRow(kind: 'sessions', recordId: 's7', deleted: true));
    put('doc', 'settings\u001ftheme', null, 'light');
    put('doc', 'savedAt', null, 2);

    final index = _index(recs);
    final expected = composeState(recs.values);
    expect(patchState(display, rows, index), isTrue);
    expect(jsonEncode(display), jsonEncode(expected));
  });

  test('key-list changes are not patched', () {
    final display = _state();
    final recs = decomposeState(display, (_) => null);
    final row = RecordRow(kind: 'doc', recordId: 'settings\u001fnewKey', data: '1');
    expect(patchState(display, [row], _index(recs)), isFalse, reason: 'a new key also changes the key list');
    expect(rowPatchable(RecordRow(kind: 'doc', recordId: '__keys', data: '[]')), isFalse);
    expect(rowPatchable(RecordRow(kind: 'doc', recordId: 'settings\u001f', data: '[]')), isFalse);
  });
}
