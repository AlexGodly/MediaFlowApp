// Time spent in the MediaFlow app counts for XP like time on the website
// (website v334 active time: foreground time, no idle timeout, no daily cap;
// v561 stores the app's time apart from the website's). Counted while the app
// is on screen (also when it is visible but not focused, like a visible
// browser tab), saved every minute and when the app goes to the background.

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

  String get platform => Platform.operatingSystem;

  void attach(AccountController account) {
    if (identical(_account, account)) return;
    _flush();
    _account = account;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed || state == AppLifecycleState.inactive) _start();
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
        _start();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
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
    // A suspended timer (sleep) is not active time.
    if (delta <= 0 || delta > 5 * 60 * 1000) return;
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
    ));
  }
}
