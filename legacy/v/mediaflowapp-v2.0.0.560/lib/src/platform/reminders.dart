// The daily streak reminder: "you haven't logged today" at a time you choose,
// so the Day Streak doesn't break. A device setting (each device decides for
// itself). Android and iOS schedule it with the system; Windows shows it while
// MediaFlow is running (it can keep running in the tray).

import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../logic/progress_summary.dart' show computeDayStreak;
import '../util/js.dart';

class Reminders {
  Reminders._();
  static final Reminders instance = Reminders._();

  static const _id = 1;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _desktopTimer;
  AccountController? _account;
  String _last = '';

  bool get enabled => AppPrefs.instance.get<bool>('reminderOn', false);

  /// "HH:mm", default 20:00.
  ({int h, int m}) get time {
    final parts = AppPrefs.instance.get<String>('reminderTime', '20:00').split(':');
    final h = int.tryParse(parts.first) ?? 20, m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (h: h.clamp(0, 23).toInt(), m: m.clamp(0, 59).toInt());
  }

  bool get _supported => Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  Future<void> init() async {
    if (_ready || !_supported) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        windows: WindowsInitializationSettings(
          appName: 'MediaFlow',
          appUserModelId: 'AlexGodly.MediaFlow',
          guid: '6f1c3c7e-9a52-4f0e-9a8b-2b5d3c1e7a40',
        ),
      ));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Asks for permission to show notifications (Android 13+, iOS).
  Future<bool> requestPermission() async {
    await init();
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? true;
      }
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
      }
    } catch (_) {}
    return true;
  }

  Future<void> setEnabled(bool on) async {
    await AppPrefs.instance.set('reminderOn', on);
    if (on) await requestPermission();
    _last = '';
    await refresh();
  }

  Future<void> setTime(int h, int m) async {
    await AppPrefs.instance.set('reminderTime', '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
    _last = '';
    await refresh();
  }

  /// Follows the account: a log today moves the reminder to tomorrow.
  void attach(AccountController account) {
    if (identical(_account, account)) return;
    _account?.removeListener(_onAccount);
    _account = account;
    account.addListener(_onAccount);
    _onAccount();
  }

  void _onAccount() => unawaited(refresh());

  Future<void> refresh() async {
    if (!_supported) return;
    await init();
    if (!_ready) return;
    final sessions = asList(_account?.view?.state['sessions']);
    final now = DateTime.now();
    final loggedToday = computeDayStreak(sessions, now.millisecondsSinceEpoch) > 0;
    final t = time;
    var at = DateTime(now.year, now.month, now.day, t.h, t.m);
    if (loggedToday || !at.isAfter(now)) at = at.add(const Duration(days: 1));
    // The streak that is at stake: days in a row up to yesterday.
    final streak = computeDayStreak(sessions, now.subtract(const Duration(days: 1)).millisecondsSinceEpoch);
    final body = loggedToday
        ? "Keep your ${streak + 1}-day streak going: log something today."
        : streak > 0
            ? "You haven't logged today. Log something to keep your $streak-day streak."
            : "You haven't logged anything today.";
    final key = '$enabled|${at.toIso8601String()}|$body';
    if (key == _last) return;
    _last = key;
    _desktopTimer?.cancel();
    try {
      await _plugin.cancel(_id);
    } catch (_) {}
    if (!enabled) return;
    const title = 'MediaFlow';
    if (Platform.isWindows) {
      // Shown while MediaFlow runs (it can stay in the tray).
      _desktopTimer = Timer(at.difference(now), () async {
        final again = asList(_account?.view?.state['sessions']);
        if (computeDayStreak(again, DateTime.now().millisecondsSinceEpoch) == 0) {
          try {
            await _plugin.show(_id, title, body, const NotificationDetails(windows: WindowsNotificationDetails()));
          } catch (_) {}
        }
        _last = '';
        unawaited(refresh());
      });
      return;
    }
    try {
      await _plugin.zonedSchedule(
        _id,
        title,
        body,
        tz.TZDateTime.from(at.toUtc(), tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails('streak', 'Streak reminder',
              channelDescription: "A daily reminder when you haven't logged yet", importance: Importance.defaultImportance),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }
}
