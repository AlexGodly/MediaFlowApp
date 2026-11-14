import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/extras.dart';

void main() {
  test('stopwatch matches the website actions', () {
    final sw = Stopwatch2(null);
    expect(sw.setTime(1, 2, 3, 10), 'Stopwatch set to 01:02:03 ✓');
    expect(sw.data['elapsed'], 3723000);
    expect(sw.data['resetValue'], 3723000);
    expect(sw.start(1000), isTrue);
    expect(sw.start(1500), isFalse);
    expect(sw.elapsed(61000), 3723000 + 60000);
    expect(sw.pause(61000), isTrue);
    expect(sw.data['elapsed'], 3783000);
    expect(sw.addTime(0, 0, 0, 1), 'Enter a time to add.');
    sw.addTime(0, 1, 0, 2);
    expect(sw.data['elapsed'], 3843000);
    expect(sw.data['resetValue'], 3843000);
    sw.minusTime(9, 0, 0, 3);
    expect(sw.data['elapsed'], 0);
    sw.reset(4);
    expect(sw.data['elapsed'], 0);
    sw.clear(5);
    expect(sw.data['resetValue'], 0);
    expect(sw.data['modifiedAt'], 5);
    expect(fmtStopwatch(3599999), '00:59:59');
  });

  test('runtime calculator carry-forward and multi-row', () {
    final rc = RuntimeCalc(null);
    expect(rc.calculate(), 'Enter at least one runtime to calculate.');
    rc.updateField('chain', 0, 'm', 24);
    rc.updateField('chain', 1, 'm', 23);
    rc.updateField('chain', 1, 's', 75); // clamped to 59
    expect(rc.calculate(), isNull);
    expect(rc.resultSeconds, 24 * 60 + 23 * 60 + 59);
    expect(rc.resultCount, 2);
    rc.continueResult();
    expect(timeToSeconds(rc.chain[0]), rc.resultSeconds);
    expect(rc.data['carryCount'], 2);
    rc.updateField('chain', 1, 'h', 1);
    rc.calculate();
    expect(rc.resultCount, 3);
    expect(rc.restorePrevious(), startsWith('Restored previous total'));
    expect(rc.resultCount, 2);
    rc.setMode('multi');
    expect(rc.rows.length, 2);
    rc.addRow();
    expect(rc.removeRow(0), isNull);
    expect(rc.removeRow(0), 'Multi-row mode keeps at least two runtime rows.');
  });

  test('newest tool change wins and mirrors the legacy stopwatch field', () {
    final state = <String, dynamic>{};
    final a = Stopwatch2(null)..setTime(0, 1, 0, 100);
    expect(writeTool(state, 'stopwatch', a.data), isTrue);
    expect(state['stopwatch']['elapsed'], 60000);
    expect(state['dashboardToolsV257']['modifiedAt'], 100);
    final older = Stopwatch2(null)..setTime(0, 2, 0, 50);
    expect(writeTool(state, 'stopwatch', older.data), isFalse);
    final rc = RuntimeCalc(null)..touch(200);
    rc.updateField('chain', 0, 'h', 1);
    expect(writeTool(state, 'runtimeCalculator', rc.data), isTrue);
    expect(state['dashboardToolsV257']['stopwatch']['elapsed'], 60000);
    expect(state['dashboardToolsV257']['modifiedAt'], 200);
  });

  test('On This Day groups History and Library milestones by years ago', () {
    final now = DateTime(2026, 10, 31, 15);
    final state = <String, dynamic>{
      'library': [
        {'id': 'a', 'title': 'Alpha', 'categoryId': 'c', 'startedAt': DateTime(2024, 10, 31, 9).millisecondsSinceEpoch},
        {'id': 'b', 'title': 'Beta', 'categoryId': 'c', 'completedAt': DateTime(2025, 10, 31, 20).millisecondsSinceEpoch},
      ],
      'sessions': [
        {'date': '2025-10-31', 'timestamp': 1, 'minutes': 60, 'titles': [
          {'title': 'Alpha', 'libraryId': 'a', 'qty': 1},
          {'title': 'Beta', 'libraryId': 'b', 'qty': 3},
        ]},
        {'date': '2025-10-31', 'timestamp': 2, 'minutes': 30, 'titles': [{'title': 'Alpha', 'libraryId': 'a', 'qty': 2}]},
        {'date': '2025-10-30', 'timestamp': 3, 'minutes': 30, 'titles': [{'title': 'Alpha', 'libraryId': 'a', 'qty': 2}]},
        {'date': '2025-10-31', 'status': 'skipped', 'titles': [{'title': 'Alpha', 'libraryId': 'a', 'qty': 2}]},
      ],
    };
    final groups = onThisDay(state, now);
    expect(groups.map((g) => g.years), [1, 2]);
    final one = groups.first.rows;
    final alpha = one.firstWhere((x) => x.kind == 'logged' && x.libraryId == 'a');
    expect(alpha.qty, 3);
    expect(alpha.minutes, 15 + 30);
    expect(one.where((x) => x.kind == 'finished').single.libraryId, 'b');
    expect(groups.last.rows.single.kind, 'started');
  });

  test('On This Day leaves out logs of titles deleted from the Library (website v563)', () {
    final now = DateTime(2026, 10, 31, 12);
    final state = <String, dynamic>{
      'library': [
        {'id': 'a', 'title': 'Alpha', 'categoryId': 'c'},
      ],
      'sessions': [
        {'date': '2025-10-31', 'timestamp': 1, 'minutes': 60, 'titles': [
          {'title': 'Alpha', 'libraryId': 'a', 'qty': 1},
          {'title': 'Deleted one', 'libraryId': 'gone', 'qty': 3},
        ]},
        {'date': '2024-10-31', 'timestamp': 2, 'minutes': 30, 'titles': [{'title': 'Also deleted', 'libraryId': 'x', 'qty': 2}]},
      ],
    };
    final groups = onThisDay(state, now);
    expect(groups.map((g) => g.years), [1], reason: 'a year with only deleted titles disappears');
    expect(groups.single.rows.map((r) => r.title), ['Alpha']);
  });
}
