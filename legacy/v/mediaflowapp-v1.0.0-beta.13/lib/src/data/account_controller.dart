import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../logic/log_engine.dart';
import '../logic/rec_submit.dart';
import '../logic/resume.dart';
import '../state/models.dart';
import '../state/state_codec.dart';
import '../util/js.dart';
import 'account_ops.dart';
import 'local_cache.dart';
import 'sync_engine.dart';

enum SyncState { loading, syncing, synced, offline, error }

/// The signed-in account as the UI sees it: the last cloud copy plus any
/// changes still waiting to upload, applied locally so they show up immediately.
class AccountController extends ChangeNotifier {
  AccountController({
    required this.userId,
    required this.email,
    required this.cloud,
    required this.cache,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? copyState,
    this.draftSyncDelay = const Duration(seconds: 3),
  }) : _copy = copyState ?? deepCopyStateInBackground;

  final String userId;
  final String email;
  final CloudBackend cloud;
  final AccountCache cache;
  final Duration draftSyncDelay;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) _copy;

  Map<String, dynamic>? _base;
  String? _baseUpdatedAt;
  final List<AccountOp> _pending = [];
  Map<String, dynamic>? _display;
  AccountView? _view;
  Timer? _syncTimer;

  SyncState status = SyncState.loading;
  String? message;
  DateTime? lastSynced;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _disposed = false;

  AccountView? get view => _view;
  bool get hasData => _view != null;

  /// Changes that matter to the user (logs and task actions); drafts excluded.
  int get pendingCount => _pending.where((op) => op is! DraftOp).length;

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
    for (final op in _pending) {
      op.apply(display);
    }
    _display = display;
    _view = AccountView(display);
  }

  /// Uploads pending changes (if any) and pulls the latest cloud copy.
  Future<void> sync() async {
    _syncTimer?.cancel();
    if (_disposed) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    status = SyncState.syncing;
    message = null;
    _notify();
    final batch = List<AccountOp>.of(_pending);
    try {
      final result = await syncOnce(cloud, userId, batch);
      _base = result.state;
      _baseUpdatedAt = result.updatedAt;
      _pending.removeWhere((op) => batch.any((b) => identical(b, op)));
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
        final n = pendingCount;
        message = n == 0
            ? 'Offline. Showing the copy saved on this device.'
            : 'Offline. $n change${n == 1 ? '' : 's'} will upload when you reconnect.';
      } else {
        status = SyncState.error;
        message = 'Sync failed: $e';
      }
    } finally {
      _syncing = false;
      _notify();
    }
    if (_syncAgain && !_disposed) {
      _syncAgain = false;
      unawaited(sync());
    }
  }

  void _scheduleSync(Duration delay) {
    _syncTimer?.cancel();
    _syncTimer = Timer(delay, () => unawaited(sync()));
  }

  /// The device's working copy (never the cached cloud copy itself).
  Future<Map<String, dynamic>> _working() async {
    var display = _display;
    if (display == null) throw StateError('Your MediaFlow data has not loaded yet.');
    if (identical(display, _base)) {
      display = await _copy(display);
      _display = display;
    }
    return display;
  }

  Future<void> _queue(AccountOp op, Map<String, dynamic> display, {Duration? delay}) async {
    _pending.add(op);
    _view = AccountView(display);
    await _save();
    _notify();
    if (delay == null) {
      unawaited(sync());
    } else {
      _scheduleSync(delay);
    }
  }

  /// Batch Log (outside recommendations). Saved on the device first, then uploaded.
  Future<LogOutcome> log(List<LogEntry> entries, {String note = '', String? date}) async {
    final display = await _working();
    final req = LogRequest.create(entries, note: note, date: date);
    final outcome = applyLog(display, req);
    if (!outcome.applied) return outcome;
    await _queue(BatchLogOp(req), display);
    return outcome;
  }

  /// MediaFlow Recommends: start / something else / skip / end / another title.
  Future<bool> taskAction(TaskAction action) async {
    final display = await _working();
    final op = TaskOp.perform(display, action);
    if (op == null) return false;
    // Something else / skip / end close the logging form; its draft goes too.
    if (action == TaskAction.reroll || action == TaskAction.skip || action == TaskAction.end) {
      _pending.removeWhere((p) => p is DraftOp);
    }
    await _queue(op, display);
    return true;
  }

  /// Saves the open logging form (shared with the website). Uploads shortly
  /// after the last change.
  Future<void> saveDraft(Map<String, dynamic> logging) async {
    final display = await _working();
    applyLoggingSection(display, logging);
    _pending.removeWhere((p) => p is DraftOp);
    await _queue(DraftOp(mediaFlowUid(), normalizeLogging(logging)), display, delay: draftSyncDelay);
  }

  /// Uploads a pending draft now (e.g. when the app goes to the background).
  Future<void> flushDraft() async {
    if (_pending.any((p) => p is DraftOp)) await sync();
  }

  /// Logs the recommended task from the open form.
  Future<RecLogOutcome> submitRecommendation(Map<String, dynamic> task, Map<String, dynamic> logDraft) async {
    final display = await _working();
    final req = RecLogRequest.create(task, logDraft);
    final outcome = applyRecLog(display, req);
    if (!outcome.applied) return outcome;
    _pending.removeWhere((p) => p is DraftOp);
    await _queue(RecLogOp(req), display);
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
    _syncTimer?.cancel();
    super.dispose();
  }
}
