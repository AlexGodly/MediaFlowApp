// The fast Library index (LibraryIndex) must give exactly the orders the old
// screen code gave, for every sort, direction and filter — and stay fast at
// 100,000 titles.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/library_index.dart';
import 'package:mediaflow/src/logic/log_arrange.dart';
import 'package:mediaflow/src/logic/recommend.dart' show stableSort;
import 'package:mediaflow/src/state/models.dart';
import 'package:mediaflow/src/util/js.dart';

const _words = ['Alpha', 'beta', 'Gamma', 'delta', 'Part', 'Season', 'Chapter', 'The', 'a', 'Zeta'];
const _cats = ['cat_anime', 'cat_manga', 'cat_movies', 'cat_books'];
const _statuses = ['planned', 'active', 'paused', 'completed', 'dropped', '', 'Active'];
const _priorities = ['low', 'medium', 'high', '', 'High'];

Map<String, dynamic> _account(int n, {int seed = 7}) {
  final r = math.Random(seed);
  Object? maybe(Object? v) => r.nextInt(5) == 0 ? null : v;
  final library = <dynamic>[];
  for (var i = 0; i < n; i++) {
    final words = [for (var w = 0; w < 1 + r.nextInt(3); w++) _words[r.nextInt(_words.length)]];
    if (r.nextBool()) words.add('${r.nextInt(30)}');
    if (r.nextInt(4) == 0) words.add('0${r.nextInt(9)}');
    final total = r.nextInt(4) == 0 ? null : r.nextInt(40);
    library.add(<String, dynamic>{
      'id': r.nextInt(50) == 0 ? '' : 'lib_$i',
      'title': r.nextInt(60) == 0 ? '' : words.join(' '),
      'categoryId': _cats[r.nextInt(_cats.length)],
      'status': _statuses[r.nextInt(_statuses.length)],
      'priority': _priorities[r.nextInt(_priorities.length)],
      'rating': maybe(r.nextInt(11)),
      'progress': maybe(r.nextInt(40)),
      'total': total,
      'createdAt': maybe(1700000000000 + r.nextInt(5) * 1000),
      'modifiedAt': maybe(1700000000000 + r.nextInt(5) * 1000),
      'lastSeenAt': maybe(1700000000000 + r.nextInt(3) * 1000),
      'tags': r.nextInt(3) == 0 ? ['tagged', _words[r.nextInt(_words.length)]] : <dynamic>[],
    });
  }
  final sessions = <dynamic>[
    for (var s = 0; s < n ~/ 3; s++)
      {
        'timestamp': 1700000000000 + r.nextInt(8) * 1000,
        'titles': [
          {'libraryId': 'lib_${r.nextInt(n)}', 'title': ''},
          {'title': _words[r.nextInt(_words.length)]},
        ],
      },
  ];
  return {'library': library, 'sessions': sessions, 'savedAt': seed};
}

/// The Library page's sort before this change (`v189CompareLibraryItems`), with
/// the "Last logged" lookup by id, then title, like the website.
List<String> _oldLibraryOrder(Map<String, dynamic> state, String sort, String dir, int seed) {
  final rows = [for (final i in asList(state['library'])) LibraryTitle(asMap(i)!)];
  final asc = dir == 'asc';
  final touched = lastTouchedIndex(state);
  double n(Object? v) => jsNumOrNull(v) ?? 0;
  int titleCmp(LibraryTitle a, LibraryTitle b) => compareTitlesNatural(a.title, b.title);
  const rank = {'low': 0, 'medium': 1, 'high': 2};
  int r(LibraryTitle t) => rank[jsStr(t.raw['priority']).isEmpty ? 'medium' : jsStr(t.raw['priority'])] ?? 1;
  double touch(LibraryTitle t) =>
      touched['id:${t.id}'] ?? touched['title:${cleanTitle(t.raw['title']).toLowerCase()}'] ?? 0;
  stableSort<LibraryTitle>(rows, (a, b) {
    if (sort == 'remaining') {
      final av = remainingUnits(a.raw), bv = remainingUnits(b.raw);
      if (av == null && bv != null) return 1;
      if (av != null && bv == null) return -1;
      if (av == null && bv == null) return titleCmp(a, b);
      final d = (av! - bv!) * (asc ? 1 : -1);
      return d != 0 ? d.sign.toInt() : titleCmp(a, b);
    }
    if (sort == 'title') return asc ? titleCmp(a, b) : -titleCmp(a, b);
    double d;
    switch (sort) {
      case 'priority':
        d = (r(a) - r(b)).toDouble();
      case 'rating':
        d = n(a.raw['rating']) - n(b.raw['rating']);
      case 'progress':
        d = n(a.raw['progress']) - n(b.raw['progress']);
      case 'total':
        d = n(a.raw['total']) - n(b.raw['total']);
      case 'logging':
        d = touch(a) - touch(b);
      case 'seen':
        d = n(a.raw['lastSeenAt']) - n(b.raw['lastSeenAt']);
      case 'added':
        d = n(a.raw['createdAt']) - n(b.raw['createdAt']);
      case 'random':
        d = (seedHash(a.id, seed) - seedHash(b.id, seed)).toDouble();
      default:
        d = n(jsTruthy(a.raw['modifiedAt']) ? a.raw['modifiedAt'] : a.raw['createdAt']) -
            n(jsTruthy(b.raw['modifiedAt']) ? b.raw['modifiedAt'] : b.raw['createdAt']);
    }
    if (sort != 'random' && !asc) d = -d;
    return d != 0 ? d.sign.toInt() : titleCmp(a, b);
  });
  return [for (final t in rows) '${t.raw.hashCode}'];
}

