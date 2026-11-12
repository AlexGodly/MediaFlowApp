import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/logic/presence_templates.dart';
import 'package:mediaflow/src/platform/discord_ffi.dart' show ActivityType;
import 'package:mediaflow/src/platform/discord_presence.dart';

void main() {
  final modified = {
    'all': {'details': 'Hello {level}', 'state': 'Fixed', 'type': 'watching', 'largeImage': '{logo}'},
    'library': {'details': 'Shelving', 'name': 'My Shelf'},
  };

  test('Advanced RPC mode modifies the automatic status per scenario', () {
    final d = DiscordPresence.instance;
    final on = PresenceConfig({'advanced': true, 'modified': modified});
    final logging = d.effective(using: on, situation: 'logging')!;
    expect(logging.details, 'Hello');
    expect(logging.state, 'Fixed');
    expect(logging.type, ActivityType.watching);
    final library = d.effective(using: on, situation: 'library')!;
    expect(library.details, 'Shelving');
    expect(library.name, 'My Shelf');
  });

  test('off: MediaFlow\'s own status, modifications kept', () {
    final off = PresenceConfig({'advanced': false, 'modified': modified});
    final a = DiscordPresence.instance.effective(using: off, situation: 'library')!;
    expect(a.details, isNot('Shelving'));
    expect(off.modifiedSituations, containsAll(['all', 'library']));
  });

  test('Modify starts from the automatic status as fields', () {
    final f = PresenceConfig(const {}).modifyFields('library');
    expect(f['details'], isNotEmpty);
    expect(f.keys, containsAll(['name', 'details', 'state', 'largeImage', 'buttons']));
  });

  test('Show progress off hides progress placeholders', () {
    final c = PresenceConfig({'showProgress': false});
    expect(c.showProgress, isFalse);
    expect(PresenceConfig(const {}).showProgress, isTrue);
  });
}
