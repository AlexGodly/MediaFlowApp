// 10.1.0 (website v580): by-parts titles in Advanced logging (Per Unit,
// Progress Reached, Amount Consumed) use the parts panel, backed by the
// draft's units; and the "+ add" bar's sums.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/log_draft.dart';
import 'package:mediaflow/src/ui/amount_adder.dart';
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
      ],
      'sessions': <dynamic>[],
      'settings': <String, dynamic>{},
    };

LogDraftEditor editor() {
  var n = 0;
  return LogDraftEditor(
    state: state(),
    task: {'categoryId': 'games', 'targetMid': 2},
    logDraft: {'v369Interface': 'itemized', 'v179Mode': 'amount', 'entries': <dynamic>[]},
    entryDraft: {},
    uid: () => 'u${n++}',
  );
}

List<String> unitsOf(LogDraftEditor ed) => [
      for (final u in asList(asMap(asList(ed.logDraft['entries']).first)!['v369Units']).map(asMap))
        '${u!['seasonId']}:${jsNum(u['number']).toInt()}',
    ];

void main() {
  test('Advanced: a by-parts title starts on its default part, one unit', () {
    final ed = editor();
    expect(ed.quickAdd('G'), isNull);
    expect(unitsOf(ed), ['b:5']);
    expect(ed.advParts(0).map((m) => '${m.id}:${m.qty.toInt()}'), ['b:1']);
  });

  test('Amount sets a part\'s units; Progress Reached sets the number reached', () {
    final ed = editor()..quickAdd('G');
    expect(ed.toggleAdvPart(0, 'a'), isNull);
    expect(ed.setAdvPart(0, 'a', 3), isNull); // Per Unit / Amount: 3 matches
    expect(unitsOf(ed), ['b:5', 'a:3', 'a:4', 'a:5']);
    ed.setMethod(0, 'last');
    expect(ed.setAdvPart(0, 'b', 7), isNull); // reached Match 7
    expect(unitsOf(ed), ['a:3', 'a:4', 'a:5', 'b:5', 'b:6', 'b:7']);
    expect(ed.setAdvPart(0, 'b', 99), isNull, reason: 'capped at the part total');
    expect(unitsOf(ed).where((u) => u.startsWith('b:')).length, 6);
    expect(ed.toggleAdvPart(0, 'b'), isNull);
    expect(ed.toggleAdvPart(0, 'a'), isNotNull, reason: 'the last part stays');
  });

  test('+ add sums', () {
    AmountAdder.sums.clear();
    AmountAdder.push('k', 0, 3);
    expect(AmountAdder.sumText('k', 3), isNull, reason: 'one amount: no sum yet');
    AmountAdder.push('k', 3, 4);
    expect(AmountAdder.sumText('k', 7), '3 + 4 = 7');
    AmountAdder.push('k', 7, 2);
    expect(AmountAdder.sumText('k', 9), '3 + 4 + 2 = 9');
    expect(AmountAdder.sumText('k', 5), isNull, reason: 'changed by hand: the sum goes');
    AmountAdder.push('j', 5, 1);
    expect(AmountAdder.sumText('j', 6), '5 + 1 = 6');
  });
}
