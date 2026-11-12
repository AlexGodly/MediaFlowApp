import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../data/local_cache.dart';
import '../data/metadata_search.dart' show providerGateway;
import '../data/ratings_refresh.dart';
import '../data/supabase_cloud.dart';
import '../platform/app_time.dart';
import '../platform/app_shortcuts.dart';
import '../platform/background_work.dart';
import '../platform/desktop_tray.dart';
import '../platform/device_report.dart';
import '../platform/discord_presence.dart';
import '../platform/notifications.dart';
import 'home_shell.dart';
import 'presence.dart';
import 'sign_in_screen.dart';
import 'theme.dart';
import 'theme_controller.dart';

class MediaFlowApp extends StatelessWidget {
  const MediaFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The account's theme (the website's theme system): the whole app is
    // redrawn when it changes.
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final theme = MF.theme();
        return MaterialApp(
          title: 'MediaFlow',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: theme,
          themeMode: MF.light ? ThemeMode.light : ThemeMode.dark,
          builder: (context, child) => PresenceIdleWatcher(child: ThemeRebuilder(child: child ?? const SizedBox.shrink())),
          home: const AuthGate(),
        );
      },
    );
  }
}

/// Shows sign-in, or the app for the signed-in account. A device that was
/// signed in before opens straight into that account even offline or after the
/// session expired; only an explicit sign-out returns to the sign-in screen.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  /// Set just before an explicit sign-out (Account → Sign out).
  static bool signingOut = false;
  static _AuthGateState? _current;

  /// Explicit sign-out: removes this account's data from the device and returns
  /// to the sign-in screen, online or offline.
  static Future<void> signOut(AccountController account) async {
    await account.forget();
    await LastAccount.clear();
    signingOut = true;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Offline: the device sign-out still applies.
    }
    signingOut = false;
    _current?._detach();
  }

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _sub;
  AccountController? _account;
  bool _starting = true;

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // Supabase could not start (offline first launch); retried on resume.
    }
  }

  @override
  void initState() {
    super.initState();
    AuthGate._current = this;
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    await Future<void>.value(); // after initState: setState is allowed from here on
    final client = _client;
    final user = client?.auth.currentUser;
    if (user != null) {
      _attach(user.id, user.email ?? '');
    } else {
      final last = await LastAccount.read();
      if (last != null) _attach(last.userId, last.email);
    }
    if (mounted) setState(() => _starting = false);
    _sub = client?.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut) {
        if (AuthGate.signingOut) {
          _detach();
        } else {
          // Session ended elsewhere/expired: keep working on the device copy.
          final account = _account;
          if (account != null) {
            account.needsSignIn = true;
            account.sync();
          }
        }
        return;
      }
      final user = event.session?.user ?? client.auth.currentUser;
      if (user == null) return;
      if (_account?.userId == user.id) {
        // Signed in again (e.g. after the session expired): upload what waited.
        _account!.needsSignIn = false;
        _account!.sync();
      } else {
        _attach(user.id, user.email ?? '');
      }
    }, onError: (_) {});
  }

  void _detach() {
    final old = _account;
    if (old == null || !mounted) return;
    AppTime.instance.detach(old);
    RatingsRefresh.instance.stopAuto();
    setState(() => _account = null);
    old.dispose();
  }

  /// This install's id on per-record cloud rows (kept across launches).
  static String _deviceId() {
    final saved = AppPrefs.instance.get<String>('recordDeviceId', '');
    if (saved.isNotEmpty) return saved;
    final r = Random.secure();
    final id = 'app-${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
    unawaited(AppPrefs.instance.set('recordDeviceId', id));
    return id;
  }

  void _attach(String userId, String email) {
    // TMDB covers go through MediaFlow's provider gateway as this account
    // (the TMDB key stays on the server, as on the website).
    providerGateway = (body) async =>
        (await Supabase.instance.client.functions.invoke('mediaflow-api-gateway', body: body)).data;
    if (_account?.userId == userId) return;
    final old = _account;
    final account = AccountController(
      userId: userId,
      email: email,
      cloud: SupabaseCloud(() => Supabase.instance.client),
      cache: FileAccountCache(),
      deviceId: _deviceId(),
    )..startAutoPull();
    ThemeController.instance.attach(account);
    AppNotifications.instance.attach(account);
    AppTime.instance.attach(account);
    DeviceReport.instance.attach(account);
    BackgroundWork.instance.attach(account);
    AppShortcuts.instance.attach(account);
    unawaited(AppShortcuts.instance.init());
    RatingsRefresh.instance.startAuto(account);
    DesktopTray.instance.onSyncNow = () => unawaited(account.sync());
    if (mounted) {
      setState(() => _account = account);
    } else {
      _account = account;
    }
    old?.dispose();
    LastAccount.write(userId, email);
    account.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (AppPrefs.instance.get<bool>('syncOnResume', true)) _account?.sync();
      _account?.startAutoPull();
      DiscordPresence.instance.resume();
    }
    // Leaving the app: upload an unsaved logging draft so the website sees it.
    // (Inactive = still on screen but not focused, e.g. a Windows window
    // next to the website: it keeps following live changes.)
    if (state == AppLifecycleState.inactive) _account?.flushDraft();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _account?.stopAutoPull();
      _account?.flushDraft();
      // Phones suspend apps in the background: don't leave a stale status.
      if (DiscordPresence.mobile) DiscordPresence.instance.pause();
    }
  }

  @override
  void dispose() {
    if (identical(AuthGate._current, this)) AuthGate._current = null;
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _account?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    if (account == null) {
      if (_starting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return const SignInScreen();
    }
    final start = Section.values.where((s) => s.name == AppPrefs.instance.get<String>('startTab', 'log')).firstOrNull ?? Section.log;
    return HomeShell(account: account, start: start);
  }
}