void main() {
  const sorts = ['edited', 'added', 'title', 'priority', 'rating', 'progress', 'total', 'remaining', 'logging', 'seen', 'random'];

  test('natural title ranks match compareTitlesNatural', () {
    final titles = ['Part 10', 'part 2', 'Part 2', 'Alpha 007', 'alpha 7', 'Beta', '', '12 Monkeys', '9 Lives', 'a-b', 'a b'];
    final rank = titleRanks(titles);
    for (var i = 0; i < titles.length; i++) {
      for (var j = 0; j < titles.length; j++) {
        expect((rank[i] - rank[j]).sign, compareTitlesNatural(titles[i], titles[j]).sign,
            reason: '"${titles[i]}" vs "${titles[j]}"');
      }
    }
  });

  test('Library page orders match the old sort for every sort and direction', () async {
    final state = _account(1500);
    final index = LibraryIndex.of(state);
    for (final sort in sorts) {
      for (final dir in ['asc', 'desc']) {
        final order = await index.libraryOrder(sort, dir, 4242);
        final got = [for (final i in order) '${index.items[i].hashCode}'];
        expect(got, _oldLibraryOrder(state, sort, dir, 4242), reason: '$sort $dir');
      }
    }
  });

  test('Library page filters match the old filters', () async {
    final state = _account(1200, seed: 3);
    final index = LibraryIndex.of(state);
    final order = await index.libraryOrder('title', 'asc', 1);
    for (final f in [
      (status: 'all', priority: 'all', cats: <String>{}, q: ''),
      (status: 'completed', priority: 'all', cats: <String>{}, q: ''),
      (status: 'all', priority: 'medium', cats: {'cat_anime'}, q: ''),
      (status: 'planned', priority: 'high', cats: {'cat_manga', 'cat_books'}, q: 'part'),
      (status: 'all', priority: 'all', cats: <String>{}, q: 'TAGGED'),
    ]) {
      final got = index.libraryRows(order, 'k', status: f.status, priority: f.priority, categories: f.cats, query: f.q);
      final want = [
        for (final i in order)
          if (() {
            final t = index.titles[i];
            final q = f.q.trim().toLowerCase();
            if (f.status != 'all' && t.status != f.status) return false;
            if (f.priority != 'all' && (jsStr(t.raw['priority']).isEmpty ? 'medium' : jsStr(t.raw['priority'])) != f.priority) return false;
            if (f.cats.isNotEmpty && !f.cats.contains(t.categoryId)) return false;
            if (q.isNotEmpty) {
              final tags = asList(t.raw['tags']).map(jsStr).join(' ');
              if (!'${t.title} $tags'.toLowerCase().contains(q)) return false;
            }
            return true;
          }())
            index.titles[i],
      ];
      expect(got.map((t) => t.raw.hashCode).toList(), want.map((t) => t.raw.hashCode).toList(), reason: '$f');
    }
  });

  test('Logging Library orders match pickerCandidates', () async {
    final state = _account(1500, seed: 11);
    final index = LibraryIndex.of(state);
    for (final sort in kPickerSorts.map((s) => s.$1).where((s) => s != 'logAdded')) {
      for (final dir in ['asc', 'desc']) {
        for (final f in [
          (status: 'all', priority: 'all', cats: <String>[], q: ''),
          (status: 'active', priority: 'high', cats: ['cat_anime', 'cat_movies'], q: 'a'),
        ]) {
          final st = PickerState()
            ..sortBase = sort
            ..sortDir = dir
            ..seed = 99
            ..status = f.status
            ..priority = f.priority
            ..categories = f.cats;
          final order = await index.pickerOrder(sort, dir, 99);
          final got = index.pickerRows(order, status: f.status, priority: f.priority, categories: f.cats, query: f.q);
          final want = pickerCandidates(state, null, st, f.q);
          expect(got.map((m) => m.hashCode).toList(), want.map((m) => m.hashCode).toList(), reason: '$sort $dir $f');
        }
      }
    }
  });

  test('100,000 titles sort in the background quickly', () async {
    final state = _account(100000, seed: 5);
    final sw = Stopwatch()..start();
    final index = LibraryIndex.of(state);
    await index.rank();
    final rankMs = sw.elapsedMilliseconds;
    final times = <String, int>{};
    for (final sort in sorts) {
      sw.reset();
      final order = await index.libraryOrder(sort, 'desc', 1);
      times[sort] = sw.elapsedMilliseconds;
      expect(order.length, 100000);
    }
    sw.reset();
    final order = await index.libraryOrder('title', 'asc', 1);
    final rows = index.libraryRows(order, 'x', status: 'all', priority: 'all', categories: {'cat_anime'}, query: 'part');
    final filterMs = sw.elapsedMilliseconds;
    // ignore: avoid_print
    print('100k titles: title ranks ${rankMs}ms, sorts $times, filter+search ${filterMs}ms (${rows.length} rows)');
    expect(filterMs, lessThan(2000));
  });
}
