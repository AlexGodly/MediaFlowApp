// Custom navigation: dock 3–5 pages, everything else in More, new pages
// join More and the end of the sidebar, Settings can't disappear.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/ui/app_nav.dart';
import 'package:mediaflow/src/ui/home_shell.dart' show Section;

void main() {
  test('defaults match the old layout', () {
    final n = AppNav.of(null);
    expect(n.dock, kDefaultDock);
    expect(n.more.first, Section.collections);
    expect(n.desktop, Section.values);
    expect({...n.dock, ...n.more}, Section.values.toSet());
  });

  test('saved order is kept; unknown and repeated pages are dropped; new pages join More', () {
    final n = AppNav.of({
      kAppNavKey: {
        'dock': ['library', 'oldSystem', 'library', 'gone', 'settings'],
        'more': ['account', 'log', 'settings'],
        'desktop': ['stats', 'log'],
      },
    });
    expect(n.dock, [Section.library, Section.oldSystem, Section.settings]);
    expect(n.more.take(2), [Section.account, Section.log]);
    expect(n.more, isNot(contains(Section.settings)), reason: 'it is in the dock');
    expect(n.more.toSet().length + n.dock.length, Section.values.length);
    expect(n.desktop.take(2), [Section.stats, Section.log]);
    expect(n.desktop.toSet(), Section.values.toSet());
    expect(AppNav.of({kAppNavKey: n.toJson()}).toJson(), n.toJson());
  });

  test('the dock holds 3 to 5 pages', () {
    expect(AppNav.of({kAppNavKey: {'dock': ['log', 'library']}}).dock, kDefaultDock);
    expect(AppNav.of({kAppNavKey: {'dock': ['log', 'library', 'history', 'extras', 'stats', 'order']}}).dock.length, 5);
  });
}
