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

  /// Called by the tray menu's "Sync now".
  void Function()? onSyncNow;

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
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Open MediaFlow'),
        MenuItem(key: 'sync', label: 'Sync now'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit MediaFlow'),
      ]));
      await windowManager.setPreventClose(closeToTray);
      _ready = true;
      if (args.contains('--minimized') && startMinimized && closeToTray) {
        await windowManager.hide();
      }
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> setCloseToTray(bool on) async {
    await AppPrefs.instance.set('trayCloseToTray', on);
    if (_ready) await windowManager.setPreventClose(on);
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
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.close();
  }

  @override
  void onWindowClose() {
    if (closeToTray) {
      unawaited(windowManager.hide());
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
      case 'quit':
        unawaited(_quit());
    }
  }
}
