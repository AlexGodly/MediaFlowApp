import 'dart:async';
import 'dart:isolate';

import '../state/state_codec.dart';
import 'account_ops.dart';
import 'records.dart';

/// Runs heavy work away from the screen. The app uses [Isolate.run]; tests may
/// run it inline. Whatever the work returns comes back without being copied.
typedef BackgroundRunner = Future<R> Function<R>(FutureOr<R> Function() work);

Future<R> runInIsolate<R>(FutureOr<R> Function() work) => Isolate.run(work);

/// Runs [work] right here (tests).
Future<R> runInline<R>(FutureOr<R> Function() work) async => await work();

/// The account's cloud copy as stored: `state_data` exactly as the row holds it
/// (the website's compressed form, or a plain object for old rows).
class CloudSnapshot {
  CloudSnapshot(this.raw, this.updatedAt);
  final Object? raw;
  final String updatedAt;
}

/// Storage the sync engine talks to (Supabase in the app, a fake in tests).
abstract class CloudBackend {
  /// The row's `updated_at` (tiny request), or null if the account has none.
  Future<String?> version(String userId);

  /// The cloud row, or null if the account has none.
  Future<CloudSnapshot?> fetch(String userId);

  /// Writes [payload] (encoded `state_data`) only if the row still has
  /// [expectedUpdatedAt]. Returns the new `updated_at`, or null if someone
  /// else saved first.
  Future<String?> compareAndSwap(String userId, String expectedUpdatedAt, Object payload);
}

/// The website's per-record storage (v556, `mediaflow_records`). Accounts the
/// website has moved over (a `meta`/`store` row exists) are synced record by
/// record; other accounts keep using the single `mediaflow_states` row.
abstract class RecordBackend implements CloudBackend {
  /// True when the account has moved to per-record storage.
  Future<bool> usesRecords(String userId);

  /// Every row changed after [since] (every row when empty), oldest first.
  Future<List<RecordRow>> fetchRecords(String userId, String since);

  /// Upserts [rows] on (user_id, kind, record_id).
  Future<void> uploadRecords(String userId, List<RecordUpload> rows, String deviceId);

  /// Rewrites the single-row fallback copy (`mediaflow_states`) with the
  /// website's v556 marker, so the website does not merge it as an old save.
  Future<void> writeFallback(String userId, Object payload, String deviceId);
}

class MissingCloudRow implements Exception {
  @override
  String toString() =>
      'No MediaFlow data exists for this account yet. Sign in on the MediaFlow website once to set it up, then sync again.';
}

/// The device has the account but no valid sign-in (expired or signed out
/// elsewhere). Everything keeps working on the device; uploads wait.
class NotSignedIn implements Exception {
  @override
  String toString() => 'Sign in again to upload your changes. Everything you do is kept on this device until then.';
}

class CloudBusy implements Exception {
  @override
  String toString() => 'Your account kept changing while syncing. Your changes are safe on this device; try again.';
}

/// [raw] plus [ops], decoded and replayed (and re-encoded if anything changed).
class MergeResult {
  MergeResult(this.state, this.payload, this.applied, this.rejected, [this.compactRaw]);
  final Map<String, dynamic> state;

  /// When the input was an old uncompressed row: the same copy, compressed (so
  /// the device keeps one small object instead of the whole account twice).
  final Map<String, dynamic>? compactRaw;

  /// Encoded `state_data` to upload (null when nothing changed or not asked).
  final Map<String, dynamic>? payload;
  final int applied;
  final List<String> rejected;
}

/// Decodes [raw], replays [ops] on it and, when [encode] is set and something
/// changed, encodes the result for upload. Meant to run in the background:
/// the account never has to be copied on the screen's thread.
MergeResult mergeState(Object? raw, List<AccountOp> ops, {bool encode = true}) {
  final state = decodeStateData(raw);
  final compactRaw = encode && !isCompressedStateData(raw) ? encodeStateData(state) : null;
  var applied = 0;
  final rejected = <String>[];
  for (final op in ops) {
    op.rejection = null;
    if (op.apply(state)) {
      applied++;
    } else if (op.rejection != null) {
      rejected.add(op.rejection!);
    }
  }
  return MergeResult(state, encode && applied > 0 ? encodeStateData(state) : null, applied, rejected, compactRaw);
}

/// [mergeState] through [background]. A plain top-level function on purpose:
/// the closure handed to the isolate then holds only [raw] and [ops] (a
/// closure made inside an async method can hold its whole context).
Future<MergeResult> mergeInBackground(BackgroundRunner background, Object? raw, List<AccountOp> ops,
    {bool encode = true}) {
  final copy = List<AccountOp>.of(ops);
  return background(() => mergeState(raw, copy, encode: encode));
}

