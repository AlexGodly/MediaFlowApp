// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'native_cas_protocol.dart';
import 'native_draft_journal.dart';
import 'native_edit_proposals.dart';
import 'native_snapshot_codec.dart';

/// M19: an inert, owner-scoped pending REVIEW record, not a queued cloud write.
/// The complete v410 row never enters local pending-draft persistence.
class NativeReviewBatch {
  NativeReviewBatch._({
    required this.batchId,
    required this.ownerId,
    required this.baseRevision,
    required this.baseDigest,
    required List<NativeDraftEntry> entries,
  }) : _entries = List.unmodifiable(entries.map((item) =>
      NativeDraftEntry.fromJson(Map<String, dynamic>.from(
        jsonDecode(jsonEncode(item.toJson())) as Map,
      )),
    ));

  static const format = 'mediaflow-native-sync-review-v1';
  static const maxOperations = 1000;
  static const maxSerializedBytes = 1024 * 1024;
  static final _identifier = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');
  final String batchId, ownerId, baseRevision, baseDigest;
  final List<NativeDraftEntry> _entries;

  /// This is a detached list; callers can't mutate a stored batch's payload.
  List<NativeDraftEntry> get entries => List.unmodifiable(
    _entries.map((item) => NativeDraftEntry.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(item.toJson())) as Map),
    )),
  );

  static String digest(NativeCloudRow row) => sha256.convert(
    utf8.encode(NativeSnapshotCodec.canonicalJson(row.stateData)),
  ).toString();

  /// The caller must provide the authenticated, full, non-offline cloud row.
  /// Only locally safe operations are admitted by the existing preflight.
  static NativeReviewBatch stage({
    required String batchId,
    required NativeCloudRow base,
    required NativeDraftJournal journal,
  }) {
    if (!_identifier.hasMatch(batchId) ||
        base.ownerId.isEmpty ||
        base.updatedAt.isEmpty ||
        journal.accountId != base.ownerId ||
        journal.entries.isEmpty ||
        journal.entries.length > maxOperations) {
      throw StateError('Invalid batch identity or operation count');
    }
    final preview = journal.preview(base);
    if (!preview.isValid) {
      throw StateError('Cannot stage unsafe draft: ' + preview.reason);
    }
    final value = NativeReviewBatch._(
      batchId: batchId,
      ownerId: base.ownerId,
      baseRevision: base.updatedAt,
      baseDigest: digest(base),
      entries: journal.entries,
    );
    // The portable batch must never contain the unmodified cloud row.
    value._validate();
    return value;
  }

  Map<String, dynamic> toJson() => {
    'format': format,
    'batchId': batchId,
    'ownerId': ownerId,
    'baseRevision': baseRevision,
    'baseDigest': baseDigest,
    'operations': [for (final item in _entries) item.toJson()],
  };

  void _validate() {
    if (!_identifier.hasMatch(batchId) ||
        ownerId.isEmpty ||
        baseRevision.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(baseDigest) ||
        _entries.isEmpty ||
        _entries.length > maxOperations) {
      throw const FormatException('Invalid native pending batch');
    }
    final ids = <String>{};
    for (final item in _entries) {
      if (!ids.add(item.operationId) ||
          item.proposal.accountId != ownerId ||
          item.proposal.baseRevision != baseRevision ||
          item.proposal.kind == NativeEditKind.setTitleStatus) {
        throw const FormatException('Mixed, duplicate, or unsafe operation');
      }
    }
    if (utf8.encode(jsonEncode(toJson())).length > maxSerializedBytes) {
      throw const FormatException('Pending batch exceeds safe size');
    }
  }

  factory NativeReviewBatch.fromJson(
    Map<String, dynamic> value, {
    required String signedInOwnerId,
  }) {
    if (value['format'] != format ||
        signedInOwnerId.isEmpty ||
        value['ownerId'] != signedInOwnerId ||
        value['operations'] is! List) {
      throw const FormatException('Unsupported or foreign pending batch');
    }
    final raw = value['operations'] as List;
    if (raw.length > maxOperations ||
        utf8.encode(jsonEncode(value)).length > maxSerializedBytes) {
      throw const FormatException('Pending batch exceeds safe limits');
    }
    final batch = NativeReviewBatch._(
      batchId: value['batchId']?.toString() ?? '',
      ownerId: signedInOwnerId,
      baseRevision: value['baseRevision']?.toString() ?? '',
      baseDigest: value['baseDigest']?.toString() ?? '',
      entries: raw.map((item) {
        if (item is! Map) {
          throw const FormatException('Malformed pending operation');
        }
        return NativeDraftEntry.fromJson(Map<String, dynamic>.from(item));
      }).toList(),
    );
    batch._validate();
    return batch;
  }
}

enum NativeReviewStatus {
  safeToSimulate, missingCloudRow, foreignAccount, revisionChanged,
  payloadChanged, invalidDraft, serverProtocolUnavailable,
}

class NativeReviewDecision {
  const NativeReviewDecision(this.status, this.message, [this.plan]);
  final NativeReviewStatus status;
  final String message;
  final NativeCasPlan? plan;

