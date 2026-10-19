import 'native_edit_proposals.dart';
import 'native_snapshot_codec.dart';

/// Milestone 9 capability gate. Neither Flutter UI nor the production
/// repository provides a native cloud-write method.
abstract final class NativeCloudCapabilities {
  static const bool cloudWritesEnabled = false;
  static const bool hasServerSideCas = false;
  static const bool offlineWriteQueueEnabled = false;
}

/// Immutable-by-copy representation of ONE authenticated cloud row.
/// Keep updated_at in its original textual precision; the website currently
/// sends this timestamp explicitly, so it must NOT be trusted alone.
class NativeCloudRow {
  NativeCloudRow({
    required this.ownerId,
    required this.updatedAt,
    required Map<String, dynamic> stateData,
  }) : _stateData = NativeSnapshotCodec.deepClone(stateData);

  final String ownerId;
  final String updatedAt;
  final Map<String, dynamic> _stateData;
  Map<String, dynamic> get stateData =>
      NativeSnapshotCodec.deepClone(_stateData);
}

/// A hypothetical CAS transaction to evaluate against a *test* server.
/// The expected opaque JSONB payload AND updated_at must both match the
/// database row in the same SQL UPDATE statement. Never use a client-side
/// read-then-unconditional-upsert as an alternative.
class NativeCasPlan {
  NativeCasPlan({
    required this.ownerId,
    required this.expectedUpdatedAt,
    required Map<String, dynamic> expectedStateData,
    required Map<String, dynamic> proposedStateData,
  })  : _expected = NativeSnapshotCodec.deepClone(expectedStateData),
        _proposed = NativeSnapshotCodec.deepClone(proposedStateData);

  final String ownerId;
  final String expectedUpdatedAt;
  final Map<String, dynamic> _expected;
  final Map<String, dynamic> _proposed;

  Map<String, dynamic> get expectedStateData =>
      NativeSnapshotCodec.deepClone(_expected);
  Map<String, dynamic> get proposedStateData =>
      NativeSnapshotCodec.deepClone(_proposed);
}

class NativePlanResult {
  const NativePlanResult.blocked(this.reason) : plan = null;
  const NativePlanResult.prepared(this.plan) : reason = '';

  final String reason;
  final NativeCasPlan? plan;
  bool get isReadyForSimulation => plan != null;
}

abstract final class NativeSyncPreflight {
  /// Read-only preparation. It never connects to a database, saves a cache,
  /// mutates the input row, or enables production cloud writes.
  static NativePlanResult prepare({
    required NativeCloudRow row,
    required NativeEditProposal proposal,
  }) {
    if (row.ownerId.isEmpty ||
        row.ownerId != proposal.accountId) {
      return const NativePlanResult.blocked('Account ownership mismatch');
    }
    if (row.updatedAt.isEmpty ||
        proposal.baseRevision != row.updatedAt) {
      return const NativePlanResult.blocked('Cloud revision mismatch');
    }
    // v410 status changes can update completionTimeline, XP and history.
    // This milestone models them locally but never stages them for cloud.
    if (proposal.kind == NativeEditKind.setTitleStatus) {
      return const NativePlanResult.blocked(
        'Status changes require full v410 side-effect parity',
      );
    }

    final raw = row.stateData;
    final Map<String, dynamic> state;
    try {
      state = NativeSnapshotCodec.decode(raw);
    } on FormatException {
      return const NativePlanResult.blocked('Missing or invalid cloud state');
    }
    // No "create defaults" path is allowed to turn a failed/missing read
    // into a new empty cloud state. Stop even for an empty-but-valid account
    // if the minimum known v410 structure is missing.
    if (state['library'] is! List ||
        state['sessions'] is! List ||
        state['categories'] is! List ||
        state['settings'] is! Map) {
      return const NativePlanResult.blocked(
        'Incomplete cloud snapshot; explicit recovery required',
      );
    }

    final preview = previewNativeEdit(
      state: state,
      accountId: row.ownerId,
      revision: row.updatedAt,
      proposal: proposal,
    );
    if (!preview.valid || preview.updatedState == null) {
      return NativePlanResult.blocked(preview.message);
    }
    final changed = preview.updatedState!;
    if (!NativeSnapshotCodec.equivalent(
        state.keys.toList()..sort(), changed.keys.toList()..sort())) {
      return const NativePlanResult.blocked('Snapshot fields were removed');
    }
    if ((state['library'] as List).length !=
        (changed['library'] as List).length ||
        (state['sessions'] as List).length !=
        (changed['sessions'] as List).length) {
      return const NativePlanResult.blocked(
        'Unexpected Library/History cardinality change',
      );
    }
    if (NativeSnapshotCodec.equivalent(state, changed)) {
      return const NativePlanResult.blocked('Proposal makes no change');
    }

    final Map<String, dynamic> nextRaw;
    try {
      nextRaw = NativeSnapshotCodec.encodeLike(changed, raw);
      final decodedAgain = NativeSnapshotCodec.decode(nextRaw);
      if (!NativeSnapshotCodec.equivalent(changed, decodedAgain)) {
        return const NativePlanResult.blocked('Cloud encoding validation failed');
      }
    } on FormatException {
      return const NativePlanResult.blocked('Cloud encoding validation failed');
    }

    return NativePlanResult.prepared(NativeCasPlan(
      ownerId: row.ownerId,
      expectedUpdatedAt: row.updatedAt,
      expectedStateData: raw,
      proposedStateData: nextRaw,
    ));
  }
}

enum NativeCasCheck { wouldApply, conflict, missing, accessDenied }

/// Models the SQL WHERE predicate, without performing a write. This method
/// is useful for simulated concurrent requests and retry/conflict tests.
abstract final class NativeCasSimulator {
  static NativeCasCheck check({
    required NativeCasPlan plan,
    required NativeCloudRow? current,
  }) {
    if (current == null) return NativeCasCheck.missing;
    if (current.ownerId != plan.ownerId) {
      return NativeCasCheck.accessDenied;
    }
    if (current.updatedAt != plan.expectedUpdatedAt ||
        !NativeSnapshotCodec.equivalent(
          current.stateData, plan.expectedStateData,
        )) {
      return NativeCasCheck.conflict;
    }
    return NativeCasCheck.wouldApply;
  }
}