class SyncResult {
  SyncResult(this.state, this.raw, this.updatedAt, this.uploaded, [this.rejected = const [], this.index]);

  /// Per-record storage: what this device now knows of the cloud's records
  /// (null when the account uses the single row).
  final RecordIndex? index;

  /// The cloud copy after this sync, decoded — or null when it is exactly the
  /// copy the device already had ([SyncResult.raw] is then that copy).
  final Map<String, dynamic>? state;

  /// The cloud copy after this sync, as stored.
  final Object? raw;
  final String updatedAt;

  /// Changes that were written by this sync (already-present ones excluded).
  final int uploaded;

  /// Changes the newer cloud copy could not take (e.g. the title was deleted).
  final List<String> rejected;
}

/// Pulls the latest cloud copy and, if there are pending changes, replays them
/// on top of it and writes the result with a compare-and-swap on `updated_at`.
/// Never overwrites a newer cloud version and never duplicates a change.
///
/// With [knownRaw] / [knownUpdatedAt] (the copy the device already has), the
/// account is only downloaded when the cloud has a newer version. Decoding,
/// replaying and encoding run through [background].
Future<SyncResult> syncOnce(
  CloudBackend cloud,
  String userId,
  List<AccountOp> pending, {
  Object? knownRaw,
  String? knownUpdatedAt,
  RecordIndex? knownIndex,
  String deviceId = 'mediaflow-app',
  BackgroundRunner background = runInIsolate,
  int attempts = 5,
}) async {
  if (cloud is RecordBackend && await cloud.usesRecords(userId)) {
    return syncRecords(cloud, userId, pending,
        knownRaw: knownRaw, knownIndex: knownIndex, deviceId: deviceId, background: background);
  }
  var known = knownRaw != null && knownUpdatedAt != null ? CloudSnapshot(knownRaw, knownUpdatedAt) : null;
  for (var attempt = 0; attempt < attempts; attempt++) {
    CloudSnapshot? remote;
    if (known != null) {
      final v = await cloud.version(userId);
      if (v == null) throw MissingCloudRow();
      if (v == known.updatedAt) {
        // Nothing new in the cloud and nothing to upload: keep what we have.
        if (pending.isEmpty) return SyncResult(null, known.raw, known.updatedAt, 0);
        remote = known;
      }
    }
    remote ??= await cloud.fetch(userId);
    if (remote == null) throw MissingCloudRow();
    final merged = await mergeInBackground(background, remote.raw, pending);
    if (merged.applied == 0) {
      return SyncResult(merged.state, merged.compactRaw ?? remote.raw, remote.updatedAt, 0, merged.rejected);
    }
    final updatedAt = await cloud.compareAndSwap(userId, remote.updatedAt, merged.payload!);
    if (updatedAt != null) {
      return SyncResult(merged.state, merged.payload, updatedAt, merged.applied, merged.rejected);
    }
    // Someone saved first: fetch their version and replay on it.
    known = null;
    await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
  }
  throw CloudBusy();
}

// ---- per-record storage (website v556) -------------------------------------------

/// One record sync, worked out in the background: the cloud's rows applied to
/// the device's copy, this device's pending changes replayed on top, and the
/// records that changed as a result.
class RecordStep {
  RecordStep(this.state, this.raw, this.index, this.uploads, this.applied, this.rejected);

  /// The account after this sync (null when unchanged).
  final Map<String, dynamic>? state;
  final Object? raw;
  final RecordIndex index;
  final List<RecordUpload> uploads;
  final int applied;
  final List<String> rejected;
}

