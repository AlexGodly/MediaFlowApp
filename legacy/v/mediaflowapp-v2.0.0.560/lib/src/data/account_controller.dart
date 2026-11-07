import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../logic/activity.dart';
import '../logic/leveling.dart';
import '../logic/log_engine.dart';
import '../logic/rec_submit.dart';
import '../logic/resume.dart';
import '../logic/xp_preview.dart';
import '../state/lazy_copy.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'account_ops.dart';
import 'edit_op.dart';
import 'local_cache.dart';
import 'records.dart';
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
    BackgroundRunner background = runInIsolate,
    this.draftSyncDelay = const Duration(seconds: 10),
    this.deviceId = 'mediaflow-app',
    this.fallbackInterval = const Duration(minutes: 3),
  }) : _bg = background;

  /// This install's id on per-record rows (`device_id`, like the website's).
  final String deviceId;

  /// How often the single-row fallback copy is rewritten (website: 3 minutes).
  final Duration fallbackInterval;

  final String userId;
  final String email;
  final CloudBackend cloud;
  final AccountCache cache;
  final Duration draftSyncDelay;
  final BackgroundRunner _bg;

  // The last cloud copy as stored (the website's compressed form: one small
  // object, so it is cheap to keep, save and hand to background work). The
  // decoded account lives only in [_display].
  Object? _baseRaw;
  String? _baseUpdatedAt;

  // Per-record storage (website v556): what this device knows of the cloud's
  // records. Null while the account uses the single row.
  RecordIndex? _index;
  bool _fallbackDirty = false;
  DateTime _lastFallback = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _fallbackTimer;
  Timer? _pullTimer;

  /// True once the account syncs record by record (instant both ways with the website).
  bool get usesRecords => _index != null;
  final List<AccountOp> _pending = [];
  Map<String, dynamic>? _display;
  AccountView? _view;
  Timer? _syncTimer;

  SyncState status = SyncState.loading;
  String? message;

  /// A change made on this device that your account could no longer accept.
  String? lastRejection;

  /// The sign-in expired or ended elsewhere; the device copy is still in use.
  bool needsSignIn = false;
  DateTime? lastSynced;
  bool _syncing = false;
  bool _syncAgain = false;
  bool _disposed = false;

  AccountView? get view => _view;
  bool get hasData => _view != null;

  /// Changes that matter to the user (logs and task actions); drafts excluded.
  int get pendingCount => _pending.where((op) => op is! DraftOp).length;

  /// Changes waiting to upload (read only).
  List<AccountOp> get pendingOps => List.unmodifiable(_pending);

  Future<void> start() async {
    final cached = await cache.load(userId);
    if (cached.raw != null) {
      try {
        // Decoded and brought up to date in the background.
        final merged = await mergeInBackground(_bg, cached.raw, cached.pending, encode: false);
        _baseRaw = cached.raw;
        _baseUpdatedAt = cached.baseUpdatedAt;
        _index = cached.records;
        _pending
          ..clear()
          ..addAll(cached.pending);
        _setDisplay(merged.state);
        status = SyncState.offline;
        _notify();
      } catch (_) {
        // An unreadable device copy: start from the cloud.
      }
    }
    await sync();
  }

  void _setDisplay(Map<String, dynamic> state) {
    _display = state;
    _view = AccountView(state);
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
      final result = await syncOnce(
        cloud,
        userId,
        batch,
        knownRaw: _display == null ? null : _baseRaw,
        knownUpdatedAt: _baseUpdatedAt,
        knownIndex: _display == null ? null : _index,
        deviceId: deviceId,
        background: _bg,
      );
      _baseRaw = result.raw;
      _baseUpdatedAt = result.updatedAt;
      _index = result.index;
      if (result.index != null && result.uploaded > 0) _scheduleFallback();
      if (result.rejected.isNotEmpty) {
        lastRejection = 'A log made on this device could not be added to your account: ${result.rejected.first}';
      }
      _pending.removeWhere((op) => batch.any((b) => identical(b, op)));
      final fresh = result.state;
      if (fresh != null) {
        // The new cloud copy plus whatever was changed here while syncing.
        for (final op in _pending) {
          op.apply(fresh);
        }
        _setDisplay(fresh);
      }
      await _save();
      status = SyncState.synced;
      needsSignIn = false;
      lastSynced = DateTime.now();
    } on MissingCloudRow catch (e) {
      status = SyncState.error;
      message = e.toString();
    } on NotSignedIn catch (e) {
      status = SyncState.offline;
      needsSignIn = true;
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

  DateTime? _syncDue;

  /// Syncs after [delay] — unless a sync is already due sooner.
  void _scheduleSync(Duration delay) {
    final due = DateTime.now().add(delay);
    if (_syncTimer?.isActive == true && _syncDue != null && _syncDue!.isBefore(due)) return;
    _syncTimer?.cancel();
    _syncDue = due;
    _syncTimer = Timer(delay, () => unawaited(sync()));
  }

  /// The device's working copy of the account.
  Future<Map<String, dynamic>> _working() async {
    final display = _display;
    if (display == null) throw StateError('Your MediaFlow data has not loaded yet.');
    return display;
  }

  Future<void> _queue(AccountOp op, Map<String, dynamic> display, {Duration? delay}) async {
    // A sync may have replaced the working copy while this change was being
    // prepared; it was made on the old one, so carry it over.
    final current = _display;
    if (current != null && !identical(current, display)) op.apply(current);
    _pending.add(op);
    _view = AccountView(current ?? display);
    _notify();
    await _save();
    if (delay == null) {
      unawaited(sync());
    } else {
      _scheduleSync(delay);
    }
  }

  /// "XP for this log": a trial save of [logDraft] on a background copy of the
  /// account (the cloud copy plus this device's changes), so nothing is copied
  /// on the screen's thread.
  Future<XpPreview> previewXp(Map<String, dynamic> task, Map<String, dynamic> logDraft) {
    final raw = _baseRaw;
    if (raw == null) return Future.error(StateError('Your MediaFlow data has not loaded yet.'));
    return xpPreviewInBackground(_bg, raw, _pending, task, logDraft);
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

  void dismissRejection() {
    lastRejection = null;
    _notify();
  }

  /// Changes one account setting (synced like the website's Settings).
  Future<void> setSetting(List<String> path, Object? value) async {
    final display = await _working();
    final op = SettingOp.create(display, path, value);
    if (!op.apply(display)) return;
    await _queue(op, display, delay: const Duration(seconds: 2));
  }

  /// Saves a change made on this device (applied now, uploaded shortly after).
  /// [supersedes] removes older pending changes the new one fully replaces.
  Future<bool> perform(AccountOp op, {Duration? delay, bool Function(AccountOp pending)? supersedes}) async {
    final display = await _working();
    if (!op.apply(display)) return false;
    if (supersedes != null) _pending.removeWhere(supersedes);
    await _queue(op, display, delay: delay);
    return true;
  }

  /// Undo / redo for edits made on this device in this session (the website's
  /// Undo and Redo work the same way: within the open app).
  final List<EditOp> undoStack = [];
  final List<EditOp> redoStack = [];

  /// Performs an edit with the website's logic on a copy of the account, then
  /// saves the difference as a replayable change. Returns the change (or null
  /// if nothing changed).
  Future<EditOp?> edit(
    void Function(Map<String, dynamic> copy, int now) action, {
    String label = '',
    bool annotateStreaks = false,
    bool undoable = true,
    Duration? delay,
  }) async {
    final display = await _working();
    // Only the parts of the account the edit touches are copied and compared.
    final copy = LazyStateCopy(display);
    final now = DateTime.now().millisecondsSinceEpoch;
    action(copy, now);
    final op = editFromStates(display, copy, now: now, label: label, annotateStreaks: annotateStreaks);
    if (op == null) return null;
    op.apply(display);
    if (undoable) {
      undoStack.add(op);
      if (undoStack.length > 40) undoStack.removeAt(0);
      redoStack.clear();
    }
    await _queue(op, display, delay: delay);
    return op;
  }

  bool _isActivity(Change c) => c.path.isNotEmpty && c.path.first == 'activityLog';

  Future<String?> _replay(EditOp source, List<Change> changes, String verb) async {
    final display = await _working();
    final copy = LazyStateCopy(display);
    final now = DateTime.now().millisecondsSinceEpoch;
    final before = coreSnapshot(copy);
    var any = false;
    for (final c in changes) {
      if (applyChange(copy, c, now)) any = true;
    }
    if (!any) return null;
    if (source.annotateStreaks) annotateStreakXP(copy, Leveling(copy));
    recordActivity(copy, before: before, id: mediaFlowUid(now), timestamp: now, action: verb, detail: source.label);
    final op = editFromStates(display, copy, now: now, label: source.label, annotateStreaks: source.annotateStreaks);
    if (op == null) return null;
    op.apply(display);
    await _queue(op, display);
    return source.label;
  }

  /// Undoes the latest edit made here. Returns its label, or null.
  Future<String?> undo() async {
    if (undoStack.isEmpty) return null;
    final op = undoStack.removeLast();
    redoStack.add(op);
    final inverse = [for (final c in op.changes.reversed) if (!_isActivity(c)) c.inverse()];
    return _replay(op, inverse, 'Undo');
  }

  /// Redoes the latest undone edit. Returns its label, or null.
  Future<String?> redo() async {
    if (redoStack.isEmpty) return null;
    final op = redoStack.removeLast();
    undoStack.add(op);
    return _replay(op, [for (final c in op.changes) if (!_isActivity(c)) c], 'Redo');
  }

  /// Uploads a pending draft now (e.g. when the app goes to the background),
  /// and the fallback copy if it is due.
  Future<void> flushDraft() async {
    if (_pending.any((p) => p is DraftOp)) await sync();
    await flushFallback();
  }

  /// Per-record accounts: the single `mediaflow_states` row is kept as a
  /// complete fallback copy for older app versions and recovery tools — at most
  /// every [fallbackInterval], and when the app goes to the background (the
  /// website does the same).
  void _scheduleFallback() {
    _fallbackDirty = true;
    if (_fallbackTimer?.isActive == true) return;
    final wait = _lastFallback.add(fallbackInterval).difference(DateTime.now());
    _fallbackTimer = Timer(wait.isNegative ? Duration.zero : wait, () => unawaited(flushFallback()));
  }

  Future<void> flushFallback() async {
    final cloud = this.cloud;
    if (!_fallbackDirty || _index == null || cloud is! RecordBackend) return;
    final raw = _baseRaw;
    if (raw == null) return;
    _fallbackDirty = false;
    _fallbackTimer?.cancel();
    try {
      await cloud.writeFallback(userId, raw, deviceId);
      _lastFallback = DateTime.now();
    } catch (_) {
      _fallbackDirty = true; // tried again with the next save or pause
    }
  }

  /// While the app is open: pull other devices' changes every minute (the
  /// website pulls every minute too). Cheap when nothing changed.
  void startAutoPull([Duration every = const Duration(minutes: 1)]) {
    _pullTimer?.cancel();
    _pullTimer = Timer.periodic(every, (_) {
      if (!_syncing && !_disposed) unawaited(sync());
    });
  }

  void stopAutoPull() {
    _pullTimer?.cancel();
    _pullTimer = null;
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
        CachedAccount(raw: _baseRaw, baseUpdatedAt: _baseUpdatedAt, pending: List.of(_pending), records: _index),
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
    _fallbackTimer?.cancel();
    _pullTimer?.cancel();
    super.dispose();
  }
}

/// The XP preview's background run. Top-level on purpose: the closure handed to
/// the isolate then holds only these arguments.
Future<XpPreview> xpPreviewInBackground(BackgroundRunner background, Object? raw, List<AccountOp> ops,
    Map<String, dynamic> task, Map<String, dynamic> logDraft) {
  final copy = List<AccountOp>.of(ops);
  final t = jsonClone(task) as Map<String, dynamic>, d = jsonClone(logDraft) as Map<String, dynamic>;
  return background(() => XpPreview(xpPreviewData(mergeState(raw, copy, encode: false).state, t, d)));
}
