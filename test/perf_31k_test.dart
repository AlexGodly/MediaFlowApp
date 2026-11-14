// 10.0.0: timings on an account the size of the owner's (31,468 titles, a
// long History). Each step must stay well inside its budget; the measured
// numbers are printed as "PERF <step>: <ms> ms" for the release notes.

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/records.dart';
import 'package:mediaflow/src/logic/choice_layout.dart';
import 'package:mediaflow/src/logic/library_index.dart';
import 'package:mediaflow/src/logic/progress_summary.dart';
import 'package:mediaflow/src/state/models.dart';

Map<String, dynamic> bigAccount({int titles = 31468, int sessions = 6000}) {
  final now = DateTime.utc(2026, 11, 14).millisecondsSinceEpoch;
  return {
    'categories': [
      for (var c = 0; c < 12; c++) <String, dynamic>{'id': 'c$c', 'name': 'Category $c', 'unit': 'episodes', 'minutesPerUnit': 24},
    ],
    'library': [
      for (var i = 0; i < titles; i++)
        <String, dynamic>{
          'id': 't$i',
          'title': 'Title number $i',
          'categoryId': 'c${i % 12}',
          'progress': i % 30,
          'total': i % 3 == 0 ? 0 : 40,
          'status': ['planned', 'active', 'completed', 'paused'][i % 4],
          'createdAt': now - i * 60000,
          if (i % 9 == 0) 'coverUrl': 'https://example.com/c/$i.jpg',
        },
    ],
    'sessions': [
      for (var s = 0; s < sessions; s++)
        <String, dynamic>{
          'id': 's$s',
          'timestamp': now - s * 3600000,
          'categoryId': 'c${s % 12}',
          'amount': 2,
          'minutes': 48,
          'titles': [
            {'libraryId': 't${(s * 7) % titles}', 'title': 'Title number ${(s * 7) % titles}', 'qty': 2},
          ],
        },
    ],
    'collections': <dynamic>[],
    'settings': <String, dynamic>{},
    'xp': 0,
  };
}

int _time(String step, void Function() run, {required int budgetMs}) {
  final sw = Stopwatch()..start();
  run();
  sw.stop();
  debugPrint('PERF $step: ${sw.elapsedMilliseconds} ms (budget $budgetMs ms)');
  expect(sw.elapsedMilliseconds, lessThan(budgetMs), reason: step);
  return sw.elapsedMilliseconds;
}

void main() {
  test('31k titles: the everyday steps stay fast', () {
    final state = bigAccount();
    final now = DateTime.utc(2026, 11, 14).millisecondsSinceEpoch;
    late AccountView view;
    _time('open the account (AccountView + Library titles)', () {
      view = AccountView(state);
      expect(view.library.length, 31468);
    }, budgetMs: 2500);
    _time('Library index', () => expect(LibraryIndex.of(state).length, 31468), budgetMs: 2500);
    _time('Log page cards (progress summary)', () => progressSummary(state, now), budgetMs: 2500);
    _time('Log page cards again after a log (cached)', () => progressSummary(state, now), budgetMs: 2500);
    _time('category lists in choice order', () {
      for (var i = 0; i < 100; i++) {
        filterCategories(view);
      }
    }, budgetMs: 1000);
    _time('search 31k titles', () {
      final q = 'number 12';
      final hits = [for (final t in view.library) if (t.title.toLowerCase().contains(q)) t];
      expect(hits, isNotEmpty);
    }, budgetMs: 1000);
    late Map<String, Rec> recs;
    _time('split into records (sync)', () => recs = decomposeState(state, (_) => null), budgetMs: 6000);
    _time('rebuild from records (sync)', () => composeState(recs.values), budgetMs: 6000);
  });
}
