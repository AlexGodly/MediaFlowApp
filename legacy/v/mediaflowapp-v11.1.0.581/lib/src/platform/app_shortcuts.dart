// Long-press shortcuts on the app icon (Android and iOS) and the Android
// home-screen widget. Both open MediaFlow on a page ("log", "add", "library",
// "recovery"); the home shell follows [AppShortcuts.request].

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:quick_actions/quick_actions.dart';

import '../data/account_controller.dart';
import '../logic/stats.dart';

class AppShortcuts {
  AppShortcuts._();
  static final AppShortcuts instance = AppShortcuts._();

  static const _channel = MethodChannel('mediaflow/background');

  /// The latest action and a counter (the same action twice still fires).
  final ValueNotifier<(String, int)?> request = ValueNotifier(null);
  int _n = 0;
  bool _ready = false;

  void ask(String action) => request.value = (action, ++_n);

  /// The app-icon shortcuts.
  Future<void> init() async {
    if (_ready || !(Platform.isAndroid || Platform.isIOS)) return;
    _ready = true;
    try {
      const qa = QuickActions();
      await qa.initialize(ask);
      await qa.setShortcutItems(const [
        ShortcutItem(type: 'log', localizedTitle: 'Log progress'),
        ShortcutItem(type: 'add', localizedTitle: 'Add title'),
        ShortcutItem(type: 'library', localizedTitle: 'Library'),
        ShortcutItem(type: 'recovery', localizedTitle: 'Recovery'),
      ]);
    } catch (_) {}
    await takeLaunchAction();
  }

  /// A widget button that opened the app (Android).
  Future<void> takeLaunchAction() async {
    if (!Platform.isAndroid) return;
    try {
      final a = await _channel.invokeMethod<String>('takeAction');
      if (a != null && a.isNotEmpty && a != 'open') ask(a);
    } catch (_) {}
  }

  // ---- the Android widget's numbers ----

  AccountController? _account;
  Timer? _throttle;
  String _sent = '';

  void attach(AccountController account) {
    if (!Platform.isAndroid || identical(_account, account)) return;
    _account?.removeListener(_onAccount);
    _account = account;
    account.addListener(_onAccount);
    _onAccount();
  }

  void _onAccount() {
    _throttle ??= Timer(const Duration(seconds: 4), () {
      _throttle = null;
      unawaited(_publish());
    });
  }

  Future<void> _publish() async {
    final view = _account?.view;
    if (view == null || !_account!.hasData) return;
    final data = <String, String>{};
    try {
      final m = StatsModel(view.state, DateTime.now());
      final mins = m.today.minutes.round();
      data['streak'] = m.streak > 0 ? '🔥 ${m.streak}-day streak' : 'No streak yet';
      data['today'] = 'Today: ${mins >= 60 ? '${(mins / 60).toStringAsFixed(1)} h' : '$mins min'} · Level ${m.level.level}';
    } catch (_) {
      data['streak'] = '';
      data['today'] = '';
    }
    // What you were last on: the most recently changed title in progress.
    final open = view.library.where((t) => !t.isCompleted && t.status != 'dropped' && t.progress > 0).toList()
      ..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    if (open.isEmpty) {
      data['title'] = view.state['sessionActive'] == true ? 'Logging session open' : 'Nothing in progress';
      data['progress'] = '';
    } else {
      final t = open.first;
      final unit = view.category(t.categoryId).unit;
      final word = switch (unit) {
        'episodes' => 'Episode',
        'chapters' => 'Chapter',
        'pages' => 'Page',
        'volumes' => 'Volume',
        'issues' => 'Issue',
        'tracks' => 'Track',
        _ => capitalized(unit),
      };
      final total = t.total;
      data['title'] = t.title;
      data['progress'] = '$word ${fmtNum(t.progress)}${total != null && total > 0 ? ' / ${fmtNum(total)}' : ''}';
    }
    final key = data.entries.map((e) => '${e.key}=${e.value}').join('|');
    if (key == _sent) return;
    _sent = key;
    try {
      await _channel.invokeMethod('widget', data);
    } catch (_) {}
  }

  static String fmtNum(double v) => v == v.truncateToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
  static String capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
