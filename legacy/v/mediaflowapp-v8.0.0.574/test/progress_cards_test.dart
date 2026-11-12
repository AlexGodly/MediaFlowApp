// The Log tab's Leveling / Day Streak cards and the floating Task Progress card
// (website render-shell + v397 `mf397ReadState`).

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/progress_summary.dart';
import 'package:mediaflow/src/logic/stats.dart';
import 'package:mediaflow/src/logic/task_progress.dart';
import 'package:mediaflow/src/util/js.dart';

void main() {
  group('Day streak (computeDayStreak)', () {
    final now = DateTime.utc(2026, 11, 7, 12).millisecondsSinceEpoch;
    String day(int back) => isoDateUtc(now - back * 86400000);

    test('counts days in a row ending today', () {
      final sessions = [
        {'date': day(0)},
        {'date': day(1)},
        {'date': day(1)},
        {'date': day(2)},
        {'date': day(4)},
      ];
      expect(computeDayStreak(sessions, now), 3);
    });

    test('is 0 when today has no log, and skipped logs do not count', () {
      expect(computeDayStreak([{'date': day(1)}, {'date': day(2)}], now), 0);
      expect(computeDayStreak([{'date': day(0), 'status': 'skipped'}], now), 0);
    });
  });

  test('level info matches the website formula', () {
    final l = levelInfo(250);
    // Level 1 needs 100, level 2 needs round(100 * 2^1.35) = 255.
    expect(l.level, 2);
    expect(l.current, 150);
    expect(l.needed, 255);
  });

  group('Task Progress', () {
    final library = {
      'a': {'id': 'a', 'categoryId': 'anime'},
      'b': {'id': 'b', 'categoryId': 'anime'},
      'm': {'id': 'm', 'categoryId': 'manga'},
    };
    TaskProgress? run(List<Map<String, dynamic>> entries,
            {bool itemized = false, int low = 12, int high = 16, String unit = 'episodes', String finish = 'maximum', String over = 'status'}) =>
        taskProgress(
          task: {'categoryId': 'anime', 'low': low, 'high': high},
          logDraft: {'entries': entries, if (itemized) 'v369Interface': 'itemized'},
          libraryItem: (id) => library[jsStr(id)],
          categoryName: 'Finished Anime',
          categoryType: '',
          unit: unit,
          finish: finish,
          over: over,
        );

    test('v565: finishes at the minimum and counts past 100% by default', () {
      final at9 = run([{'libraryId': 'a', 'qty': 9}], low: 9, high: 13, finish: 'minimum', over: 'count')!;
      expect(at9.pct, 100);
      expect(at9.marker, isNull);
      expect(at9.denominator, 9);
      final at11 = run([{'libraryId': 'a', 'qty': 11}], low: 9, high: 13, finish: 'minimum', over: 'count')!;
      expect(at11.pct.round(), 122);
      expect(at11.warn, isFalse);
      final at15 = run([{'libraryId': 'a', 'qty': 15}], low: 9, high: 13, finish: 'minimum', over: 'count')!;
      expect(at15.pct.round(), 167);
      expect(at15.warn, isTrue);
      final warnOnly = run([{'libraryId': 'a', 'qty': 15}], low: 9, high: 13, finish: 'minimum', over: 'warning')!;
      expect(warnOnly.pct, 100);
      expect(warnOnly.warn, isTrue);
      final statusOnly = run([{'libraryId': 'a', 'qty': 15}], low: 9, high: 13, finish: 'minimum', over: 'status')!;
      expect(statusOnly.pct, 100);
      expect(statusOnly.warn, isFalse);
      final max15 = run([{'libraryId': 'a', 'qty': 15}], low: 9, high: 13, finish: 'maximum', over: 'count')!;
      expect(max15.pct.round(), 115);
    });

    test('hidden until a title from the task category is added', () {
      expect(run([]), isNull);
      expect(run([{'libraryId': 'm', 'qty': 4}]), isNull);
    });

    test('ready to log, goal marker and percentage against the maximum', () {
      final p = run([{'libraryId': 'a', 'qty': 0}])!;
      expect(p.status, 'Ready to log');
      expect(p.denominator, 12);
      expect(p.pct, 0);
      expect(p.marker, closeTo(0.75, 1e-9));
    });

    test('statuses as the amount grows', () {
      expect(run([{'libraryId': 'a', 'qty': 5}])!.status, 'In progress');
      final reached = run([{'libraryId': 'a', 'qty': 7}, {'libraryId': 'b', 'qty': 5}])!;
      expect(reached.status, 'Goal reached');
      expect(reached.pct, 75);
      final within = run([{'libraryId': 'a', 'qty': 14}])!;
      expect(within.status, 'Within target range');
      expect(within.denominator, 14);
      expect(run([{'libraryId': 'a', 'qty': 16}])!.status, 'Recommended maximum reached');
      final over = run([{'libraryId': 'a', 'qty': 20}])!;
      expect(over.status, 'Overwatched');
      expect(over.denominator, 16);
      expect(over.pct, 100);
      expect(run([{'libraryId': 'a', 'qty': 20}], unit: 'chapters')!.status, 'Overread');
    });

    test('Advanced counts units; a single-number goal has no marker', () {
      final p = run([
        {'libraryId': 'a', 'qty': 99, 'v369Units': [{}, {}, {}]},
      ], itemized: true, low: 3, high: 3)!;
      expect(p.amount, 3);
      expect(p.status, 'Goal reached');
      expect(p.marker, isNull);
    });
  });
}