/// Pure and synchronous (runs in an isolate). [known]/[knownRaw] are what the
/// device had after its last sync; [rows] are the cloud rows changed since.
RecordStep recordStep(Object? knownRaw, RecordIndex? known, List<RecordRow> rows, List<AccountOp> ops) {
  final index = known?.copy() ?? RecordIndex();
  final fresh = known == null || knownRaw == null || known.cursor.isEmpty;
  var cursor = fresh ? '' : index.cursor;
  Map<String, dynamic>? base;
  var changed = false;
  if (fresh) {
    index.entries.clear();
    final recs = <String, Rec>{};
    for (final r in rows) {
      if (r.kind == 'meta') continue;
      if (r.updatedAt.compareTo(cursor) > 0) cursor = r.updatedAt;
      final key = recordKey(r.kind, r.recordId);
      final data = r.deleted ? null : r.data;
      if (data == null) {
        recs.remove(key);
        index.entries.remove(key);
      } else {
        recs[key] = Rec(r.kind, r.recordId, r.pos, data);
        index.entries[key] = (r.pos, recHash(data, r.pos));
      }
    }
    base = composeState(recs.values);
    changed = true;
  } else {
    // Only rows that differ from what this device already has (its own saves
    // come back unchanged and are skipped).
    final incoming = <String, RecordRow>{};
    for (final r in rows) {
      if (r.kind == 'meta') continue;
      if (r.updatedAt.compareTo(cursor) > 0) cursor = r.updatedAt;
      final key = recordKey(r.kind, r.recordId);
      final data = r.deleted ? null : r.data;
      final h = data == null ? null : recHash(data, r.pos);
      final cur = index.entries[key];
      if (cur != null && cur.$2 == h) {
        incoming.remove(key);
        continue;
      }
      if (cur == null && h == null) {
        incoming.remove(key);
        continue;
      }
      incoming[key] = r;
    }
    if (incoming.isNotEmpty) {
      final current = decodeStateData(knownRaw);
      final recs = decomposeState(current, index.pos);
      for (final e in incoming.entries) {
        final r = e.value;
        final data = r.deleted ? null : r.data;
        if (data == null) {
          recs.remove(e.key);
          index.entries.remove(e.key);
        } else {
          recs[e.key] = Rec(r.kind, r.recordId, r.pos, data);
          index.entries[e.key] = (r.pos, recHash(data, r.pos));
        }
      }
      base = composeState(recs.values);
      changed = true;
    }
  }
  index.cursor = cursor;
  if (ops.isEmpty) {
    return RecordStep(changed ? base : null, changed ? encodeStateData(base!) : knownRaw, index, const [], 0, const []);
  }
  final next = base ?? decodeStateData(knownRaw);
  var applied = 0;
  final rejected = <String>[];
  for (final op in ops) {
    op.rejection = null;
    if (op.apply(next)) {
      applied++;
    } else if (op.rejection != null) {
      rejected.add(op.rejection!);
    }
  }
  if (applied == 0) {
    return RecordStep(changed ? next : null, changed ? encodeStateData(next) : knownRaw, index, const [], 0, rejected);
  }
  final recs = decomposeState(next, index.pos);
  final uploads = <RecordUpload>[];
  for (final r in recs.values) {
    final h = recHash(r.j, r.pos);
    if (index.entries[r.key]?.$2 == h) continue;
    uploads.add(RecordUpload(r.k, r.i, r.pos, r.j));
    index.entries[r.key] = (r.pos, h);
  }
  for (final key in index.entries.keys.where((k) => !recs.containsKey(k)).toList()) {
    final cut = key.indexOf('\u0001');
    uploads.add(RecordUpload(key.substring(0, cut), key.substring(cut + 1), null, null, deleted: true));
    index.entries.remove(key);
  }
  return RecordStep(next, encodeStateData(next), index, uploads, applied, rejected);
}

Future<RecordStep> _recordStepInBackground(
    BackgroundRunner background, Object? knownRaw, RecordIndex? known, List<RecordRow> rows, List<AccountOp> ops) {
  final copy = List<AccountOp>.of(ops);
  return background(() => recordStep(knownRaw, known, rows, copy));
}

/// A few seconds before [cursor], so rows saved in the same instant are never missed.
String recordsSince(String cursor) {
  if (cursor.isEmpty) return '';
  final t = DateTime.tryParse(cursor);
  return t == null ? '' : t.toUtc().subtract(const Duration(seconds: 3)).toIso8601String();
}

/// Per-record sync: pull the rows changed since the last sync, replay this
/// device's pending changes on the result, and upload only the records that
/// changed. Pending changes are replayed on the newest copy, so nothing made
/// on another device is overwritten except the same record changed at once.
Future<SyncResult> syncRecords(
  RecordBackend cloud,
  String userId,
  List<AccountOp> pending, {
  Object? knownRaw,
  RecordIndex? knownIndex,
  required String deviceId,
  BackgroundRunner background = runInIsolate,
}) async {
  final usable = knownRaw != null && knownIndex != null && knownIndex.cursor.isNotEmpty;
  final rows = await cloud.fetchRecords(userId, usable ? recordsSince(knownIndex.cursor) : '');
  final step = await _recordStepInBackground(background, usable ? knownRaw : null, usable ? knownIndex : null, rows, pending);
  if (step.uploads.isNotEmpty) await cloud.uploadRecords(userId, step.uploads, deviceId);
  // The cursor stays where the pull ended: this device's own rows come back
  // on the next pull and are recognised, and another device's row saved in
  // the meantime is never skipped.
  return SyncResult(step.state, step.raw, step.index.cursor, step.uploads.isEmpty ? 0 : step.applied, step.rejected, step.index);
}
