// 7.1.1.569 contract: a title's own unit and runtime in logging (website v569)
// and in Discord, and Consuming… following the open log's draft progress.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/log_draft.dart';
import 'package:mediaflow/src/logic/log_engine.dart';
import 'package:mediaflow/src/logic/title_units.dart';
import 'package:mediaflow/src/state/models.dart';
import 'package:mediaflow/src/ui/presence.dart';
import 'package:mediaflow/src/util/js.dart';

void main() {
  final cat = <String, dynamic>{'id': 'games', 'name': 'Games', 'unit': 'sessions', 'minutesPerUnit': 45};
  final own = <String, dynamic>{
    'id': 'G', 'title': 'Rocket League', 'categoryId': 'games', 'progress': 10, 'total': 0,
    'mf565Unit': 'matches', 'mf565SecondsPerUnit': 1200,
  };
  final plain = <String, dynamic>{'id': 'P', 'title': 'Celeste', 'categoryId': 'games', 'progress': 3, 'total': 8};
  final unitOnly = <String, dynamic>{'id': 'U', 'title': 'Chess', 'categoryId': 'games', 'progress': 0, 'mf565Unit': 'games'};
  Map<String, dynamic> state() => {
        'categories': [cat],
        'library': [own, plain, unitOnly],
        'sessions': <dynamic>[],
        'settings': <String, dynamic>{},
      };

  test('own runtime only when the title has its own unit and runtime', () {
    expect(ownRuntimeSeconds(own), 1200);
    expect(ownRuntimeSeconds(plain), 0);
    expect(ownRuntimeSeconds(unitOnly), 0);
    expect(ownRuntimeSeconds({'mf565SecondsPerUnit': 600}), 0, reason: 'a runtime without its own unit is ignored');
  });

  test('quick logging: the draft minutes count the title\'s own runtime', () {
    final ed = LogDraftEditor(
      state: state(),
      task: {'categoryId': 'games', 'targetMid': 2},
      logDraft: {
        'v369Interface': 'quick',
        'entries': [
          {'libraryId': 'G', 'title': 'Rocket League', 'qty': 3},
          {'libraryId': 'P', 'title': 'Celeste', 'qty': 2},
          {'libraryId': 'U', 'title': 'Chess', 'qty': 1},
        ],
      },
      entryDraft: {},
    );
    ed.syncSingle();
    // 3 matches × 20 min + 2 × 45 + 1 × 45 (own unit, no own runtime).
    expect(jsNum(ed.logDraft['minutes']), 60 + 90 + 45);
    expect(jsNum(ed.logDraft['amount']), 6);
  });

  test('Batch Log default minutes use the title\'s own runtime', () {
    final c = Category(cat);
    final a = previewEntry(LibraryTitle(own), c, const LogEntry(libraryId: 'G', reached: 13));
    expect(a.qty, 3);
    expect(a.minutes, 60);
    final b = previewEntry(LibraryTitle(plain), c, const LogEntry(libraryId: 'P', reached: 5));
    expect(b.minutes, 90, reason: 'unchanged for other titles');
  });

  test('labels use the title\'s own unit', () {
    expect(unitLabel(titleUnit(own, cat), 1), 'match');
    expect(unitLabel(titleUnit(own, cat), 2), 'matches');
    expect(unitLabel(titleUnit(plain, cat), 1), 'session');
  });

  test('Consuming… reads the open log\'s draft progress', () {
    final ed = LogDraftEditor(
      state: state(),
      task: {'categoryId': 'games'},
      logDraft: {
        'v369Interface': 'quick',
        'v179Mode': 'amount',
        'entries': [
          {'libraryId': 'P', 'title': 'Celeste', 'qty': 1, 'v369UpdatedAt': 5},
          {'libraryId': 'G', 'title': 'Rocket League', 'qty': 4, 'v369UpdatedAt': 9},
        ],
      },
      entryDraft: {},
    );
    final entry = draftEntryFor(ed, 'G')!;
    final d = draftProgress(ed, own, entry);
    expect(d.before, 10);
    expect(d.progress, 14, reason: 'after this log, not the saved 10');
    expect(draftEntryFor(ed, 'X'), isNull);
  });
}
