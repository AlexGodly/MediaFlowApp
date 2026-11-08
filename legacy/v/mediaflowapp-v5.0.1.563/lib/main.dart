import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/config.dart';
import 'src/data/app_prefs.dart';
import 'src/platform/desktop_tray.dart';
import 'src/platform/discord_presence.dart';
import 'src/platform/notifications.dart';
import 'src/ui/app.dart';
import 'src/ui/theme_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPrefs.instance.load();
  // Open in the theme last used on this device.
  ThemeController.instance.restore();
  try {
    await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabasePublishableKey);
  } catch (e) {
    // Offline start: the saved session is still read from the device.
    debugPrint('Supabase initialisation: $e');
  }
  // Windows: tray icon, close to tray, start with Windows.
  await DesktopTray.instance.init(args);
  unawaited(AppNotifications.instance.init());
  // Discord Rich Presence (official Social SDK, when this build has it).
  unawaited(DiscordPresence.instance.start());
  runApp(const MediaFlowApp());
}
