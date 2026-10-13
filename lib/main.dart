import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/mediaflow_shell.dart';
import 'features/auth/auth_gate.dart';
import 'services/mediaflow_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const endpoint = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final configured = endpoint.isNotEmpty && publishableKey.isNotEmpty;
  if (configured) {
    await Supabase.initialize(url: endpoint, anonKey: publishableKey);
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
    home: configured
        ? AuthGate(auth: MediaFlowAuth(Supabase.instance.client))
        : const MediaFlowShell(),
  );
}
