// The category editor writes what the website writes (fixtures from
// tool/website_reference/generate_category_goldens.mjs, which runs the
// website's own save / delete / restore / clear code).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/records.dart' show jsStringify;
import 'package:mediaflow/src/logic/categories.dart';

void main() {
  final fx = jsonDecode(File('test/fixtures/category-golden.json').readAsStringSync()) as Map<String, dynamic>;

  test('defaults, colours and icons are the website\'s', () {
    final c = fx['constants'] as Map<String, dynamic>;
    expect(jsStringify(kDefaultCategories), jsStringify(c['defaults']));
    expect(kColorChoices, c['colors']);
    expect(kIconChoices, c['icons']);
  });

  for (final raw in fx['scenarios'] as List) {
    final sc = (raw as Map).cast<String, dynamic>();
    test('categories: ${sc['name']}', () {
      final state = (jsonDecode(jsonEncode(fx['base'])) as Map).cast<String, dynamic>();
      var n = 0;
      String uid() => 'u${++n}';
      final actions = sc['actions'] as List, want = sc['expected'] as List;
      for (var i = 0; i < actions.length; i++) {
        final a = (actions[i] as Map).cast<String, dynamic>();
        final now = a['at'] as int;
        String? toast;
        switch (a['op']) {
          case 'save':
            final f = (a['form'] as Map).cast<String, dynamic>();
            String t(String k) => '${f[k] ?? ''}';
            final r = saveCategory(
                state,
                (a['id'] as String).isEmpty ? null : a['id'] as String,
                CategoryForm(
                  name: t('m-name'),
                  icon: t('m-icon'),
                  iconUrl: t('m-icon-url'),
                  missingCover: t('m-missing-default-cover'),
                  type: t('m-type'),
                  unit: t('m-unit'),
                  target: t('m-target'),
                  weight: t('m-weight'),
                  hours: t('m-runtime-hours'),
                  minutes: t('m-runtime-minutes'),
                  seconds: t('m-runtime-seconds'),
                  seasonal: f['m-seasonal'] == true,
                  color: t('m-color'),
                  enabled: f['m-enabled'] == true,
                ),
                now,
                uid);
            toast = r.error;
          case 'delete':
            deleteCategory(state, a['id'] as String, now);
          case 'restoreDeleted':
            toast = restoreDeletedCategory(state, now);
          case 'restoreDefaults':
            toast = restoreDefaultCategories(state);
          case 'clear':
            toast = clearCategory(state, a['id'] as String, now, uid);
        }
        final w = (want[i] as Map).cast<String, dynamic>();
        final ws = (w['state'] as Map).cast<String, dynamic>();
        for (final k in const ['categories', 'categoryOrder', 'settings', 'categoryRecovery', 'library', 'activityLog']) {
          expect(jsStringify(state[k]), jsStringify(ws[k]), reason: 'step $i (${a['op']}): $k');
        }
        if (a['op'] != 'delete' && (w['toast'] as String).isNotEmpty) expect(toast, w['toast'], reason: 'step $i message');
      }
    });
  }

  test('a saved category fills the editor back (HH:MM:SS from secondsPerUnit)', () {
    final f = CategoryForm.of({'name': 'A', 'secondsPerUnit': 1420, 'minutesPerUnit': 23.6, 'target': 6, 'weight': 5, 'color': '#FF5D9E'});
    expect((f.hours, f.minutes, f.seconds), ('0', '23', '40'));
    expect(f.target, '6');
    final g = CategoryForm.of({'minutesPerUnit': 100});
    expect((g.hours, g.minutes, g.seconds), ('1', '40', '0'));
  });
}
