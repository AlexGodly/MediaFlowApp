import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/mediaflow_full_state.dart';
import 'native_snapshot_codec.dart';

/// Conflict-safe writer for the existing single-row MediaFlow account.
///
/// This is deliberately transport-only: callers must first build a complete,
/// source-compatible next state. It never reconstructs the account from the
/// lossy MediaFlowCatalog projection and never creates tables or calls RPCs.
class NativeCloudStateCommitter {
  NativeCloudStateCommitter({
    required this.client,
    required this.ownerId,
  });

  final SupabaseClient client;
  final String ownerId;

  Future<NativeCloudCommitResult> commit({
    required Object expectedStateData,
    required String expectedUpdatedAt,
    required Object nextStateData,
  }) async {
    _assertOwner();
    if (ownerId.isEmpty || expectedUpdatedAt.trim().isEmpty) {
      throw const FormatException('A signed-in owner and cloud revision are required');
    }

    final expected = MediaFlowFullState.parse(expectedStateData);
    final next = MediaFlowFullState.parse(nextStateData);
    final currentRow = await client
        .from('mediaflow_states')
        .select('state_data,updated_at')
        .eq('user_id', ownerId)
        .maybeSingle();
    _assertOwner();

    if (currentRow == null ||
        currentRow['state_data'] == null ||
        currentRow['updated_at'] == null) {
      throw const NativeCloudStateConflict('The cloud account row is missing');
    }
    final liveRevision = currentRow['updated_at'].toString();
    if (liveRevision != expectedUpdatedAt) {
      throw const NativeCloudStateConflict(
        'The website or another device changed this account. Reload and review your draft.',
      );
    }

    final live = MediaFlowFullState.parse(currentRow['state_data']);
    if (_digest(live.json) != _digest(expected.json)) {
      throw const NativeCloudStateConflict(
        'The cloud payload changed without a matching revision. No data was saved.',
      );
    }
    validatePreservation(expected, next);
    if (_digest(expected.json) == _digest(next.json)) {
      throw const FormatException('There are no account changes to save');
    }

    final previous = DateTime.tryParse(liveRevision)?.toUtc();
    final now = DateTime.now().toUtc();
    final nextRevision = previous != null && !now.isAfter(previous)
        ? previous.add(const Duration(microseconds: 1))
        : now;

    // Compare-and-swap is a single conditional UPDATE. The explicit updated_at
    // value is essential because the existing table has no update trigger.
    final saved = await client
        .from('mediaflow_states')
        .update({
          'state_data': nextStateData,
          'updated_at': nextRevision.toIso8601String(),
        })
        .eq('user_id', ownerId)
        .eq('updated_at', expectedUpdatedAt)
        .select('updated_at')
        .maybeSingle();
    _assertOwner();

    if (saved == null || saved['updated_at'] == null) {
      throw const NativeCloudStateConflict(
        'The account changed during save. Reload before submitting again.',
      );
    }
    return NativeCloudCommitResult(
      ownerId: ownerId,
      previousRevision: expectedUpdatedAt,
      savedRevision: saved['updated_at'].toString(),
    );
  }

  void _assertOwner() {
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('The signed-in account changed. Cloud write blocked.');
    }
  }

  static String _digest(Object? value) => sha256
      .convert(utf8.encode(NativeSnapshotCodec.canonicalJson(value)))
      .toString();

  static void validatePreservation(
    MediaFlowFullState before,
    MediaFlowFullState after,
  ) {
    final beforeState = before.json;
    final afterState = after.json;
    const requiredRoots = ['library', 'categories', 'sessions', 'settings'];
    for (final root in requiredRoots) {
      if (!before.containsRoot(root) || !after.containsRoot(root)) {
        throw FormatException('Cannot save an account missing "$root"');
      }
    }
    for (final root in beforeState.keys) {
      if (!afterState.containsKey(root)) {
        throw FormatException('Refusing to drop existing account field "$root"');
      }
    }
    if (before.format != after.format) {
      throw const FormatException('Refusing to change the account wire format');
    }
  }
}

class NativeCloudCommitResult {
  const NativeCloudCommitResult({
    required this.ownerId,
    required this.previousRevision,
    required this.savedRevision,
  });

  final String ownerId;
  final String previousRevision;
  final String savedRevision;
}

class NativeCloudStateConflict implements Exception {
  const NativeCloudStateConflict(this.message);
  final String message;

  @override
  String toString() => message;
}

class NativeCloudStateSnapshot {
  const NativeCloudStateSnapshot({
    required this.ownerId,
    required this.stateData,
    required this.updatedAt,
  });

  final String ownerId;
  final Object stateData;
  final String updatedAt;
}
