import 'dart:async';
import 'dart:isolate';

import '../state/state_codec.dart';
import 'account_ops.dart';

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
  SyncResult(this.state, this.raw, this.updatedAt, this.uploaded, [this.rejected = const []]);

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
  BackgroundRunner background = runInIsolate,
  int attempts = 5,
}) async {
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
