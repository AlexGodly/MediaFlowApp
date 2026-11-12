// Records this install's app version in the account, so the website's
// "Get MediaFlow" popup (website v565) can show each device against the
// latest release: settings.mf565AppDevices[deviceId] =
// {platform, version, label, lastSeen}. Written once per new version and at
// most once a day otherwise, never on every launch.

import 'dart:async';
import 'dart:io';

import '../config.dart';
import '../data/account_controller.dart';
import '../util/js.dart';

class DeviceReport {
  DeviceReport._();
  static final DeviceReport instance = DeviceReport._();

  static const _refreshEvery = Duration(days: 1);
  AccountController? _account;
  bool _done = false;

  void attach(AccountController account) {
    if (identical(_account, account)) return;
    _account?.removeListener(_check);
    _account = account;
    _done = false;
    account.addListener(_check);
    _check();
  }

  /// 'android' | 'windows' | 'ios' — the names the website uses.
  static String get platform => Platform.isAndroid
      ? 'android'
      : Platform.isIOS
          ? 'ios'
          : Platform.isWindows
              ? 'windows'
              : Platform.operatingSystem;

  static String get label {
    if (Platform.isWindows) {
      final host = Platform.localHostname.trim();
      return host.isEmpty ? 'Windows PC' : host;
    }
    if (Platform.isIOS) return 'iPhone / iPad';
    if (Platform.isAndroid) return 'Android phone';
    return 'MediaFlow app';
  }

  /// The entry to write, or null when the saved one is still current.
  static Map<String, dynamic>? entryToWrite(Object? saved, {required String version, required int now}) {
    final m = asMap(saved);
    final fresh = m != null &&
        jsStr(m['version']) == version &&
        jsStr(m['platform']) == platform &&
        now - jsNum(m['lastSeen']) < _refreshEvery.inMilliseconds;
    if (fresh) return null;
    return {'platform': platform, 'version': version, 'label': label, 'lastSeen': now};
  }

  void _check() {
    final account = _account;
    final view = account?.view;
    if (_done || account == null || view == null) return;
    _done = true;
    final devices = asMap(asMap(view.state['settings'])?['mf565AppDevices']);
    final entry = entryToWrite(devices?[account.deviceId],
        version: kAppVersionLabel, now: DateTime.now().millisecondsSinceEpoch);
    if (entry != null) unawaited(account.setSetting(['mf565AppDevices', account.deviceId], entry, xp: false));
  }
}
