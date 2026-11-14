// 11.0.0: Category Classes keep every kind of icon the website allows —
// emoji, an http(s) link, or one of MediaFlow's packaged category icons
// (website v258) — and categories do too.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/categories.dart';
import 'package:mediaflow/src/logic/category_classes.dart';
import 'package:mediaflow/src/ui/widgets.dart' show categoryIconUrl;

void main() {
  test('packaged icons are kept (v144SafeIconUrl + v258)', () {
    expect(safeCategoryIconUrl('assets/category-icons/games.png'), 'assets/category-icons/games.png');
    expect(safeCategoryIconUrl('./assets/category-icons/games.png'), 'assets/category-icons/games.png');
    expect(safeCategoryIconUrl('/assets/category-icons/games.png'), 'assets/category-icons/games.png');
    expect(safeCategoryIconUrl('assets/other/x.png'), '', reason: 'other relative paths stay blocked');
    expect(safeCategoryIconUrl('https://example.com/i.png'), 'https://example.com/i.png');
    expect(safeCategoryIconUrl('javascript:alert(1)'), '');
    expect(kBuiltInCategoryIcons, hasLength(24));
    expect(categoryIconUrl('assets/category-icons/games.png'), endsWith('/assets/category-icons/games.png'));
  });

  test('a class with a packaged icon keeps it when cleaned', () {
    final clean = cleanCategoryClasses({
      'enabled': true,
      'classes': [
        {'id': 'a', 'name': 'Anime', 'icon': '🖼️', 'iconUrl': 'assets/category-icons/seasonal-anime.png', 'color': '#a78bfa', 'weight': 3, 'categoryIds': ['c1']},
        {'id': 'b', 'name': 'Web', 'icon': '🖼️', 'iconUrl': 'https://example.com/i.png', 'categoryIds': []},
        {'id': 'c', 'name': 'Bad', 'icon': '📚', 'iconUrl': 'file:///etc/passwd', 'categoryIds': []},
      ],
    }, ['c1']);
    final classes = clean['classes'] as List;
    expect((classes[0] as Map)['iconUrl'], 'assets/category-icons/seasonal-anime.png');
    expect((classes[0] as Map)['color'], '#A78BFA');
    expect((classes[1] as Map)['iconUrl'], 'https://example.com/i.png');
    expect((classes[2] as Map)['iconUrl'], '');
  });
}
