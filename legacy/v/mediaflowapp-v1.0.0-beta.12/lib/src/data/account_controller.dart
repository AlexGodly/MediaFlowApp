import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../logic/log_engine.dart';
import '../state/models.dart';
import '../state/state_codec.dart';
import 'local_cache.dart';
import 'sync_engine.dart';

enum SyncState { loading, syncing, synced, offline, error }

/// The signed-in account as the UI sees it: the last cloud copy plus any logs
/// still waiting to upload, applied locally so they show up immediately.
class AccountController extends ChangeNotifier {
  AccountController({
    required this.userId,
    required this.email,
    required this.cloud,
    required this.cache,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? copyState,
  }) : _copy = copyState ?? deepCopyStateInBackground;

  final String userId;
  final String email;
  final CloudBackend cloud;
  final AccountCache cache;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) _copy;

  Map<String, dynamic>? _base;
  String? _baseUpdatedAt;
  final List<LogRequest> _pending = [];
  Map<String, dynamic>? _display;
  AccountView? _view;

  SyncState status = SyncState.loading;
  String? message;
  DateTime? lastSynced;
  bool _syncing = false;
  bool _disposed = false;

  AccountView? get view => _view;
  bool get hasData => _view != null;
  int get pendingCount => _pending.length;

  Future<void> start() async {
    final cached = await cache.load(userId);
    if (cached.base != null) {
      _base = cached.base;
      _baseUpdatedAt = cached.baseUpdatedAt;
      _pending
        ..clear()
        ..addAll(cached.pending);
      await _rebuild();
      status = SyncState.offline;
      _notify();
    }
    await sync();
  }

  Future<void> _rebuild() async {
    final base = _base;
    if (base == null) {
      _display = null;
      _view = null;
      return;
    }
    final display = _pending.isEmpty ? base : await _copy(base);
    for (final req in _pending) {
      applyLog(display, req);
    }
    _display = display;
    _view = AccountView(display);
  }

  /// Uploads pending logs (if any) and pulls the latest cloud copy.
  Future<void> sync() async {
    if (_syncing || _disposed) return;
    _syncing = true;
    status = SyncState.syncing;
    message = null;
    _notify();
    final batch = List<LogRequest>.of(_pending);
    try {
      final result = await syncOnce(cloud, userId, batch);
      _base = result.state;
      _baseUpdatedAt = result.updatedAt;
      _pending.removeWhere((r) => batch.any((b) => b.groupId == r.groupId));
      await _save();
      await _rebuild();
      status = SyncState.synced;
      lastSynced = DateTime.now();
    } on MissingCloudRow catch (e) {
      status = SyncState.error;
      message = e.toString();
    } catch (e) {
      if (_isNetworkError(e)) {
        status = SyncState.offline;
        message = _pending.isEmpty ? 'Offline. Showing the copy saved on this device.' : 'Offline. ${_pending.length} log${_pending.length == 1 ? '' : 's'} will upload when you reconnect.';
      } else {
        status = SyncState.error;
        message = 'Sync failed: $e';
      }
    } finally {
      _syncing = false;
      _notify();
    }
  }

  /// Logs consumption. Saved on the device first, then uploaded.
  Future<LogOutcome> log(List<LogEntry> entries, {String note = '', String? date}) async {
    var display = _display;
    if (display == null) throw StateError('Your MediaFlow data has not loaded yet.');
    if (identical(display, _base)) {
      // Keep the last cloud copy untouched; logs are layered on a working copy.
      display = await _copy(display);
      _display = display;
    }
    final req = LogRequest.create(entries, note: note, date: date);
    final outcome = applyLog(display, req);
    if (!outcome.applied) return outcome;
    _pending.add(req);
    _view = AccountView(display);
    await _save();
    _notify();
    unawaited(sync());
    return outcome;
  }

  Future<void> _save() => cache.save(
        userId,
        CachedAccount(base: _base, baseUpdatedAt: _baseUpdatedAt, pending: List.of(_pending)),
      );

  /// Removes this account's data from the device (used on sign-out).
  Future<void> forget() => cache.delete(userId);

  bool _isNetworkError(Object e) {
    if (e is SocketException || e is TimeoutException || e is HttpException) return true;
    final text = e.toString().toLowerCase();
    return text.contains('socketexception') || text.contains('failed host lookup') ||
        text.contains('connection') || text.contains('network') || text.contains('clientexception') ||
        text.contains('timed out') || text.contains('authretryablefetchexception');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
