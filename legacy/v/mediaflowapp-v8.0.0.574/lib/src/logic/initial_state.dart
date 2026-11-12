// A brand-new account's first save, exactly as the website makes it (loadAll
// with no data → snapshot()): default categories and settings, an empty
// Library and History. test/initial_state_golden_test.dart.

import 'dart:convert';

import '../util/js.dart';
import 'categories.dart' show kDefaultCategories;
import 'default_settings.g.dart';

Map<String, dynamic> newAccountState(int now) {
  final defaults = (jsonDecode(kDefaultSettingsJson) as Map).cast<String, dynamic>();
  final settings = <String, dynamic>{...defaults};
  // loadAll's nested merges (fresh copies of the defaults).
  settings['backup'] = {...?asMap(defaults['backup'])};
  final leveling = <String, dynamic>{...?asMap(defaults['leveling'])};
  leveling['unitXP'] = {...?asMap(asMap(defaults['leveling'])?['unitXP'])};
  leveling['rotationMultiplier'] = {...?asMap(asMap(defaults['leveling'])?['rotationMultiplier'])};
  settings['leveling'] = leveling;
  final categories = kDefaultCategories;
  return {
    'categories': categories,
    'categoryOrder': [for (final c in categories) c['id']],
    'library': <dynamic>[],
    'sessions': <dynamic>[],
    'settings': settings,
    'currentTask': null,
    'sessionActive': false,
    'profilePicture': '',
    'stopwatch': {'running': false, 'startedAt': 0, 'elapsed': 0, 'resetValue': 0},
    'malLink': {'username': '', 'mode': 'anime'},
    'xpLedger': {'libraryAdditions': <String, dynamic>{}},
    'completionTimeline': <dynamic>[],
    'activityLog': <dynamic>[],
    'migrations': <String, dynamic>{},
    'savedAt': now,
  };
}
