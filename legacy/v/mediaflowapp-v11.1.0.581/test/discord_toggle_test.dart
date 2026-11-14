// 10.0.0: turning Discord on, off and on again quickly applies the choices
// one after another and ends with the last one (it crashed in Discord's SDK).

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/app_prefs.dart';
import 'package:mediaflow/src/platform/discord_presence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('rapid on/off/on ends on, in order, without throwing', () async {
    AppPrefs.instance.reset();
    final d = DiscordPresence.instance;
    final all = [d.setEnabled(true), d.setEnabled(false), d.setEnabled(true), d.setEnabled(false), d.setEnabled(true)];
    await Future.wait(all);
    expect(d.enabled, isTrue);
    await d.setEnabled(false);
    expect(d.enabled, isFalse);
    expect(d.connected, isFalse);
  });
}
