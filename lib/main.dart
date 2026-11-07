import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/config.dart';
import 'src/data/app_prefs.dart';
import 'src/ui/app.dart';
import 'src/ui/theme_controller.dart';

Future<void> main() async {
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
  runApp(const MediaFlowApp());
}
