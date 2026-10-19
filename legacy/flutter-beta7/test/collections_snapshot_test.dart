import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/data/mediaflow_state_codec.dart';

void main() {
  test('Collection ordering and progress mirror v274 snapshot semantics', () {
    final catalog = decodeMediaFlowState({
      'library': [
        {'id': 'a', 'title': 'Alpha', 'status': 'completed',
          'progress': 10, 'total': 10},
        {'id': 'b', 'title': 'Beta', 'status': 'active',
          'progress': 5, 'total': 10},
      ],
      'collections': [
        {'id': 'collection', 'title': 'Favorites',
          'description': 'My favorites',
          'titleIds': ['a','b','missing'],
          'order': ['b','a','b','unknown']},
      ],
    });
    final collection = catalog.collections.single;
    final map = {for (final title in catalog.library) title.id: title};
    expect(collection.titleIds, ['b','a','missing']);
    expect(collection.resolvedTitles(map).map((item) => item.title),
        ['Beta','Alpha']);
    expect(collection.progressPercent(map), 75);
  });

  test('Missing collection key produces an empty collection list', () {
    expect(decodeMediaFlowState({'library': []}).collections, isEmpty);
  });

  test('Malformed collection payload is rejected', () {
    expect(() => decodeMediaFlowState({'collections': {'invalid': true}}),
        throwsFormatException);
  });
}
