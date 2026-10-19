import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/mediaflow_full_state.dart';
import 'native_cas_protocol.dart';
import 'native_snapshot_codec.dart';

/// Review-only protocol prototype for a future shared web/Flutter sync API.
///
/// IMPORTANT: This file defines NO Supabase client, network request, RPC,
/// persistent write, offline replay or production capability. In particular,
/// neither a simulated receipt nor a simulated ready gate authorizes writes.
/// The v410 website must stop unconditional state_data UPSERTs before any
/// native write capability can be deployed.
abstract final class NativeM30Protocol {
  static const String version = 'mediaflow-shared-sync-v1-review-only';
  static const bool deployed = false;
  static const bool cloudWritesEnabled = NativeCloudCapabilities.cloudWritesEnabled;

  static String digest(Object raw) => sha256.convert(
    utf8.encode(NativeSnapshotCodec.canonicalJson(raw)),
  ).toString();

  static Object copy(Object raw) => jsonDecode(jsonEncode(raw)) as Object;
}

/// Independent, versioned revision token is mandatory; website updated_at
/// alone cannot be a CAS token. Production migration/backfill is unimplemented.
class NativeM30RevisionedSnapshot {
  NativeM30RevisionedSnapshot({
    required this.ownerId,
    required this.revision,
    required Object wire,
    required this.legacyUpdatedAt,
  }) : _wire = NativeM30Protocol.copy(wire) {
    if (ownerId.isEmpty || revision < 1) {
      throw const FormatException('Invalid versioned account snapshot');
    }
    MediaFlowFullState.parse(_wire);
  }

  final String ownerId;
  final int revision;
  final String legacyUpdatedAt;
  final Object _wire;

  Object get wire => NativeM30Protocol.copy(_wire);
  String get wireDigest => NativeM30Protocol.digest(_wire);
}

/// This narrow operation is known to have no web History/XP side effects.
/// Complex v410 actions, status changes, logging and Collection edits must
/// first gain *complete* source-backed multi-root transactional parity.
class NativeM30PriorityIntent {
  NativeM30PriorityIntent({
    required this.ownerId,
    required this.operationId,
    required this.expectedRevision,
    required this.expectedDigest,
    required this.titleId,
    required this.priority,
  }) {
    if (ownerId.isEmpty ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(operationId) ||
        expectedRevision < 1 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedDigest) ||
        titleId.isEmpty ||
        !const {'low', 'medium', 'high'}.contains(priority)) {
      throw const FormatException('Invalid shared-sync priority intent');
    }
  }

  factory NativeM30PriorityIntent.forSnapshot({
    required NativeM30RevisionedSnapshot base,
    required String operationId,
    required String titleId,
    required String priority,
  }) => NativeM30PriorityIntent(
    ownerId: base.ownerId,
    operationId: operationId,
    expectedRevision: base.revision,
    expectedDigest: base.wireDigest,
    titleId: titleId,
    priority: priority,
  );

  final String ownerId, operationId, expectedDigest, titleId, priority;
  final int expectedRevision;

  /// Idempotency is owner + operation ID + the entire frozen intent, not a
  /// timestamp or a hash of *only* the proposed scalar change.
  String get fingerprint => NativeM30Protocol.digest({
    'protocol': NativeM30Protocol.version,
    'ownerId': ownerId,
    'operationId': operationId,
    'expectedRevision': expectedRevision,
    'expectedDigest': expectedDigest,
    'titleId': titleId,
    'priority': priority,
  });
}

/// These booleans are synthetic *test evidence* only. They do not switch on
/// any native feature and do not represent deployed Supabase capabilities.
class NativeM30SyntheticGate {
  const NativeM30SyntheticGate({
    this.websiteUsesSharedProtocol = false,
    this.legacyDirectWritesBlocked = false,
    this.ownerRlsAudited = false,
    this.durableReceiptsModeled = false,
    this.backupAndRestoreVerified = false,
    this.allWritersCompatible = false,
    this.sideEffectsVerified = false,
  });

  const NativeM30SyntheticGate.testOnlyComplete()
      : websiteUsesSharedProtocol = true,
        legacyDirectWritesBlocked = true,
        ownerRlsAudited = true,
        durableReceiptsModeled = true,
        backupAndRestoreVerified = true,
        allWritersCompatible = true,
        sideEffectsVerified = true;

  final bool websiteUsesSharedProtocol, legacyDirectWritesBlocked;
  final bool ownerRlsAudited, durableReceiptsModeled;
  final bool backupAndRestoreVerified, allWritersCompatible;
  final bool sideEffectsVerified;

  bool get readyForTestOnly => websiteUsesSharedProtocol &&
      legacyDirectWritesBlocked &&
      ownerRlsAudited &&
      durableReceiptsModeled &&
      backupAndRestoreVerified &&
      allWritersCompatible &&
      sideEffectsVerified;
}

enum NativeM30Result {
  applied, replayed, protocolUnavailable, unauthorized,
  missing, conflict, reusedOperationId, invalid, noChange,
  legacyWriteBlocked,
}

class NativeM30Receipt {
  const NativeM30Receipt(
    this.result, {this.revision, this.digest, this.message = ''}
  );
  final NativeM30Result result;
  final int? revision;
  final String? digest;
  final String message;

  bool get succeeded => result == NativeM30Result.applied ||
      result == NativeM30Result.replayed;
}

/// An in-memory single-threaded *simulation of one atomic server transaction*.
/// Both hypothetical website and native writers enter this exact function.
/// Never instantiate it as a production account repository or sync transport.
class NativeM30SimulatedSharedServer {
  NativeM30SimulatedSharedServer({
    this.gate = const NativeM30SyntheticGate(),
  });

