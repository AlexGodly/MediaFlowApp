// Beta 14's account edits must change the account exactly like the real
// MediaFlow website does. Fixtures are recorded from the website itself
// (tool/website_reference/generate_edit_goldens.py). Run with TZ=UTC.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/collections_logic.dart';
import 'package:mediaflow/src/logic/history_logic.dart';
import 'package:mediaflow/src/logic/library_logic.dart';
import 'package:mediaflow/src/util/js.dart';

Map<String, dynamic> _load(String name) =>
    (jsonDecode(File('test/fixtures/edit-$name.json').readAsStringSync()) as Map).cast<String, dynamic>();

const _keys = ['library', 'sessions', 'completionTimeline', 'xpLedger', 'activityLog', 'collections', 'orderPlan'];

/// Ids and the exact millisecond of "now" differ between runs; the rest must match.
Object? _norm(Object? v, int now, Map<String, String> renames) {
  String s(String x) {
    var out = x;
    renames.forEach((a, b) => out = out.replaceAll(a, b));
    return out
        .replaceAll(RegExp(r'id_[a-z0-9]+_[a-z0-9]+'), 'ID')
        .replaceAllMapped(RegExp(r'\d{13}'), (m) {
          final n = int.parse(m[0]!);
          return n >= now && n < now + 120000 ? 'NOW' : m[0]!;
        });
  }

  if (v is num) return v >= now && v < now + 120000 ? 'NOW' : v.toDouble();
  if (v is String) return s(v);
  if (v is List) return [for (final x in v) _norm(x, now, renames)];
  if (v is Map) return {for (final e in v.entries) s('${e.key}'): _norm(e.value, now, renames)};
  return v;
}

void _expectSame(Map<String, dynamic> mine, Map<String, dynamic> site, int now, {Map<String, String> renames = const {}}) {
  for (final k in _keys) {
    expect(jsonEncode(_norm(mine[k], now, renames)), jsonEncode(_norm(site[k], now, renames)), reason: k);
  }
}

Map<String, dynamic> _copy(Object? v) => (jsonDecode(jsonEncode(v)) as Map).cast<String, dynamic>();

String Function() _uids(int now) {
  var n = 0;
  return () => mediaFlowUid(now + n++);
}

void main() {
  test('title editor: edit (completed, rating, manual cover)', () {
    final fx = _load('edit-title');
    final now = jsNum(fx['now']).toInt();
    final state = _copy(fx['before']);
    final old = findTitle(state, 'lib_alpha')!;
    final f = TitleFields.of(old);
    final fields = TitleFields(
      title: f.title, categoryId: f.categoryId, progress: 12, total: f.total, status: 'completed', priority: f.priority,
      estimatedMinutes: f.estimatedMinutes, tags: f.tags, rating: 8.5, coverUrl: 'https://example.com/alpha.jpg',
      repeatFull: f.repeatFull, repeatExtra: f.repeatExtra, startedAt: f.startedAt, completedAt: f.completedAt,
    );
    expect(saveTitle(state, 'lib_alpha', fields, now, _uids(now)), isNull);
    _expectSame(state, (fx['after'] as Map).cast<String, dynamic>(), now);
  });

  test('title editor: add a new title', () {
    final fx = _load('add-title');
    final now = jsNum(fx['now']).toInt();
    final state = _copy(fx['before']);
    String? id;
    saveTitle(state, null, TitleFields(title: 'Brand New Show', categoryId: 'seasonal', total: 10, priority: 'high'), now, _uids(now),
        saved: (x, _) => id = x);
    final after = (fx['after'] as Map).cast<String, dynamic>();
    final before = (fx['before']['library'] as List).map((i) => i['id']).toSet();
    final siteId = (after['library'] as List).map((i) => i['id']).firstWhere((i) => !before.contains(i)) as String;
    _expectSame(state, after, now, renames: {id!: 'NEW', siteId: 'NEW'});
  });

  test('History: delete a log', () {
    final fx = _load('delete-history');
    final now = jsNum(fx['now']).toInt();
    final state = _copy(fx['before']);
    expect(deleteSessions(state, {'old_0'}, now), 1);
    _expectSame(state, (fx['after'] as Map).cast<String, dynamic>(), now);
  });

  test('Collections: add titles one by one', () {
    final fx = _load('collection-add');
    final now = jsNum(fx['now']).toInt();
    final state = _copy(fx['before']);
    final uid = _uids(now);
    expect(addCollectionTitles(state, 'col_one', ['lib_beta'], now, uid), 1);
    expect(addCollectionTitles(state, 'col_one', ['lib_gamma'], now, uid), 1);
    _expectSame(state, (fx['after'] as Map).cast<String, dynamic>(), now);
  });

  test('Personal Order: add a title, then move one up', () {
    final fx = _load('order-change');
    final now = jsNum(fx['now']).toInt();
    final state = _copy(fx['before']);
    final uid = _uids(now);
    orderEdit(state, now, uid, (p) => orderAddTitles(p, state, ['lib_gamma']));
    orderEdit(state, now, uid, (p) => orderMoveTitle(p, state, 'lib_beta', delta: -1));
    _expectSame(state, (fx['after'] as Map).cast<String, dynamic>(), now);
  });
}
