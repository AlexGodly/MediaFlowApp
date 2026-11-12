// Beta 14's account edits must change the account exactly like the real
// MediaFlow website does. Fixtures are recorded from the website itself
// (tool/website_reference/generate_edit_goldens.py). Run with TZ=UTC.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/edit_op.dart';
import 'package:mediaflow/src/logic/collections_logic.dart';
import 'package:mediaflow/src/logic/history_logic.dart';
import 'package:mediaflow/src/logic/library_logic.dart';
import 'package:mediaflow/src/state/lazy_copy.dart';
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
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) s(k): _norm(v[k], now, renames)};
  }
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

/// Runs [act] on the fixture's account: directly, or (with [asEdit]) the way
/// the app saves an edit — on a copy that only copies what it touches, saved as
/// the difference and applied to the account.
Map<String, dynamic> _run(Map<String, dynamic> fx, bool asEdit, void Function(Map<String, dynamic> s) act) {
  final now = jsNum(fx['now']).toInt();
  final state = _copy(fx['before']);
  if (!asEdit) {
    act(state);
    return state;
  }
  final copy = LazyStateCopy(state);
  act(copy);
  editFromStates(state, copy, now: now)?.apply(state);
  return state;
}

void main() {
  for (final asEdit in [false, true]) {
    final how = asEdit ? ' (as an app edit)' : '';

    test('title editor: edit (completed, rating, manual cover)$how', () {
      final fx = _load('edit-title');
      final now = jsNum(fx['now']).toInt();
      final f = TitleFields.of(findTitle(_copy(fx['before']), 'lib_alpha')!);
      final fields = TitleFields(
        title: f.title, categoryId: f.categoryId, progress: 12, total: f.total, status: 'completed', priority: f.priority,
        estimatedMinutes: f.estimatedMinutes, tags: f.tags, rating: 8.5, coverUrl: 'https://example.com/alpha.jpg',
        repeatFull: f.repeatFull, repeatExtra: f.repeatExtra, startedAt: f.startedAt, completedAt: f.completedAt,
      );
      final state = _run(fx, asEdit, (s) => expect(saveTitle(s, 'lib_alpha', fields, now, _uids(now)), isNull));
      _expectSame(state, (fx['after'] as Map).cast<String, dynamic>(), now);
    });

    test('title editor: add a new title$how', () {
      final fx = _load('add-title');
      final now = jsNum(fx['now']).toInt();
      String? id;
      final state = _run(fx, asEdit, (s) {
        saveTitle(s, null, TitleFields(title: 'Brand New Show', categoryId: 'seasonal', total: 10, priority: 'high'), now,
            _uids(now), saved: (x, _) => id = x);
      });
      final after = (fx['after'] as Map).cast<String, dynamic>();
      final before = (fx['before']['library'] as List).map((i) => i['id']).toSet();
      final siteId = (after['library'] as List).map((i) => i['id']).firstWhere((i) => !before.contains(i)) as String;
      _expectSame(state, after, now, renames: {id!: 'NEW', siteId: 'NEW'});
    });

    test('History: delete a log$how', () {
      final fx = _load('delete-history');
      final now = jsNum(fx['now']).toInt();
      final state = _run(fx, asEdit, (s) => expect(deleteSessions(s, {'old_0'}, now), 1));
      _expectSame(state, (fx['after'] as Map).cast<String, dynamic>(), now);
    });

    test('Collections: add titles one by one$how', () {
      final fx = _load('collection-add');
      final now = jsNum(fx['now']).toInt();
      final uid = _uids(now);
      final state = _run(fx, asEdit, (s) {
        expect(addCollectionTitles(s, 'col_one', ['lib_beta'], now, uid), 1);
        expect(addCollectionTitles(s, 'col_one', ['lib_gamma'], now, uid), 1);
      });
      _expectSame(state, (fx['after'] as Map).cast<String, dynamic>(), now);
    });

    test('Personal Order: add a title, then move one up$how', () {
      final fx = _load('order-change');
      final now = jsNum(fx['now']).toInt();
      final uid = _uids(now);
      final state = _run(fx, asEdit, (s) {
        orderEdit(s, now, uid, (p) => orderAddTitles(p, s, ['lib_gamma']));
        orderEdit(s, now, uid, (p) => orderMoveTitle(p, s, 'lib_beta', delta: -1));
      });
      _expectSame(state, (fx['after'] as Map).cast<String, dynamic>(), now);
    });
  }
}
