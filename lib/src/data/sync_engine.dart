import 'dart:async';

import '../logic/log_engine.dart';

/// The account's cloud copy: the website's `mediaflow_states` row.
class CloudSnapshot {
  CloudSnapshot(this.state, this.updatedAt);
  final Map<String, dynamic> state;
  final String updatedAt;
}

/// Storage the sync engine talks to (Supabase in the app, a fake in tests).
abstract class CloudBackend {
  /// Fresh, mutable copy of the cloud row, or null if the account has none.
  Future<CloudSnapshot?> fetch(String userId);

  /// Writes [state] only if the row still has [expectedUpdatedAt].
  /// Returns the new `updated_at`, or null if someone else saved first.
  Future<String?> compareAndSwap(String userId, String expectedUpdatedAt, Map<String, dynamic> state);
}

class MissingCloudRow implements Exception {
  @override
  String toString() =>
      'No MediaFlow data exists for this account yet. Sign in on the MediaFlow website once to set it up, then sync again.';
}

class CloudBusy implements Exception {
  @override
  String toString() => 'Your account kept changing while syncing. Your logs are safe on this device; try again.';
}

class SyncResult {
  SyncResult(this.state, this.updatedAt, this.uploaded);
  final Map<String, dynamic> state;
  final String updatedAt;

  /// Requests whose logs were written by this sync (already-present ones excluded).
  final int uploaded;
}

/// Pulls the latest cloud copy and, if there are pending logs, replays them on
/// top of it and writes the result with a compare-and-swap on `updated_at`.
/// Never overwrites a newer cloud version and never duplicates a log.
Future<SyncResult> syncOnce(CloudBackend cloud, String userId, List<LogRequest> pending,
    {int attempts = 5}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    final remote = await cloud.fetch(userId);
    if (remote == null) throw MissingCloudRow();
    if (pending.isEmpty) return SyncResult(remote.state, remote.updatedAt, 0);
    var applied = 0;
    for (final req in pending) {
      if (applyLog(remote.state, req).applied) applied++;
    }
    if (applied == 0) return SyncResult(remote.state, remote.updatedAt, 0);
    final updatedAt = await cloud.compareAndSwap(userId, remote.updatedAt, remote.state);
    if (updatedAt != null) return SyncResult(remote.state, updatedAt, applied);
    await Future<void>.delayed(Duration(milliseconds: 120 * (attempt + 1)));
  }
  throw CloudBusy();
}
