// 10.0.0: category icons are always drawn with CategoryBadge (the real icon,
// emoji or a letter in the category colour), never as text like "🖼️ Name".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no screen writes a category icon into text', () {
    final bad = <String>[];
    for (final f in Directory('lib/src/ui').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r"\$\{(c|cat|category)\.icon\}").hasMatch(lines[i])) bad.add('${f.path}:${i + 1}');
      }
    }
    expect(bad, isEmpty, reason: 'use CategoryBadge(category) instead:\n${bad.join('\n')}');
  });

  test('category lists in filters follow the order and layout', () {
    final bad = <String>[];
    for (final f in Directory('lib/src/ui').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('settings_screen.dart') || f.path.endsWith('old_system_screen.dart')) continue; // editing categories themselves
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('viewChoices(')) continue; // already follows the layout
        if (RegExp(r"for \(final c in (widget\.)?view\.categories\) \(c\.id").hasMatch(lines[i])) bad.add('${f.path}:${i + 1}');
      }
    }
    expect(bad, isEmpty, reason: 'use filterCategories(view) / setCategories(view):\n${bad.join('\n')}');
  });
}
