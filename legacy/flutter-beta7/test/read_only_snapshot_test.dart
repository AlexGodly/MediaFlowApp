import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';
import 'package:mediaflow_app/features/history/history_filter.dart';

void main() {
  final state = {
    'categories': [
      {'id': 'a', 'name': 'Anime', 'unit': 'episodes'},
      {'id': 'b', 'name': 'Books', 'unit': 'chapters'},
    ],
    'library': [
      {'id': 'one', 'title': 'Hotel', 'categoryId': 'a'},
    ],
    'sessions': [
      {
        'id': 's1',
        'timestamp': DateTime(2026, 10, 13, 10).millisecondsSinceEpoch,
        'date': '2026-10-13',
        'categoryId': 'a',
        'status': 'complete',
        'actualAmount': 3,
        'minutes': 67.5,
        'xp': 35,
        'unit': 'episodes',
        'source': 'recommendation',
        'titles': [
          {'title': 'Hotel', 'libraryId': 'one', 'qty': 3}
        ],
      },
      {
        'id': 's2',
        'timestamp': DateTime(2026, 10, 2, 10).millisecondsSinceEpoch,
        'date': '2026-10-02',
        'categoryId': 'b',
        'status': 'skipped',
        'actualAmount': 0,
        'minutes': 0,
        'xp': 0,
        'note': 'Recommendation not followed',
      },
    ],
    'sessionActive': true,
    'currentTask': {
      'categoryId': 'a',
      'title': 'Hotel',
      'low': 1,
      'high': 3,
      'unit': 'episodes',
      'reasons': ['High priority'],
    },
    'settings': {'dailyMinutes': 90, 'tasksPerDay': 2},
    'xpLedger': {'libraryAdditions': {'unchanged': true}},
  };

  test('v410 history/task are projected from one raw account snapshot', () {
    final catalog = decodeMediaFlowState(state);
    expect(catalog.library.single.title, 'Hotel');
    expect(catalog.sessions, hasLength(2));
    expect(catalog.sessions.first.actualAmount, 3);
    expect(catalog.sessions.first.minutes, 67.5);
    expect(catalog.sessions.first.titles.single.title, 'Hotel');
    expect(catalog.currentTask?.title, 'Hotel');
    expect(catalog.currentTask?.reasons, ['High priority']);
    expect(catalog.sessionActive, isTrue);
    expect(catalog.tasksPerDay, 2);
    expect(catalog.dailyMinutes, 90);
    expect(state['xpLedger'], isNotNull); // Source fixture was not mutated.
  });

  test('compressed snapshot also decodes History and Dashboard state', () {
    final payload = base64Encode(gzip.encode(utf8.encode(jsonEncode(state))));
    final catalog = decodeMediaFlowState({
      '__mediaflowCompressed': 'gzip', 'data': payload,
    });
    expect(catalog.sessions, hasLength(2));
    expect(catalog.currentTask?.categoryId, 'a');
    expect(catalog.dailyMinutes, 90);
  });

  test('History filter finds titles and supports combined category/time', () {
    final sessions = decodeMediaFlowState(state).sessions;
    final today = DateTime(2026, 10, 13, 12);
    final results = const MediaFlowHistoryFilter(
      search: 'hotel',
      categoryId: 'a',
      range: MediaFlowHistoryRange.today,
    ).apply(sessions, now: today);
    expect(results.map((entry) => entry.id).toList(), ['s1']);

    final week = const MediaFlowHistoryFilter(
      range: MediaFlowHistoryRange.sevenDays,
    ).apply(sessions, now: today);
    expect(week.map((entry) => entry.id).toList(), ['s1']);
  });

  test('History filter excludes skipped sessions when filtering complete', () {
    final sessions = decodeMediaFlowState(state).sessions;
    final result = const MediaFlowHistoryFilter(status: 'complete').apply(sessions);
    expect(result, hasLength(1));
    expect(result.single.id, 's1');
  });

  test('Malformed sessions fail instead of silently inventing an empty History', () {
    expect(() => decodeMediaFlowState({'sessions': {'not': 'a list'}}),
      throwsFormatException);
  });
}
