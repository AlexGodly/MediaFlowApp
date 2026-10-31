import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/account_controller.dart';
import '../data/local_cache.dart';
import '../data/supabase_cloud.dart';
import 'home_shell.dart';
import 'sign_in_screen.dart';
import 'theme.dart';

class MediaFlowApp extends StatelessWidget {
  const MediaFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediaFlow',
      debugShowCheckedModeBanner: false,
      theme: MF.theme(),
      darkTheme: MF.theme(),
      themeMode: ThemeMode.dark,
      home: const AuthGate(),
    );
  }
}

/// Shows sign-in, or the app for the signed-in account.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _sub;
  AccountController? _account;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach(_client.auth.currentUser, initial: true);
    _sub = _client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        _attach(null);
      } else {
        _attach(event.session?.user ?? _client.auth.currentUser);
      }
    }, onError: (_) {});
  }

  void _attach(User? user, {bool initial = false}) {
    if (user == null) {
      final old = _account;
      if (old != null) {
        if (initial) {
          _account = null;
        } else {
          setState(() => _account = null);
        }
        old.dispose();
      }
      return;
    }
    if (_account?.userId == user.id) return;
    final old = _account;
    final account = AccountController(
      userId: user.id,
      email: user.email ?? '',
      cloud: SupabaseCloud(_client),
      cache: FileAccountCache(),
    );
    if (initial) {
      _account = account;
    } else {
      setState(() => _account = account);
    }
    old?.dispose();
    account.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _account?.sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _account?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    if (account == null) return const SignInScreen();
    return HomeShell(account: account);
  }
}
