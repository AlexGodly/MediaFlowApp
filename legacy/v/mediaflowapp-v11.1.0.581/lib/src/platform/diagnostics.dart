// v565: an on-device log of crashes and freezes, so the ones that remain can
// be found and fixed. Nothing is sent anywhere; the person can export the log
// from Settings → App info → Diagnostics.
//
// - Uncaught Flutter and platform errors (with their stack).
// - Freezes: the UI thread not getting a frame for over a second while the
//   app is in the foreground (a watchdog timer checks the frame clock).
// - The decoded-image cache is capped, so covers can't fill memory.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

class Diagnostics {
  Diagnostics._();
  static final Diagnostics instance = Diagnostics._();

  static const _maxEntries = 300;
  final List<Map<String, Object?>> _entries = [];
  File? _file;
  Timer? _flush, _watch;
  bool _foreground = true;

  List<Map<String, Object?>> get entries => List.unmodifiable(_entries);

  /// 10.0.0: what was on screen and what the app last did, so a slow frame
  /// says where it happened ("Personal Order · after sync: remote changes").
  String screen = '';
  String _event = '';
  DateTime _eventAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Notes what the app is doing now (sync, a saved change, a live update).
  void note(String event) {
    _event = event;
    _eventAt = DateTime.now();
  }

  String _context() {
    final parts = <String>[
      if (screen.isNotEmpty) screen,
      if (_event.isNotEmpty && DateTime.now().difference(_eventAt).inSeconds < 10)
        'after $_event (${DateTime.now().difference(_eventAt).inMilliseconds} ms before)',
    ];
    try {
      parts.add('RAM ${(ProcessInfo.currentRss / (1 << 20)).round()} MB');
    } catch (_) {}
    return parts.join(' · ');
  }

  Future<void> init() async {
    // Covers: at most ~96 MB / 500 decoded images held at once.
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = 64 << 20; // 10.0.0: 96 → 64 MB (covers are decoded at their shown size)
    cache.maximumSize = 500;

    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}mediaflow-diagnostics.json');
      if (await _file!.exists()) {
        final raw = jsonDecode(await _file!.readAsString());
        if (raw is List) {
          for (final e in raw) {
            if (e is Map) _entries.add(e.cast<String, Object?>());
          }
        }
      }
    } catch (_) {}

    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      record('error', details.exceptionAsString(), stack: details.stack?.toString());
      previousFlutter?.call(details);
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record('crash', error.toString(), stack: stack.toString());
      return previousPlatform?.call(error, stack) ?? false;
    };

    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final ms = t.totalSpan.inMilliseconds;
        if (ms >= 700) record('slow-frame', 'A frame took $ms ms · ${_context()}');
      }
    });
    _watch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      // The timer itself runs on the UI thread: a late tick IS a freeze.
      final now = DateTime.now();
      final gap = now.difference(_lastTick).inMilliseconds;
      _lastTick = now;
      if (_foreground && gap > 1500) record('freeze', 'The app did not respond for ${(gap / 1000).toStringAsFixed(1)} s · ${_context()}');
    });
    WidgetsBinding.instance.addObserver(_Lifecycle(this));
  }

  DateTime _lastTick = DateTime.now();

  void record(String kind, String message, {String? stack}) {
    _entries.add({
      'at': DateTime.now().toIso8601String(),
      'kind': kind,
      'message': message.length > 600 ? message.substring(0, 600) : message,
      if (stack != null) 'stack': stack.length > 3000 ? stack.substring(0, 3000) : stack,
      'version': kAppVersionLabel,
      'platform': Platform.operatingSystem,
    });
    if (_entries.length > _maxEntries) _entries.removeRange(0, _entries.length - _maxEntries);
    _flush?.cancel();
    _flush = Timer(const Duration(seconds: 2), save);
  }

  Future<void> save() async {
    final f = _file;
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode(_entries));
    } catch (_) {}
  }

  Future<void> clear() async {
    _entries.clear();
    await save();
  }

  /// The log as readable text, for Settings → Export.
  String asText() => [
        'MediaFlow $kAppVersionLabel diagnostics (${Platform.operatingSystem})',
        // Each entry with the version it happened in (a log spans updates).
        for (final e in _entries.reversed)
          '${e['at']}  ${e['version'] ?? ''}  ${e['kind']}  ${e['message']}${e['stack'] != null ? '\n${e['stack']}' : ''}',
      ].join('\n\n');

  void _setForeground(bool fg) {
    _foreground = fg;
    _lastTick = DateTime.now();
  }

  @visibleForTesting
  void stop() {
    _watch?.cancel();
    _flush?.cancel();
  }
}

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this.d);
  final Diagnostics d;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => d._setForeground(state == AppLifecycleState.resumed);
}