  final NativeM30SyntheticGate gate;
  final Map<String, NativeM30RevisionedSnapshot> _rows = {};
  final Map<String, _NativeM30LedgerReceipt> _receipts = {};

  /// Only used to build independent synthetic fixtures in tests.
  void seedForTest(NativeM30RevisionedSnapshot row) {
    if (_rows.containsKey(row.ownerId)) {
      throw StateError('Cannot silently replace an existing account');
    }
    _rows[row.ownerId] = NativeM30RevisionedSnapshot(
      ownerId: row.ownerId,
      revision: row.revision,
      wire: row.wire,
      legacyUpdatedAt: row.legacyUpdatedAt,
    );
  }

  NativeM30RevisionedSnapshot? readForTest({
    required String signedInOwnerId,
    required String ownerId,
  }) {
    if (signedInOwnerId.isEmpty || signedInOwnerId != ownerId) return null;
    final row = _rows[ownerId];
    return row == null ? null : NativeM30RevisionedSnapshot(
      ownerId: row.ownerId, revision: row.revision,
      wire: row.wire, legacyUpdatedAt: row.legacyUpdatedAt,
    );
  }

  /// Simulates the required revocation of legacy unconditional UPSERT.
  /// It can never change synthetic state or return a success receipt.
  NativeM30Receipt legacyUpsertForTest({
    required String signedInOwnerId,
    required String ownerId,
    required Object wire,
  }) => const NativeM30Receipt(NativeM30Result.legacyWriteBlocked,
    message: 'Legacy unconditional full-state writes must be denied');

  /// Synchronous fake models a future database-side transaction containing:
  /// authorization, durable idempotency receipt, revision + full wire digest
  /// comparison, lossless patch, revision increment, and receipt insertion.
  /// It does NOT actually provide PostgreSQL transaction guarantees.
  NativeM30Receipt commitForTest({
    required String signedInOwnerId,
    required NativeM30PriorityIntent intent,
    required String clientKind,
  }) {
    // ClientKind is a test label (website / Android / Windows / iOS), NOT
    // authentication evidence or an authorization mechanism.
    if (signedInOwnerId.isEmpty || signedInOwnerId != intent.ownerId) {
      return const NativeM30Receipt(NativeM30Result.unauthorized);
    }
    if (!gate.readyForTestOnly) {
      return const NativeM30Receipt(NativeM30Result.protocolUnavailable);
    }
    if (!const {'website', 'android', 'windows', 'ios'}.contains(clientKind)) {
      return const NativeM30Receipt(NativeM30Result.invalid,
        message: 'Unknown synthetic client kind');
    }
    final key = '${intent.ownerId}:${intent.operationId}';
    final prior = _receipts[key];
    if (prior != null) {
      if (prior.fingerprint != intent.fingerprint) {
        return const NativeM30Receipt(NativeM30Result.reusedOperationId);
      }
      return NativeM30Receipt(NativeM30Result.replayed,
        revision: prior.revision, digest: prior.digest);
    }
    final row = _rows[intent.ownerId];
    if (row == null) return const NativeM30Receipt(NativeM30Result.missing);
    if (row.revision != intent.expectedRevision ||
        row.wireDigest != intent.expectedDigest) {
      return const NativeM30Receipt(NativeM30Result.conflict,
        message: 'Discard or manually review a stale draft; never auto-merge');
    }
    try {
      final original = MediaFlowFullState.parse(row.wire);
      final titles = original.root('library');
      if (titles is! List) {
        return const NativeM30Receipt(NativeM30Result.invalid);
      }
      final indexes = <int>[];
      for (var i = 0; i < titles.length; i++) {
        final value = titles[i];
        if (value is Map && value['id'] == intent.titleId) {
          indexes.add(i);
        }
      }
      if (indexes.length != 1) {
        return const NativeM30Receipt(NativeM30Result.invalid,
          message: 'Missing or duplicated Library ID');
      }
      final previous = original.at(['library', indexes.single, 'priority']);
      if (previous == intent.priority) {
        return const NativeM30Receipt(NativeM30Result.noChange);
      }
      final changed = original.simulateScalarReplacement(
        ['library', indexes.single, 'priority'], intent.priority,
      );
      final wire = changed.encodeForLocalParityTest();
      final next = NativeM30RevisionedSnapshot(
        ownerId: row.ownerId,
        revision: row.revision + 1,
        wire: wire,
        // Intentionally unchanged: demonstrates why updated_at is *not*
        // the authoritative revision / conflict token.
        legacyUpdatedAt: row.legacyUpdatedAt,
      );
      // A real backend must make the following two changes inseparable,
      // durable and conditional under a per-owner transaction/row lock.
      _rows[intent.ownerId] = next;
      _receipts[key] = _NativeM30LedgerReceipt(
        fingerprint: intent.fingerprint,
        revision: next.revision, digest: next.wireDigest,
      );
      return NativeM30Receipt(NativeM30Result.applied,
        revision: next.revision, digest: next.wireDigest);
    } on FormatException {
      return const NativeM30Receipt(NativeM30Result.invalid,
        message: 'Invalid, incomplete or unsafe source account');
    } on StateError {
      return const NativeM30Receipt(NativeM30Result.invalid,
        message: 'Unpreserved original account data');
    }
  }
}

class _NativeM30LedgerReceipt {
  const _NativeM30LedgerReceipt({
    required this.fingerprint,
    required this.revision,
    required this.digest,
  });
  final String fingerprint, digest;
  final int revision;
}
