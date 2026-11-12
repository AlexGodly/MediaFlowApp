// Automatic Backups (website "AUTOMATIC BACKUPS", saveBackupNow +
// restartBackupTimer, with the v565 background XP). settings.backup =
// {enabled, interval (minutes), mode 'single'|'multiple', fileName,
// lastBackup}. The folder is this device's own choice (AppPrefs
// 'autoBackupFolder'), like the website keeps its folder in the browser.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../data/background_worker.dart';
import '../logic/data_transfer.dart';
import '../state/lazy_copy.dart';
import '../util/js.dart';

/// Builds the full backup, encodes it and writes it to [path]. Top-level so it
/// can run on the worker isolate.
Future<void> writeBackupFile(String path, Map<String, dynamic> state, DateTime now, String appVersion) async {
  final json = const JsonEncoder.withIndent('  ').convert(buildFullBackup(state, now, appVersion: appVersion));
  await File(path).writeAsString(json, flush: true);
}

class AutoBackup {
  AutoBackup._();
  static final AutoBackup instance = AutoBackup._();

  AccountController? _account;
  Timer? _timer;
  String _key = '';
  bool _writing = false;

  /// The last error, shown in Settings.
  String? lastError;

  void attach(AccountController account) {
    if (identical(_account, account)) return;
    _account?.removeListener(_check);
    _account = account;
    account.addListener(_check);
    _check();
  }

  static Map<String, dynamic> prefs(Map<String, dynamic>? settings) => {
        'enabled': false,
        'interval': 60,
        'mode': 'single',
        'fileName': 'mediaflow-backup.json',
        'lastBackup': 0,
        ...?asMap(settings?['backup']),
      };

  static int intervalMinutes(Map<String, dynamic> p) {
    final n = (jsNumOrNull(p['interval']) ?? 60).round();
    return n < 1 ? 60 : n;
  }

  /// This device's backup folder (default: Documents/MediaFlow Backups).
  static Future<Directory> folder() async {
    final chosen = AppPrefs.instance.get<String>('autoBackupFolder', '');
    if (chosen.isNotEmpty) return Directory(chosen);
    Directory? base;
    // Android: the app's folder on shared storage (visible in file managers).
    if (Platform.isAndroid) base = await getExternalStorageDirectory();
    base ??= await getApplicationDocumentsDirectory();
    return Directory('${base.path}${Platform.pathSeparator}MediaFlow Backups');
  }

  void _check() {
    final view = _account?.view;
    if (view == null) return;
    final p = prefs(asMap(view.state['settings']));
    final key = '${p['enabled']}|${intervalMinutes(p)}';
    if (key == _key) return;
    _key = key;
    _timer?.cancel();
    _timer = null;
    if (p['enabled'] != true) return;
    final every = Duration(minutes: intervalMinutes(p));
    _timer = Timer.periodic(every, (_) => unawaited(saveNow()));
    // Catch up when the last backup is older than one interval.
    final last = jsNum(p['lastBackup']);
    if (DateTime.now().millisecondsSinceEpoch - last >= every.inMilliseconds) {
      Timer(const Duration(seconds: 30), () => unawaited(saveNow()));
    }
  }

  /// Writes a backup now. Returns the file path, or null (see [lastError]).
  Future<String?> saveNow({bool manual = false}) async {
    final account = _account;
    final view = account?.view;
    if (account == null || view == null || _writing) return null;
    final p = prefs(asMap(view.state['settings']));
    if (!manual && p['enabled'] != true) return null;
    _writing = true;
    try {
      final dir = await folder();
      await dir.create(recursive: true);
      final now = DateTime.now();
      var name = p['mode'] == 'multiple' ? autoBackupFileName(now) : jsStr(p['fileName']).trim();
      if (name.isEmpty) name = 'mediaflow-backup.json';
      name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = '${dir.path}${Platform.pathSeparator}$name';
      // 7.0.0: building, encoding and writing a full backup of a big account
      // took seconds on the screen's thread, every interval (the regular
      // freezes in Windows diagnostics). It all runs on the worker now.
      final state = readOnlyView(view.state);
      await runOnWorker(() => writeBackupFile(path, state, now, kAppVersionLabel));
      lastError = null;
      final at = now.millisecondsSinceEpoch;
      await account.setSetting(['backup', 'lastBackup'], at, xp: false);
      if (!manual) {
        await account.backgroundXp('mf565BackupXP', 'backup:$at', 'Automatic backup', 'Backup written to your folder');
      }
      return path;
    } catch (e) {
      lastError = '$e';
      return null;
    } finally {
      _writing = false;
    }
  }
}
