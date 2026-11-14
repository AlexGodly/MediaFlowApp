// 9.0.0.577 contract (website v577): XP History adds up to the total, the
// Batch Log draft is shared (newer wins), and quick logging of a by-parts
// title moves only its chosen parts at their own times.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/history_logic.dart';
import 'package:mediaflow/src/logic/log_draft.dart';
import 'package:mediaflow/src/logic/resume.dart';
import 'package:mediaflow/src/logic/stats.dart';
import 'package:mediaflow/src/util/js.dart';

void main() {
  final cat = <String, dynamic>{'id': 'games', 'name': 'Games', 'unit': 'sessions', 'minutesPerUnit': 30};
  Map<String, dynamic> parts() => {
        'id': 'V', 'title': 'Valorant', 'categoryId': 'games', 'status': 'active', 'progress': 45, 'total': null,
        'mf577LogMode': 'parts', 'createdAt': 1790000000000,
        'seasons': [
          {'id': 'pc', 'name': 'Competitive', 'progress': 41, 'total': null, 'mf577Kind': 'Mode', 'mf577SecondsPerUnit': 2400},
          {'id': 'pu', 'name': 'Unrated', 'progress': 4, 'total': 10, 'mf577Kind': 'Mode'},
        ],
      };

  test('XP History sums to the account\'s XP (added and completed titles have rows)', () {
    final state = <String, dynamic>{
      'categories': [cat],
      'library': [
        parts(),
        {'id': 'D', 'title': 'Done', 'categoryId': 'games', 'status': 'completed', 'progress': 3, 'total': 3, 'completedAt': 1791000000000},
      ],
      'sessions': <dynamic>[],
      'settings': <String, dynamic>{},
      'xpLedger': <String, dynamic>{},
    };
    final rows = xpHistory(state);
    final sum = rows.fold<double>(0, (a, r) => a + r.xp);
    expect(sum, xpMetrics(state).total);
    expect(rows.where((r) => r.kind == 'libraryAddition').length, 2);
    expect(rows.where((r) => r.kind == 'titleCompletion' && r.id.startsWith('completed:')).single.title, 'Done');
  });

  test('the Batch Log draft: newer wins, unknown row fields dropped', () {
    final state = <String, dynamic>{};
    expect(applyBatchSection(state, {'draft': {'rows': [{'libraryId': 'V', 'qty': 2, 'junk': 1}], 'note': 'n', 'date': '2026-11-14'}, 'modifiedAt': 10}), isTrue);
    expect(readBatchSection(state)!['draft']['rows'][0], {'libraryId': 'V', 'qty': 2});
    expect(applyBatchSection(state, {'draft': {'rows': []}, 'modifiedAt': 5}), isFalse, reason: 'older');
    expect(applyBatchSection(state, {'draft': {'rows': [], 'mf573Time': '21:15', 'v179Mode': 'amount'}, 'modifiedAt': 11}), isTrue);
    expect(readBatchSection(state)!['draft'], {'rows': [], 'note': '', 'date': '', 'mf573Time': '21:15', 'v179Mode': 'amount'});
    expect(state['resumeStateV285']['format'], kResumeFormat);
  });

  test('quick logging: chosen parts, their own counters and times', () {
    final ed = LogDraftEditor(
      state: {'categories': [cat], 'library': [parts()], 'sessions': <dynamic>[], 'settings': <String, dynamic>{}},
      task: {'categoryId': 'games'},
      logDraft: {'v369Interface': 'quick', 'v179Mode': 'progress', 'entries': [
        {'libraryId': 'V', 'title': 'Valorant', 'qty': 1, 'mf577Parts': [{'id': 'pc', 'qty': 1}]},
      ]},
      entryDraft: {},
    );
    ed.setPartAt(0, 'pc', 44);
    ed.togglePartAt(0, 'pu');
    ed.setPartAt(0, 'pu', 50); // capped at the part's total (10)
    final e = ed.entries.first;
    expect(e['mf577Parts'], [{'id': 'pc', 'qty': 3}, {'id': 'pu', 'qty': 6}]);
    expect(jsNum(e['qty']), 9);
    expect(jsNum(e['v179EndProgress']), 54);
    expect(jsNum(ed.logDraft['minutes']), 3 * 40 + 6 * 30, reason: 'own part time, then the category\'s');
    ed.togglePartAt(0, 'pc');
    expect(ed.entries.first['mf577Parts'], [{'id': 'pu', 'qty': 6}]);
    ed.togglePartAt(0, 'pu');
    expect(ed.entries.first['mf577Parts'], [{'id': 'pu', 'qty': 6}], reason: 'never the last part');
  });
}
