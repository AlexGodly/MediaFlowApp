// Time spent in the MediaFlow app counts for XP like time on the website
// (website v334 active time: no idle timeout, no daily cap; v561 stores the
// app's time apart from the website's). Since 6.0.0 (website v565) it keeps
// counting while the app is idle, minimised, in the tray or in the background,
// and stops only when the app is closed. A gap longer than 3 minutes means the
// system suspended the app (phones do this in the background): that gap is not
// active time; it is credited as away time instead, like a frozen website tab.
// Saved every minute and when the app goes to the background.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../data/account_controller.dart';
import '../data/account_ops.dart';
import '../util/js.dart';

class AppTime with WidgetsBindingObserver {
  AppTime._();
  static final AppTime instance = AppTime._();

  AccountController? _account;
  Timer? _tick;
  DateTime? _since; // counting since (null when not on screen)
  int _unsaved = 0; // ms counted but not saved yet
  String _day = '';
  DateTime _lastSave = DateTime.now();
  bool _observing = false;

  static const _tickEvery = Duration(seconds: 15);
  static const _saveEvery = Duration(minutes: 1);
  static const frozenMs = 3 * 60 * 1000;

  String get platform => Platform.operatingSystem;

  void attach(AccountController account) {
    if (identical(_account, account)) return;
    _flush();
    _account = account;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached) _start();
  }

  void detach(AccountController account) {
    if (!identical(_account, account)) return;
    _stop();
    _flush();
    _account = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive: // visible but not focused
        _count();
        _start();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // Still running: keep counting, but save now in case the system stops the app.
        _count();
        _flush();
      case AppLifecycleState.detached:
        _stop();
        _flush();
    }
  }

  void _start() {
    if (_account == null || _since != null) return;
    _since = DateTime.now();
    _tick ??= Timer.periodic(_tickEvery, (_) => _count());
  }

  void _stop() {
    _count();
    _since = null;
    _tick?.cancel();
    _tick = null;
  }

  /// Adds the time since the last tick (one day at a time, in UTC like the website).
  void _count() {
    final since = _since;
    if (since == null) return;
    final now = DateTime.now();
    final day = isoDateUtc(now.millisecondsSinceEpoch);
    if (_day.isNotEmpty && day != _day) _flush();
    _day = day;
    final delta = now.difference(since).inMilliseconds;
    _since = now;
    // Suspended by the system or asleep: not active time (website v565: 3 minutes).
    if (delta <= 0 || delta > frozenMs) return;
    _unsaved += delta;
    if (now.difference(_lastSave) >= _saveEvery) _flush();
  }

  void _flush() {
    final account = _account, ms = _unsaved;
    _lastSave = DateTime.now();
    if (account == null || ms < 1000 || _day.isEmpty || account.view == null) return;
    _unsaved = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    unawaited(account.perform(
      AppTimeOp(id: mediaFlowUid(now), day: _day, ms: ms, platform: platform, at: now),
      delay: const Duration(minutes: 2),
      quiet: true, // 7.0.0: once a minute, without rebuilding every open screen
    ));
  }
}
