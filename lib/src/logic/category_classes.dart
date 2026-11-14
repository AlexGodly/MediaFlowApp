// Category Classes (website v480, 367-v480-category-classes-intelligence.js):
// optional Class → Category → Title recommendations. Stored in
// settings.v480CategoryClasses; the recommendation engine (recommend.dart)
// already reads it. This file is the website's v480Clean, used when saving.

import '../util/js.dart';
import 'categories.dart' show safeCategoryIconUrl;

const kClassStrengths = [('gentle', 'Gentle'), ('balanced', 'Balanced (recommended)'), ('strong', 'Strong')];

const kClassToggles = [
  ('avoidRepeat', 'Class repetition penalty', 'Avoid recommending the same class too frequently'),
  ('rewardNeglect', 'Class neglect bonus', 'Favor classes that have received less attention'),
  ('freshInfluence', 'Fresh episodes influence', 'Preserve seasonal importance when choosing a class'),
  ('adaptAmount', 'Adjust session amounts by class', 'Optionally reduce or increase suggested consumption amounts'),
];

/// `v480Clean`: valid classes only, each category in at most one class.
Map<String, dynamic> cleanCategoryClasses(Object? raw, Iterable<String> categoryIds) {
  final s = asMap(raw) ?? const <String, dynamic>{};
  final strength = const ['gentle', 'balanced', 'strong'].contains(s['strength']) ? s['strength'] as String : 'balanced';
  final valid = categoryIds.toSet(), used = <String>{};
  final classes = <Map<String, dynamic>>[];
  for (final e in asList(s['classes']).take(200)) {
    final entry = asMap(e);
    if (entry == null) continue;
    var id = jsStr(entry['id']).trim();
    if (id.length > 100) id = id.substring(0, 100);
    if (id.isEmpty || classes.any((c) => c['id'] == id)) continue;
    final ids = <String>[];
    for (final v in asList(entry['categoryIds'])) {
      final key = jsStr(v);
      if (valid.contains(key) && used.add(key)) ids.add(key);
    }
    String or(Object? v, String def) => jsTruthy(v) ? jsStr(v) : def; // JS `v || def`
    final color = or(entry['color'], '#A78BFA').toUpperCase();
    var name = or(entry['name'], 'Untitled Class').trim();
    if (name.length > 80) name = name.substring(0, 80);
    var icon = or(entry['icon'], '📚');
    if (icon.length > 32) icon = icon.substring(0, 32);
    final iconUrl = jsStr(entry['iconUrl']).trim();
    final w = jsNum(entry['weight']);
    classes.add({
      'id': id,
      'name': name.isEmpty ? 'Untitled Class' : name,
      'icon': icon,
      'iconUrl': safeCategoryIconUrl(iconUrl),
      'color': RegExp(r'^#[A-F0-9]{6}$').hasMatch(color) ? color : '#A78BFA',
      'weight': jsOut((w.isNaN || w == 0 ? 1.0 : w.toDouble()).clamp(1.0, 5.0)),
      'enabled': entry['enabled'] != false,
      'categoryIds': ids,
    });
  }
  return {
    'enabled': s['enabled'] == true,
    'strength': strength,
    'avoidRepeat': s['avoidRepeat'] != false,
    'rewardNeglect': s['rewardNeglect'] != false,
    'freshInfluence': s['freshInfluence'] != false,
    'adaptAmount': s['adaptAmount'] == true,
    'classes': classes,
  };
}

/// `v480SaveClass`: adds or replaces one class; its categories leave any other class.
Map<String, dynamic> saveCategoryClass(Map<String, dynamic> prefs, Map<String, dynamic> item) {
  final classes = [for (final c in asList(prefs['classes'])) Map<String, dynamic>.of(asMap(c)!)];
  final i = classes.indexWhere((c) => c['id'] == item['id']);
  if (i >= 0) {
    classes[i] = item;
  } else {
    classes.add(item);
  }
  final members = asList(item['categoryIds']).map(jsStr).toSet();
  for (final g in classes) {
    if (g['id'] != item['id']) g['categoryIds'] = [for (final c in asList(g['categoryIds'])) if (!members.contains(jsStr(c))) c];
  }
  return {...prefs, 'classes': classes};
}
