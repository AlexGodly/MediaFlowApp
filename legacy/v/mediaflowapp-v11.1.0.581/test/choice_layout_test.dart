import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/category_classes.dart';
import 'package:mediaflow/src/logic/choice_layout.dart';

void main() {
  final cats = [(id: 'a', enabled: true), (id: 'b', enabled: false), (id: 'c', enabled: true)];

  test('defaults follow the website order', () {
    expect(visibleChoices({}, 'setStatus', cats), ['planned', 'active', 'paused', 'completed', 'dropped']);
    expect(visibleChoices({}, 'statusFilter', cats), ['active', 'paused', 'completed', 'dropped', 'planned']);
    expect(visibleChoices({}, 'priorityFilter', cats), ['high', 'medium', 'low']);
    expect(visibleChoices({}, 'setCategory', cats), ['a', 'b', 'c']);
  });

  test('custom order, hidden, sources', () {
    final s = {
      'v230ChoiceLayout': {
        'setStatus': {'source': 'custom', 'order': ['dropped', 'active', 'x'], 'hidden': ['paused']},
        'statusFilter': {'source': 'setStatus'},
        'setCategory': {'source': 'categories'},
        'categoryFilter': {'source': 'dynamic'},
      },
      'v181Library': {'categoryOrder': ['c', 'a', 'b'], 'hiddenCategoryIds': ['a']},
    };
    expect(visibleChoices(s, 'setStatus', cats), ['dropped', 'active', 'planned', 'completed']);
    expect(visibleChoices(s, 'statusFilter', cats), ['dropped', 'active', 'planned', 'completed']);
    expect(visibleChoices(s, 'setCategory', cats), ['a', 'c']);
    expect(visibleChoices(s, 'categoryFilter', cats), ['c', 'b']);
    final out = applyChoiceLayout(s, 'setStatus', cats, const [('paused', 'Paused'), ('active', 'Active')], keep: 'paused');
    expect(out, [('active', 'Active'), ('paused', 'Paused')]);
  });

  test('saving one surface keeps the others and stamps modifiedAt', () {
    final out = withSurface({}, 'setPriority', 'custom', ['high', 'low'], ['low'], ['a'], 42);
    expect(out['modifiedAt'], 42);
    expect(out['setPriority'], {'source': 'custom', 'order': ['high', 'low', 'medium'], 'hidden': ['low']});
    expect((out['statusFilter'] as Map)['order'], ['active', 'paused', 'completed', 'dropped', 'planned']);
  });

  test('category classes clean like v480Clean', () {
    final out = cleanCategoryClasses({
      'enabled': true,
      'classes': [
        {'id': 'k1', 'name': '', 'weight': 9, 'color': '#abcdef', 'categoryIds': ['a', 'zz']},
        {'id': 'k2', 'categoryIds': ['a', 'c'], 'color': 'red'},
      ],
    }, ['a', 'c']);
    final cl = out['classes'] as List;
    expect(cl[0]['name'], 'Untitled Class');
    expect(cl[0]['weight'], 5);
    expect(cl[0]['color'], '#ABCDEF');
    expect(cl[0]['categoryIds'], ['a']);
    expect(cl[1]['categoryIds'], ['c']);
    expect(cl[1]['color'], '#A78BFA');
    expect(out['strength'], 'balanced');
  });
}