  bool get simulationOnly => status == NativeReviewStatus.safeToSimulate;
  bool get mayUpload => false; // Production cloud transport DOES NOT EXIST.
}

/// Always require a newly supplied full cloud row, not an offline projection.
/// Same updated_at but different state_data MUST be considered a conflict.
abstract final class NativeSyncReview {
  static NativeReviewDecision inspect({
    required NativeReviewBatch batch,
    required NativeCloudRow? cloudRow,
    required String signedInOwnerId,
  }) {
    if (signedInOwnerId.isEmpty || batch.ownerId != signedInOwnerId) {
      return const NativeReviewDecision(
        NativeReviewStatus.foreignAccount, 'Signed-in account mismatch',
      );
    }
    if (cloudRow == null) {
      return const NativeReviewDecision(
        NativeReviewStatus.missingCloudRow, 'Fresh cloud row is required',
      );
    }
    if (cloudRow.ownerId != signedInOwnerId) {
      return const NativeReviewDecision(
        NativeReviewStatus.foreignAccount, 'Cloud owner does not match',
      );
    }
    if (batch.baseRevision != cloudRow.updatedAt) {
      return const NativeReviewDecision(
        NativeReviewStatus.revisionChanged,
        'Cloud revision changed; pending review quarantined',
      );
    }
    if (batch.baseDigest != NativeReviewBatch.digest(cloudRow)) {
      return const NativeReviewDecision(
        NativeReviewStatus.payloadChanged,
        'Cloud data changed even though its timestamp did not',
      );
    }
    try {
      final journal = NativeDraftJournal(accountId: batch.ownerId);
      for (final entry in batch.entries) {
        journal.add(entry);
      }
      final preview = journal.preview(cloudRow);
      if (!preview.isValid) {
        return NativeReviewDecision(
          NativeReviewStatus.invalidDraft, preview.reason,
        );
      }
      final result = NativeCasSimulator.check(
        plan: preview.plan!, current: cloudRow,
      );
      if (result != NativeCasCheck.wouldApply) {
        return NativeReviewDecision(
          NativeReviewStatus.invalidDraft,
          'Atomic simulation failed: ' + result.name,
        );
      }
      return NativeReviewDecision(
        NativeReviewStatus.safeToSimulate,
        'CAS simulation ready; no network writes allowed',
        preview.plan,
      );
    } catch (_) {
      return const NativeReviewDecision(
        NativeReviewStatus.invalidDraft, 'Pending batch is invalid',
      );
    }
  }
}

/// In-memory fake server for demonstrating no lost updates and exactly-once
/// receipts. NOT backed by Supabase and NOT a cloud API implementation.
class NativeSimulatedAtomicServer {
  NativeSimulatedAtomicServer(NativeCloudRow initial) : _row = initial;

  NativeCloudRow? _row;
  final Map<String, (String, String)> _applied = {};

  NativeCloudRow? get current => _row == null ? null : NativeCloudRow(
    ownerId: _row!.ownerId,
    updatedAt: _row!.updatedAt,
    stateData: _row!.stateData,
  );

  void simulateForeignWrite(NativeCloudRow? next) => _row = next;

  NativeSimulatedReceipt commitForTest({
    required NativeReviewBatch batch,
    required String signedInOwnerId,
  }) {
    // Receipt lookup is scoped to one owner and one stable operation batch.
    final receiptKey = batch.ownerId + ':' + batch.batchId;
    if (signedInOwnerId.isEmpty || signedInOwnerId != batch.ownerId) {
      return const NativeSimulatedReceipt('access-denied', false);
    }
    final fingerprint = sha256.convert(
      utf8.encode(NativeSnapshotCodec.canonicalJson(batch.toJson())),
    ).toString();
    final previous = _applied[receiptKey];
    if (previous != null) {
      if (previous.$1 != fingerprint) {
        return const NativeSimulatedReceipt('reused-id-different-batch', false);
      }
      return NativeSimulatedReceipt(previous.$2, true);
    }
    final decision = NativeSyncReview.inspect(
      batch: batch, cloudRow: _row, signedInOwnerId: signedInOwnerId,
    );
    if (!decision.simulationOnly) {
      return NativeSimulatedReceipt(decision.status.name, false);
    }
    // The commit transition is synchronous in this fake only; a real server
    // must implement these checks and commit in ONE PostgreSQL transaction,
    // shared by EVERY writing client. Never emulate with read+UPSERT.
    final nextRevision = 'simulated-revision-' + (_applied.length + 1).toString();
    _row = NativeCloudRow(
      ownerId: signedInOwnerId,
      updatedAt: nextRevision,
      stateData: decision.plan!.proposedStateData,
    );
    _applied[receiptKey] = (fingerprint, nextRevision);
    return NativeSimulatedReceipt(nextRevision, false);
  }
}

class NativeSimulatedReceipt {
  const NativeSimulatedReceipt(this.result, this.alreadyApplied);
  final String result;
  final bool alreadyApplied;
}
