// Discord Rich Presence must keep up with the app (owner's rule, CLAUDE.md):
// every section has a status, every screen opened on top of the app sets its
// own, and the privacy settings hide what they promise to hide.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/platform/discord_presence.dart';
import 'package:mediaflow/src/ui/home_shell.dart' show Section;
import 'package:mediaflow/src/ui/presence.dart';

void main() {
  test('every section of the app has a Discord status', () {
    for (final s in Section.values) {
      final info = sectionPresence(s);
      expect(info.details.trim().length, greaterThanOrEqualTo(2), reason: '$s');
    }
  });

  test('every screen opened on top of the app sets its Discord status', () {
    final files = Directory('lib/src/ui').listSync().whereType<File>().where((f) => f.path.endsWith('.dart')).toList();
    final source = {for (final f in files) f.path: f.readAsStringSync()};
    // Screens pushed with a route…
    final pushed = <String>{};
    final route = RegExp(r'MaterialPageRoute(?:<[^>]*>)?\(\s*builder: \([^)]*\) => (?:const )?([A-Z]\w+)\(');
    for (final s in source.values) {
      for (final m in route.allMatches(s)) {
        pushed.add(m[1]!);
      }
    }
    expect(pushed, isNotEmpty);
    for (final name in pushed) {
      final file = source.entries.firstWhere((e) => RegExp('class $name\\b').hasMatch(e.value), orElse: () => const MapEntry('', '')).key;
      expect(file, isNotEmpty, reason: '$name not found');
      final cls = source[file]!;
      final start = cls.indexOf(RegExp('class $name\\b'));
      // The screen's own code (up to the next top-level screen class) must set a status.
      final end = cls.indexOf(RegExp(r'\nclass [A-Z]\w*(Screen|Editor) '), start + 1);
      final body = cls.substring(start, end < 0 ? cls.length : end);
      final state = RegExp('class _${name}State\\b[\\s\\S]*?(?=\\nclass |\$)').firstMatch(cls)?[0] ?? '';
      expect('$body$state'.contains('PresenceScope') || '$body$state'.contains('PresenceHub'), isTrue,
          reason: '$name ($file) must set its Discord status (PresenceScope / PresenceHub) — see CLAUDE.md');
    }
    // …and every *_screen.dart file is either a section page or sets a status.
    for (final e in source.entries.where((e) => e.key.endsWith('_screen.dart'))) {
      final isSection = RegExp(r'class (Log|Library|History|Extras|Collections|Order|Stats|Settings|Account)Screen\b').hasMatch(e.value);
      expect(isSection || e.value.contains('PresenceScope') || e.value.contains('PresenceHub'), isTrue,
          reason: '${e.key} must set its Discord status — see CLAUDE.md');
    }
  });

  test('privacy: titles and covers are hidden unless "everything" is chosen', () {
    const info = PresenceInfo(
      details: 'Logging Frieren',
      genericDetails: 'Logging anime',
      state: 'Episode 12 / 28',
      title: 'Frieren',
      cover: 'https://example.com/frieren.jpg',
      categoryName: 'Anime',
      categoryId: 'anime',
      kind: PresenceKind.watching,
    );
    expect(info.key, contains('Frieren'));
  });
}
