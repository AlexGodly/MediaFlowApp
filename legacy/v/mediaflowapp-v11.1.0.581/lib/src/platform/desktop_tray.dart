// Windows: a tray icon, keep running in the tray when the window is closed,
// start with Windows, and start minimised. Device settings ("This app").

import 'dart:async';
import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../data/app_prefs.dart';

class DesktopTray with TrayListener, WindowListener {
  DesktopTray._();
  static final DesktopTray instance = DesktopTray._();

  bool _ready = false;

  /// The window was hidden to the tray (true) or shown again (false).
  void Function(bool hidden)? onHiddenChanged;

  /// Whether the window is hidden in the tray right now.
  bool hidden = false;

  /// Called by the tray menu's "Sync now".
  void Function()? onSyncNow;

  /// Called by the tray menu's recovery items ('pause' | 'resume' | 'stop').
  void Function(String action)? onBackgroundAction;

  /// A recovery is running: closing the window keeps MediaFlow in the tray
  /// until it finishes, even when "keep running in the tray" is off.
  bool _busy = false;
  String _status = '';
  bool _paused = false;

  static bool get supported => Platform.isWindows;

  bool get closeToTray => AppPrefs.instance.get<bool>('trayCloseToTray', false);
  bool get startWithWindows => AppPrefs.instance.get<bool>('trayStartWithWindows', false);
  bool get startMinimized => AppPrefs.instance.get<bool>('trayStartMinimized', false);

  /// [args]: the app's start arguments ("--minimized" when Windows starts it).
  Future<void> init(List<String> args) async {
    if (!supported || _ready) return;
    try {
      await windowManager.ensureInitialized();
      launchAtStartup.setup(appName: 'MediaFlow', appPath: Platform.resolvedExecutable, args: const ['--minimized']);
      windowManager.addListener(this);
      trayManager.addListener(this);
      await trayManager.setIcon('assets/branding/mediaflow-tray.ico');
      await trayManager.setToolTip('MediaFlow');
      await _menu();
      await windowManager.setPreventClose(closeToTray);
      _ready = true;
      if (args.contains('--minimized') && startMinimized && closeToTray) {
        await windowManager.hide();
        hidden = true;
        onHiddenChanged?.call(true);
      }
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> setCloseToTray(bool on) async {
    await AppPrefs.instance.set('trayCloseToTray', on);
    if (_ready) await windowManager.setPreventClose(on || _busy);
  }

  Future<void> _menu() => trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Open MediaFlow'),
        MenuItem(key: 'sync', label: 'Sync now'),
        if (_busy) ...[
          MenuItem.separator(),
          MenuItem(key: 'status', label: _status, disabled: true),
          MenuItem(key: _paused ? 'resume' : 'pause', label: _paused ? 'Resume recovery' : 'Pause recovery'),
          MenuItem(key: 'stop', label: 'Stop recovery'),
        ],
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit MediaFlow'),
      ]));

  /// Shows a running recovery in the tray ([status] null: nothing runs).
  Future<void> setBackground(String? status, {bool paused = false}) async {
    if (!_ready) return;
    final busy = status != null;
    final changed = busy != _busy || paused != _paused || (status ?? '') != _status;
    if (!changed) return;
    final menuChanged = busy != _busy || paused != _paused;
    _busy = busy;
    _paused = paused;
    _status = status ?? '';
    try {
      await trayManager.setToolTip(busy ? 'MediaFlow · $_status' : 'MediaFlow');
      if (menuChanged || busy) await _menu();
      await windowManager.setPreventClose(closeToTray || _busy);
    } catch (_) {}
  }

  Future<void> setStartWithWindows(bool on) async {
    await AppPrefs.instance.set('trayStartWithWindows', on);
    try {
      on ? await launchAtStartup.enable() : await launchAtStartup.disable();
    } catch (_) {}
  }

  Future<void> setStartMinimized(bool on) => AppPrefs.instance.set('trayStartMinimized', on);

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
    hidden = false;
    onHiddenChanged?.call(false);
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.close();
  }

  @override
  void onWindowClose() {
    if (closeToTray || _busy) {
      unawaited(windowManager.hide());
      hidden = true;
        onHiddenChanged?.call(true);
    } else {
      unawaited(_quit());
    }
  }

  @override
  void onTrayIconMouseDown() => unawaited(_show());

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_show());
      case 'sync':
        onSyncNow?.call();
      case 'pause' || 'resume' || 'stop':
        onBackgroundAction?.call(menuItem.key!);
      case 'quit':
        unawaited(_quit());
    }
  }
}
