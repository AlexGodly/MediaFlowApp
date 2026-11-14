// 10.0.0 (website v579): a by-parts title in MediaFlow Recommends. "Add
// recommended title" / the Logging Library's quick add start it on its default
// part (the one logged last), one unit, so the log moves that part instead of
// logging nothing; the recommendation names the next part.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/log_draft.dart';
import 'package:mediaflow/src/logic/title_parts.dart';
import 'package:mediaflow/src/util/js.dart';

Map<String, dynamic> state() => {
      'categories': [
        {'id': 'games', 'name': 'Games', 'unit': 'sessions', 'minutesPerUnit': 60},
      ],
      'library': [
        {
          'id': 'G',
          'title': 'Rocket League',
          'categoryId': 'games',
          'status': 'active',
          'progress': 6,
          'mf577LogMode': 'parts',
          'mf565Unit': 'matches',
          'mf565SecondsPerUnit': 900,
          'mf577LastPartId': 'b',
          'seasons': [
            {'id': 'a', 'name': 'Career', 'progress': 2, 'mf577Kind': 'Mode'},
            {'id': 'b', 'name': 'Live', 'progress': 4, 'total': 10, 'mf577Kind': 'Mode'},
          ],
        },
        {'id': 'P', 'title': 'Celeste', 'categoryId': 'games', 'status': 'active', 'progress': 3},
      ],
      'sessions': <dynamic>[],
      'settings': <String, dynamic>{},
    };

void main() {
  test('quick add of a by-parts title starts on its default part', () {
    final ed = LogDraftEditor(
      state: state(),
      task: {'categoryId': 'games', 'targetMid': 2, 'libraryId': 'G'},
      logDraft: {'v369Interface': 'quick', 'v179Mode': 'progress', 'entries': <dynamic>[]},
      entryDraft: {},
    );
    expect(ed.quickAdd('G'), isNull);
    final e = asMap(asList(ed.logDraft['entries']).first)!;
    expect(e['mf577Parts'], [
      {'id': 'b', 'qty': 1},
    ]);
    expect(jsNum(e['qty']), 1);
    expect(jsNum(e['v179StartProgress']), 6);
    expect(jsNum(e['v179EndProgress']), 7);

    expect(ed.quickAdd('P'), isNull);
    final plain = asMap(asList(ed.logDraft['entries']).last)!;
    expect(plain.containsKey('mf577Parts'), isFalse, reason: 'normal titles are unchanged');
    expect(jsNum(plain['qty']), 0);
  });

  test('the recommendation names the next part', () {
    final s = state();
    final item = asMap(asList(s['library']).first);
    final cat = asMap(asList(s['categories']).first);
    expect(nextPartText(item, cat), 'Mode · Live · Match 5 of 10');
    expect(nextPartText(asMap(asList(s['library']).last), cat), '');
  });
}
