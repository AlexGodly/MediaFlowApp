// Recoveries keep going when MediaFlow is not on screen:
// - Android: a foreground service with a progress notification (Pause /
//   Resume / Stop); the work continues in the background and after the app
//   is swiped away (tool/android/BackgroundWorkService.kt).
// - Windows: closing the window keeps MediaFlow in the tray until the job
//   ends; the tray shows the progress with Pause / Stop.
// - iOS: the system stops apps in the background, so a job pauses when
//   MediaFlow leaves the screen and continues when it comes back.
// Running jobs are saved, so a job cut short (the app was closed, the phone
// restarted) continues the next time MediaFlow opens.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../data/account_controller.dart';
import '../data/recovery_runner.dart';
import 'desktop_tray.dart';

/// The progress line shown in the notification / tray.
({String title, String text, int done, int total, bool paused})? recoveryStatus(RecoveryRunner r) {
  final jobs = [r.cover, r.metadata].whereType<RecoveryJob>().where((j) => j.running).toList();
  if (jobs.isEmpty) return null;
  final j = jobs.first;
  final name = j.kind == 'cover' ? 'Cover Recovery' : 'Metadata Recovery';
  final paused = jobs.every((x) => x.paused);
  final both = jobs.length > 1 ? ' · +1 more job' : '';
  return (
    title: '$name · ${j.done} / ${j.total}${paused ? ' · Paused' : ''}',
    text: paused ? 'Paused$both' : (j.current.isEmpty ? 'Working…$both' : '${j.current}$both'),
    done: j.done,
    total: j.total,
    paused: paused,
  );
}

class BackgroundWork with WidgetsBindingObserver {
  BackgroundWork._();
  static final BackgroundWork instance = BackgroundWork._();

  static const _channel = MethodChannel('mediaflow/background');

  AccountController? _account;
  bool _observing = false, _native = false, _resumed = false;
  String _lastSent = '';
  Timer? _throttle;
  String _lastSaved = '';

  /// Called when a job ends (for the "Recovery finished" notification).
  void Function(RecoveryJob job)? onFinished;
  final Set<RecoveryJob> _seenRunning = {};

  void attach(AccountController account) {
    if (identical(_account, account)) return;
    _account?.removeListener(_onAccount);
    _account = account;
    _resumed = false;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
      RecoveryRunner.instance.addListener(_onRunner);
      if (Platform.isAndroid) {
        _channel.setMethodCallHandler((call) async {
          if (call.method == 'action') _action('${call.arguments}');
          return null;
        });
      }
      DesktopTray.instance.onBackgroundAction = _action;
    }
    account.addListener(_onAccount);
    _onAccount();
  }

  void _onAccount() => unawaited(_maybeResumeSaved());

  void _action(String action) {
    final r = RecoveryRunner.instance;
    switch (action) {
      case 'pause':
        r.pauseAll();
      case 'resume':
        r.resumeAll();
      case 'stop':
        r.stopAll();
    }
  }

  // ---- progress out ----

  void _onRunner() {
    final r = RecoveryRunner.instance;
    for (final j in [r.cover, r.metadata].whereType<RecoveryJob>()) {
      if (j.running) {
        _seenRunning.add(j);
      } else if (_seenRunning.remove(j)) {
        onFinished?.call(j);
      }
    }
    _throttle ??= Timer(const Duration(milliseconds: 700), () {
      _throttle = null;
      unawaited(_publish());
    });
  }

  Future<void> _publish() async {
    final status = recoveryStatus(RecoveryRunner.instance);
    final key = status == null ? '' : '${status.title}|${status.text}|${status.paused}';
    if (key != _lastSent) {
      _lastSent = key;
      if (Platform.isAndroid) {
        try {
          if (status == null) {
            if (_native) await _channel.invokeMethod('stop');
            _native = false;
          } else {
            _native = await _channel.invokeMethod<bool>('update', {
                  'title': status.title,
                  'text': status.text,
                  'done': status.done,
                  'total': status.total,
                  'paused': status.paused,
                }) ??
                false;
          }
        } on MissingPluginException {
          // Not a MediaFlow Android build (tests): nothing to show.
        } catch (_) {}
      }
      if (Platform.isWindows) {
        await DesktopTray.instance.setBackground(status == null ? null : '${status.title} · ${status.text}', paused: status?.paused ?? false);
      }
    }
    await _save();
  }

  // ---- saved jobs ----

  Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/recovery_jobs.json');
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final account = _account;
    if (account == null) return;
    final r = RecoveryRunner.instance;
    final jobs = [r.cover, r.metadata].whereType<RecoveryJob>().where((j) => j.running && !j.stopped).toList();
    final data = jobs.isEmpty ? '' : jsonEncode({'userId': account.userId, 'jobs': [for (final j in jobs) j.toJson()]});
    if (data == _lastSaved) return;
    _lastSaved = data;
    final f = await _file();
    if (f == null) return;
    try {
      if (data.isEmpty) {
        if (await f.exists()) await f.delete();
      } else {
        await f.writeAsString(data, flush: true);
      }
    } catch (_) {}
  }

  /// Continues the jobs saved by an earlier run once the account is loaded.
  Future<void> _maybeResumeSaved() async {
    final account = _account;
    if (account == null || _resumed || !account.hasData) return;
    _resumed = true;
    final f = await _file();
    if (f == null || !await f.exists()) return;
    List<RecoveryJob> jobs;
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map || raw['userId'] != account.userId) return;
      jobs = [for (final j in (raw['jobs'] as List? ?? const [])) RecoveryJob.fromJson(j)].whereType<RecoveryJob>().toList();
    } catch (_) {
      return;
    }
    final r = RecoveryRunner.instance;
    final cover = jobs.where((j) => j.kind == 'cover').firstOrNull;
    final meta = jobs.where((j) => j.kind == 'metadata').firstOrNull;
    // Covers first, then details (as Combined Recovery does).
    unawaited(() async {
      if (cover != null) await r.startCover(account, cover.ids, cover.label, resume: cover);
      if (meta != null) await r.startMetadata(account, meta.ids, meta.label, resume: meta);
    }());
  }

  // ---- iOS: pause in the background, continue on return ----

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isIOS) return;
    final r = RecoveryRunner.instance;
    if (state == AppLifecycleState.paused) {
      if (r.anyRunning) r.pauseAll(bySystem: true);
    } else if (state == AppLifecycleState.resumed) {
      r.resumeAll(onlySystem: true);
    }
  }
}
