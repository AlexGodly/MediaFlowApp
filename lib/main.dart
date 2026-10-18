import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/mediaflow_shell.dart';
import 'design_system/mediaflow_theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/full_app/full_mediaflow_screen.dart';
import 'services/mediaflow_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://wgeijxfdpgehesxialxm.supabase.co',
  );
  const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_d2P0qZlvGZOSqcUzEg3BNg_3wQsHY_M',
  );
  final configured = endpoint.isNotEmpty && publishableKey.isNotEmpty;
  if (configured) {
    await Supabase.initialize(url: endpoint, publishableKey: publishableKey);
  }
  runApp(MediaFlowApp(configured: configured));
}

class MediaFlowApp extends StatelessWidget {
  const MediaFlowApp({super.key, this.configured = false});
  final bool configured;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MediaFlow',
    debugShowCheckedModeBanner: false,
    theme: MediaFlowTheme.build(MediaFlowAppearance.dark),
    home: const String.fromEnvironment('MEDIAFLOW_APP_MODE') == 'native-preview'
        ? (configured
            ? AuthGate(auth: MediaFlowAuth(Supabase.instance.client))
            : const MediaFlowShell())
        : const FullMediaFlowScreen(),
  );
}
