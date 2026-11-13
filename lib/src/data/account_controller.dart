import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../logic/activity.dart';
import '../logic/initial_state.dart';
import '../logic/leveling.dart';
import '../logic/log_engine.dart';
import '../logic/log_xp_preview.dart';
import '../logic/rec_submit.dart';
import '../logic/resume.dart';
import '../logic/xp_preview.dart';
import '../state/lazy_copy.dart';
import '../state/state_codec.dart' show encodeStateData;
import '../state/models.dart';
import '../util/js.dart';
import 'account_ops.dart';
import 'app_prefs.dart';
import 'edit_op.dart';
import 'local_cache.dart';
import 'records.dart';
import 'supabase_cloud.dart' show SupabaseCloud;
import 'sync_engine.dart';
import '../logic/action_xp.dart';

enum SyncState { loading, syncing, synced, offline, error }

/// The signed-in account as the UI sees it: the last cloud copy plus any
/// changes still waiting to upload, applied locally so they show up immediately.
/// 7.0.0: quiet background writes upload together, at most this often.
const Duration kQuietSyncDelay = Duration(seconds: 10);

class AccountController extends ChangeNotifier {
  AccountController({
    required this.userId,
    required this.email,
    required this.cloud,
    required this.cache,
    BackgroundRunner background = runInIsolate,
    this.draftSyncDelay = const Duration(seconds: 10),
    this.liveDraftDelay = const Duration(milliseconds: 600),
    this.liveFoldDelay = const Duration(seconds: 45),
    this.deviceId = 'mediaflow-app',
    this.fallbackInterval = const Duration(minutes: 30),
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

  /// Per-record accounts: how soon a draft change is uploaded, and how soon
  /// it is folded into the device's cloud copy by a normal sync.
  final Duration liveDraftDelay, liveFoldDelay;
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

  /// The account has no MediaFlow data yet (signed up but never opened).
  bool missingAccountData = false;

  /// Creates a new account's first cloud save, exactly as the website's first
  /// save (default categories and settings, empty Library and History), then
  /// syncs. Never overwrites existing data. Returns an error message or null.
  Future<String?> createAccountData() async {
    final c = cloud;
    if (c is! SupabaseCloud) return 'Not available here.';
    try {
      if (await c.version(userId) == null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        await c.createRow(userId, encodeStateData(newAccountState(now)));
      }
      missingAccountData = false;
      await sync();
      return status == SyncState.error ? message : null;
    } catch (e) {
      return _isNetworkError(e) ? 'Could not reach MediaFlow. Check your connection and try again.' : '$e';
    }
  }

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

  /// Level, XP, streak and Library size, worked out in the background with
  /// each sync (7.0.0, for Discord). Null until the first one.
  Map<String, num>? presenceStats;

  /// Changes waiting to upload (read only).
  List<AccountOp> get pendingOps => List.unmodifiable(_pending);

  Future<void> start() async {
    final cached = await cache.load(userId);
    if (cached.raw != null) {
      try {
        // Decoded and brought up to date in the background.
        final merged = await mergeInBackground(_bg, cached.raw, cached.pending, encode: false);
        presenceStats = merged.stats ?? presenceStats;
        _baseRaw = cached.raw;
        _baseUpdatedAt = cached.baseUpdatedAt;
        _index = cached.records;
        _pending
          ..clear()
          ..addAll(cached.pending);
        _setDisplay(merged.state);
        status = SyncState.offline;
        _notify();
        // v565: time away since MediaFlow was last open anywhere (checked again
        // on the cloud copy when this uploads, so it is never counted twice).
        unawaited(creditAway());
      } catch (_) {
        // An unreadable device copy: start from the cloud.
      }
    }
    await sync();
    await creditAway();
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
    // 7.0.0: only the status changed, so only the status listeners hear it
    // (it used to rebuild every open screen at the start of every sync).
    syncStatus.value++;
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
      presenceStats = result.stats ?? presenceStats;
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
      missingAccountData = _display == null;
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

  Future<void> _queue(AccountOp op, Map<String, dynamic> display, {Duration? delay, bool quiet = false}) async {
    // A sync may have replaced the working copy while this change was being
    // prepared; it was made on the old one, so carry it over.
    final current = _display;
    if (current != null && !identical(current, display)) op.apply(current);
    _pending.add(op);
    if (quiet) {
      // Same data for every reader; the screens pick it up with the next change.
      if (!_disposed) syncStatus.value++;
    } else {
      _view = AccountView(current ?? display);
      _notify();
    }
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

  /// 8.0.1: what a Batch Log (Log a title) would earn, worked out in the
  /// background on a copy of the account (like [previewXp]). Null if it
  /// can't be logged.
  Future<double?> previewLog(List<LogEntry> entries, {String? date, String? time}) {
    final raw = _baseRaw;
    if (raw == null) return Future.value(null);
    return logPreviewInBackground(_bg, raw, _pending, LogRequest.create(entries, date: date, time: time));
  }

  /// Batch Log (outside recommendations). Saved on the device first, then uploaded.
  Future<LogOutcome> log(List<LogEntry> entries, {String note = '', String? date, String? time}) async {
    final display = await _working();
    final req = LogRequest.create(entries, note: note, date: date, time: time);
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
  /// after the last change: on per-record accounts within about a second (only
  /// the draft's own records), so the website's open log page follows along.
  Future<void> saveDraft(Map<String, dynamic> logging) async {
    final display = await _working();
    applyLoggingSection(display, logging);
    _pending.removeWhere((p) => p is DraftOp);
    final live = _index != null && cloud is RecordBackend;
    await _queue(DraftOp(mediaFlowUid(), normalizeLogging(logging)), display, delay: live ? liveFoldDelay : draftSyncDelay);
    if (live) {
      _draftPushTimer?.cancel();
      _draftPushTimer = Timer(liveDraftDelay, () => unawaited(_pushDraftNow()));
    }
  }

  // ---- live logging draft (per-record accounts) ----------------------------

  static const _resumeKey = 'resumeStateV285';
  static const _sep = '\u001f';
  static const _loggingRecord = '$_resumeKey${_sep}logging';
  static const _taskRecords = ['sessionActive', 'currentTask$_sep', 'currentTask${_sep}id', 'currentTask${_sep}libraryId'];
  Timer? _draftPushTimer, _livePoll;
  String _liveSince = '';
  bool _livePulling = false, _backgrounded = false;
  int _liveViewers = 0;

  /// The draft's records as the website stores them (`doc` rows of
  /// `resumeStateV285`), from the account as it is on this device.
  Map<String, String>? _draftRecords(Map<String, dynamic> display) {
    final resume = asMap(display[_resumeKey]);
    if (resume == null) return null;
    return {
      '$_resumeKey$_sep': jsStringify([for (final k in resume.keys) '$k']),
      for (final k in resume.keys) '$_resumeKey$_sep$k': jsStringify(resume[k]),
    };
  }

  /// Uploads only the draft's changed records. The draft stays pending and is
  /// folded into the device's cloud copy by the next normal sync (which then
  /// finds nothing left to upload). Returns false when a normal sync is needed.
  Future<bool> _pushDraftNow() async {
    final cloud = this.cloud, index = _index, display = _display;
    if (cloud is! RecordBackend || index == null || display == null || _disposed) return false;
    if (_syncing || _pending.isEmpty || !_pending.every((p) => p is DraftOp)) {
      if (!_syncing) unawaited(sync());
      return false;
    }
    final recs = _draftRecords(display);
    if (recs == null) return false;
    final uploads = <RecordUpload>[];
    for (final e in recs.entries) {
      final cur = index.entries[recordKey('doc', e.key)];
      if (cur == null) {
        // A section the cloud doesn't have yet: the normal sync adds it.
        unawaited(sync());
        return false;
      }
      if (cur.$2 != recHash(e.value, null)) uploads.add(RecordUpload('doc', e.key, null, e.value));
    }
    if (uploads.isEmpty) return true;
    try {
      await cloud.uploadRecords(userId, uploads, deviceId);
    } catch (_) {
      _scheduleSync(const Duration(seconds: 5));
      return false;
    }
    if (!identical(index, _index)) return true; // a sync replaced the index meanwhile
    for (final u in uploads) {
      index.entries[recordKey('doc', u.i)] = (null, recHash(u.j!, null));
    }
    await _save();
    return true;
  }

  /// While the log page is open: checks the draft every few seconds, so a log
  /// continued on the website shows up here right away.
  void startLiveDraft([Duration every = const Duration(seconds: 3)]) {
    _liveViewers++;
    _livePoll ??= Timer.periodic(every, (_) => unawaited(pullDraftNow()));
    unawaited(pullDraftNow());
  }

  void stopLiveDraft() {
    if (_liveViewers > 0) _liveViewers--;
    if (_liveViewers == 0) {
      _livePoll?.cancel();
      _livePoll = null;
    }
  }

  /// Reads the website's latest draft (one small row) and takes it when it is
  /// newer, like a draft saved here. Returns true when the form changed.
  Future<bool> pullDraftNow() async {
    final cloud = this.cloud, index = _index;
    if (cloud is! RecordBackend || index == null || _display == null || _livePulling || _syncing || _disposed || _backgrounded) {
      return false;
    }
    _livePulling = true;
    try {
      final since = _liveSince.isNotEmpty ? _liveSince : recordsSince(index.cursor);
      final rows = await cloud.fetchDocRecords(userId, [_loggingRecord, ..._taskRecords], since);
      if (rows.isEmpty) return false;
      for (final r in rows) {
        if (r.updatedAt.compareTo(_liveSince) > 0) _liveSince = r.updatedAt;
      }
      // A recommendation started, rerolled or ended on the website: a full sync now.
      final taskChanged = rows.any((r) {
        if (r.recordId == _loggingRecord) return false;
        final cur = index.entries[recordKey(r.kind, r.recordId)];
        final data = r.deleted ? null : r.data;
        return data == null ? cur != null : cur?.$2 != recHash(data, r.pos);
      });
      if (taskChanged) {
        _livePulling = false;
        unawaited(sync());
        return false;
      }
      final row = rows.lastWhere((r) => r.recordId == _loggingRecord, orElse: () => rows.first);
      if (row.recordId != _loggingRecord || row.deleted || row.data == null) return false;
      if (index.entries[recordKey('doc', _loggingRecord)]?.$2 == recHash(row.data!, row.pos)) return false;
      final logging = asMap(jsonDecode(row.data!));
      final display = _display;
      if (logging == null || display == null || !identical(index, _index)) return false;
      if (!applyLoggingSection(display, logging)) {
        index.entries[recordKey('doc', _loggingRecord)] = (null, recHash(row.data!, null));
        return false;
      }
      // Kept like a draft saved here, so the next normal sync folds it in.
      _pending.removeWhere((p) => p is DraftOp);
      _pending.add(DraftOp(mediaFlowUid(), readLogging(display) ?? normalizeLogging(logging)));
      // The rows that now match this device's draft are not uploaded again.
      final recs = _draftRecords(display) ?? const {};
      for (final r in rows) {
        if (r.data != null && recs[r.recordId] == r.data) index.entries[recordKey('doc', r.recordId)] = (null, recHash(r.data!, null));
      }
      _view = AccountView(display);
      _notify();
      await _save();
      _scheduleSync(liveFoldDelay);
      return true;
    } catch (_) {
      return false;
    } finally {
      _livePulling = false;
    }
  }

  void dismissRejection() {
    lastRejection = null;
    _notify();
  }

  /// Changes one account setting (synced like the website's Settings).
  /// [xp]: false for changes the app makes by itself and for view toggles
  /// (website v565 earns XP only for real changes made by you).
  Future<void> setSetting(List<String> path, Object? value, {bool xp = true}) async {
    final display = await _working();
    final op = SettingOp.create(display, path, value);
    if (!op.apply(display)) return;
    await _queue(op, display, delay: const Duration(seconds: 2));
    if (xp && path.isNotEmpty) await _actionXp(settingGroup(path), path.first, 'Setting · ${path.first}');
  }

  // ---- v565: XP for every action ---------------------------------------------

  final ActionRepeat _repeat = ActionRepeat();

  /// Action XP for something that is not an account edit (exports…).
  Future<void> actionXp(String group, String subject, String details) => _actionXp(group, subject, details);

  /// Earns this kind of action's XP (website mf565AwardAction): once per
  /// 5 minutes for the same thing, written as a replayable ledger event.
  Future<void> _actionXp(String group, String subject, String details, {bool quiet = false}) async {
    final display = _display;
    if (display == null) return;
    final rate = actionRate(display, group);
    if (!(rate > 0)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_repeat.allow('$group\u0001$subject', now)) return;
    final op = XpEventOp(ActionXpOp(
      key: 'mf565Action:${mediaFlowUid(now)}',
      kind: 'mf565Action.$group',
      base: rate,
      source: actionGroupLabel(group),
      details: details,
      subjectId: subject,
      at: now,
    ));
    if (!op.apply(display)) return;
    await _queue(op, display, delay: quiet ? kQuietSyncDelay : const Duration(seconds: 2), quiet: quiet);
  }

  /// Credits time away from MediaFlow (website v565): on opening the app and
  /// when it comes back after the system suspended it. Returns the XP earned.
  Future<double> creditAway() async {
    final display = _display;
    if (display == null || needsSignIn) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = jsNum(asMap(display['xpLedger'])?['mf565LastSeenAt']).toInt();
    if (last > 0 && now - last < AwayXpOp.minGap) return 0;
    final op = AwayXpOp(from: last > 0 ? last : now, to: now);
    final before = jsNum(asMap(asMap(display['xpLedger'])?['v348ActionEvents'])?[op.id]);
    if (!op.apply(display)) return 0;
    await _queue(op, display, delay: const Duration(seconds: 2));
    return jsNum(asMap(asMap(display['xpLedger'])?['v348ActionEvents'])?[op.id]) - before;
  }

  /// Background work (backups, finished recoveries, fresh-episode checks) earns
  /// XP once per [key] (website mf565BgAward).
  Future<void> backgroundXp(String kind, String key, String source, String details) async {
    final display = _display;
    if (display == null) return;
    final v = asMap(asMap(display['settings'])?['leveling'])?[kind];
    final raw = v == null ? null : jsNumOrNull(v); // missing: the default
    final rate = raw != null && raw.isFinite ? raw.clamp(0, 100000).toDouble() : (kBackgroundXpDefaults[kind] ?? 0.0);
    if (!(rate > 0)) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final op = XpEventOp(ActionXpOp(key: 'mf565Bg:$key', kind: kind, base: rate, source: source, details: details, at: now));
    if (!op.apply(display)) return;
    await _queue(op, display, delay: const Duration(seconds: 2));
  }

  /// Saves a change made on this device (applied now, uploaded shortly after).
  /// [supersedes] removes older pending changes the new one fully replaces.
  /// [quiet]: background bookkeeping (app time) that no screen shows right
  /// away: saved and synced as usual, without rebuilding every open screen.
  Future<bool> perform(AccountOp op, {Duration? delay, bool Function(AccountOp pending)? supersedes, bool quiet = false}) async {
    final display = await _working();
    if (!op.apply(display)) return false;
    if (supersedes != null) _pending.removeWhere(supersedes);
    await _queue(op, display, delay: delay, quiet: quiet);
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
    bool quiet = false,
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
    await _queue(op, display, delay: delay, quiet: quiet);
    // v565: XP for the change, unless it already earned its own XP.
    final kind = editGroup([for (final c in op.changes) c.path]);
    if (kind != null) await _actionXp(kind.group, kind.subject, label.isEmpty ? actionGroupLabel(kind.group) : label, quiet: quiet);
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
    await _actionXp('history', 'undo-redo', '$verb · ${source.label}');
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
    final wait = _lastFallbackAt.add(fallbackInterval).difference(DateTime.now());
    _fallbackTimer = Timer(wait.isNegative ? Duration.zero : wait, () => unawaited(flushFallback()));
  }

  /// 8.1.1: the copy is the whole account (several MB) and every write of it
  /// costs the database a lot of disk work. It was written every 3 minutes and
  /// each time the app lost focus (on Windows: every switch to another
  /// window), which used up the project's Disk IO budget. Now: every
  /// [fallbackInterval] (30 min), and on leaving the app only when the last
  /// copy is at least [kFallbackMinGap] old. The time of the last copy is kept
  /// across restarts.
  static const Duration kFallbackMinGap = Duration(minutes: 10);

  DateTime get _lastFallbackAt {
    if (_lastFallback.millisecondsSinceEpoch == 0 && AppPrefs.instance.loaded) {
      final saved = AppPrefs.instance.get<int>('fallbackAt:$userId', 0);
      if (saved > 0) _lastFallback = DateTime.fromMillisecondsSinceEpoch(saved);
    }
    return _lastFallback;
  }

  Future<void> flushFallback({bool force = false}) async {
    final cloud = this.cloud;
    if (!_fallbackDirty || _index == null || cloud is! RecordBackend) return;
    final raw = _baseRaw;
    if (raw == null) return;
    if (!force && fallbackInterval > Duration.zero && DateTime.now().difference(_lastFallbackAt) < kFallbackMinGap) {
      _scheduleFallback(); // still due later
      return;
    }
    _fallbackDirty = false;
    _fallbackTimer?.cancel();
    try {
      await cloud.writeFallback(userId, raw, deviceId);
      _lastFallback = DateTime.now();
      if (AppPrefs.instance.loaded) unawaited(AppPrefs.instance.set('fallbackAt:$userId', _lastFallback.millisecondsSinceEpoch));
    } catch (_) {
      _fallbackDirty = true; // tried again with the next save or pause
    }
  }

  /// While the app is open: other devices' changes arrive live (8.0.0).
  /// Every [probeEvery] one tiny read asks whether another device saved
  /// anything since the last sync, and syncs right away when it did; a full
  /// sync still runs every [every] as a safety net. The website does the same.
  void startAutoPull([Duration every = const Duration(minutes: 1), Duration probeEvery = const Duration(seconds: 5)]) {
    _backgrounded = false;
    _pullTimer?.cancel();
    _pullTimer = Timer.periodic(every, (_) {
      if (!_syncing && !_disposed) unawaited(sync());
    });
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(probeEvery, (_) => unawaited(probeNow()));
  }

  void stopAutoPull() {
    _backgrounded = true;
    _pullTimer?.cancel();
    _pullTimer = null;
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  Timer? _probeTimer;
  bool _probing = false;

  /// Syncs now if another device saved something since the last sync.
  /// Returns true when it did.
  Future<bool> probeNow() async {
    final cloud = this.cloud, index = _index;
    if (cloud is! RecordBackend || index == null || index.cursor.isEmpty) return false;
    if (_probing || _syncing || _disposed || _backgrounded) return false;
    _probing = true;
    try {
      // Strictly after the cursor: the full sync reads a few seconds back to
      // catch late commits, but the probe must not keep finding the last row.
      if (!await cloud.changedElsewhere(userId, index.cursor, deviceId)) return false;
      if (_syncing || _disposed) return false;
      await sync();
      return true;
    } catch (_) {
      return false; // offline or a hiccup: the next probe or the minute sync tries again
    } finally {
      _probing = false;
    }
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
    if (_disposed) return;
    syncStatus.value++;
    notifyListeners();
  }

  /// Ticks whenever the sync status (or anything else) changes. The status
  /// pill listens to this, so a sync starting doesn't rebuild every screen.
  final ValueNotifier<int> syncStatus = ValueNotifier<int>(0);

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _fallbackTimer?.cancel();
    _pullTimer?.cancel();
    _probeTimer?.cancel();
    _draftPushTimer?.cancel();
    _livePoll?.cancel();
    syncStatus.dispose();
    super.dispose();
  }
}

/// The XP preview's background run. Top-level on purpose: the closure handed to
/// the isolate then holds only these arguments.
/// Top-level (like [xpPreviewInBackground]) so the background work carries
/// only the account copy and the log, never the controller.
Future<double?> logPreviewInBackground(BackgroundRunner background, Object? raw, List<AccountOp> ops, LogRequest req) {
  final copy = List<AccountOp>.of(ops);
  return background(() => previewLogXp(mergeState(raw, copy, encode: false).state, req));
}

Future<XpPreview> xpPreviewInBackground(BackgroundRunner background, Object? raw, List<AccountOp> ops,
    Map<String, dynamic> task, Map<String, dynamic> logDraft) {
  final copy = List<AccountOp>.of(ops);
  final t = jsonClone(task) as Map<String, dynamic>, d = jsonClone(logDraft) as Map<String, dynamic>;
  return background(() => XpPreview(xpPreviewData(mergeState(raw, copy, encode: false).state, t, d)));
}
