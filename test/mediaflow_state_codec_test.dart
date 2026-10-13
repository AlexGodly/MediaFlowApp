import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_models.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';

void main() {
  final fixture = {
    'categories': [
      {'id': 'anime', 'name': 'Anime', 'icon': '📺'},
      {'id': 'books', 'name': 'Books', 'icon': '📖'},
    ],
    'library': [
      {
        'id': '1', 'title': 'Hotel', 'categoryId': 'anime',
        'status': 'active', 'priority': 'high', 'progress': 5,
        'total': 12, 'rating': 8.5,
        'coverUrl': 'https://example.test/cover.png', 'tags': ['Drama'],
      },
      {
        'id': '2', 'title': 'A Book', 'categoryId': 'books',
        'status': 'planned', 'priority': 'low', 'progress': 0,
        'total': null,
      },
    ],
  };

  test('raw JSONB state preserves v410 Library fields', () {
    final snapshot = decodeMediaFlowState(fixture);
    expect(snapshot.library, hasLength(2));
    expect(snapshot.categories.first.name, 'Anime');
    expect(snapshot.library.first.title, 'Hotel');
    expect(snapshot.library.first.categoryId, 'anime');
    expect(snapshot.library.first.status, 'active');
    expect(snapshot.library.first.progress, 5);
    expect(snapshot.library.first.total, 12);
    expect(snapshot.library.first.rating, 8.5);
  });

  test('gzip/base64 wrapper matches the web cloud format', () {
    final packed = base64Encode(gzip.encode(utf8.encode(jsonEncode(fixture))));
    final snapshot = decodeMediaFlowState({
      '__mediaflowCompressed': 'gzip',
      'data': packed,
    });
    expect(snapshot.library.map((item) => item.title).toList(),
        ['Hotel', 'A Book']);
  });

  test('bad compressed data fails visibly rather than showing empty data', () {
    expect(
      () => decodeMediaFlowState({
        '__mediaflowCompressed': 'gzip',
        'data': 'not-valid-base64',
      }),
      throwsFormatException,
    );
  });

  test('combined search, category and status filters', () {
    final titles = decodeMediaFlowState(fixture).library;
    final found = const MediaFlowLibraryFilter(
      search: 'hot', categoryId: 'anime', status: 'active',
    ).apply(titles);
    expect(found.map((item) => item.id).toList(), ['1']);
    expect(const MediaFlowLibraryFilter(
      search: 'hotel', priority: 'low',
    ).apply(titles), isEmpty);
  });

  test('priority sorting puts high-priority title first', () {
    final titles = decodeMediaFlowState(fixture).library;
    final result = const MediaFlowLibraryFilter(
      sort: LibrarySort.priorityHigh,
    ).apply(titles);
    expect(result.map((item) => item.id).toList(), ['1', '2']);
  });

  test('empty account row has an empty read-only Library', () {
    expect(decodeMediaFlowState(null).library, isEmpty);
  });
}
