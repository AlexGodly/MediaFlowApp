import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/config.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabasePublishableKey);
  } catch (e) {
    // Offline start: the saved session is still read from the device.
    debugPrint('Supabase initialisation: $e');
  }
  runApp(const MediaFlowApp());
}
