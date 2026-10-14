import 'dart:math';

import '../data/mediaflow_models.dart';
import 'native_cas_protocol.dart';
import 'native_draft_journal.dart';
import 'native_edit_proposals.dart';
import 'native_editing_workspace.dart';
import 'native_snapshot_codec.dart';
import 'native_sync_review.dart';

/// Opaque *read-only* anchor captured from the actual authenticated cloud
/// SELECT that produced the catalog shown on-screen. Never built from a
/// lossy offline projection or a client-controlled updated_at alone.
class NativePriorityCloudAnchor {
  const NativePriorityCloudAnchor({
    required this.ownerId,
    required this.revision,
    required this.fullPayloadDigest,
  });
  final String ownerId, revision, fullPayloadDigest;
}

/// Connects the native RAM-only title drafts to the existing encrypted
/// pending-REVIEW format. Does not submit changes or stage an offline queue.
/// Only priority-only edits can be reviewed. All other v410 mutations require
/// full multi-root side-effect parity and an installed shared web/native CAS.
class NativePriorityReviewCoordinator {
  NativePriorityReviewCoordinator({
    required this.ownerId,
    required this.isOwnerCurrent,
    required this.fetchFreshCloudRow,
    required this.loadEncryptedReview,
    required this.saveEncryptedReview,
    required this.clearEncryptedReview,
  });

  final String ownerId;
  final bool Function() isOwnerCurrent;
  final Future<NativeCloudRow> Function() fetchFreshCloudRow;
  final Future<NativeReviewBatch?> Function(String ownerId) loadEncryptedReview;
  final Future<void> Function(NativeReviewBatch batch, String ownerId)
      saveEncryptedReview;
  final Future<void> Function(String ownerId) clearEncryptedReview;
  bool _busy = false;

  bool get busy => _busy;
  bool _hasOwner => ownerId.isNotEmpty && isOwnerCurrent();

  void _verifyOwner() {
    if (!_hasOwner) throw StateError('Authenticated account changed');
  }

  Future<T> _exclusive<T>(Future<T> Function() work) async {
    _verifyOwner();
    if (_busy) throw StateError('A review operation is already in progress');
    _busy = true;
    try {
      final result = await work();
      _verifyOwner();
      return result;
    } finally {
      _busy = false;
    }
  }

  Future<NativeReviewBatch?> pendingReview() => _exclusive(() async {
    final batch = await loadEncryptedReview(ownerId);
    _verifyOwner();
    return batch == null ? null : NativeReviewBatch.fromJson(
      batch.toJson(), signedInOwnerId: ownerId,
    );
  });

  /// A fresh authenticated SELECT is mandatory. If anything changed since
  /// the catalog's original cloud read, the draft is quarantined: no rebase,
  /// no default state reconstruction and no silent merge.
  Future<NativeReviewBatch> stage({
    required NativeEditingWorkspace workspace,
    required MediaFlowCatalog catalog,
    required NativePriorityCloudAnchor anchor,
    required bool isDisplayedAuthoritativeCloud,
  }) => _exclusive(() async {
    if (!isDisplayedAuthoritativeCloud ||
        anchor.ownerId != ownerId ||
        anchor.revision.isEmpty ||
        anchor.fullPayloadDigest.isEmpty ||
        workspace.ownerId != ownerId ||
        workspace.stale ||
        !identical(workspace.baseCatalog, catalog)) {
      throw StateError('An unchanged, authenticated cloud Library is required');
    }
    if (workspace.titleDrafts.isEmpty ||
        workspace.logCount != 0 ||
        workspace.itemizedCount != 0) {
      throw StateError('Only priority-only title drafts can be reviewed');
    }
    if (workspace.titleDrafts.length > NativeReviewBatch.maxOperations) {
      throw StateError('Too many title drafts');
    }
    final previous = await loadEncryptedReview(ownerId);
    _verifyOwner();
    if (previous != null) {
      throw StateError('Discard the existing encrypted review first');
    }

    final row = await fetchFreshCloudRow();
    _verifyOwner();
    if (row.ownerId != ownerId ||
        row.updatedAt != anchor.revision ||
        NativeReviewBatch.digest(row) != anchor.fullPayloadDigest) {
      throw StateError('Cloud snapshot changed; review the Library again');
    }
    final raw = NativeSnapshotCodec.decode(row.stateData);
    final library = raw['library'];
    if (library is! List || raw['settings'] is! Map ||
        raw['sessions'] is! List || raw['categories'] is! List) {
      throw const FormatException('Incomplete authenticated cloud snapshot');
    }
    final journal = NativeDraftJournal(accountId: ownerId);
    final ids = <String>{};
    final rand = Random.secure();
    for (final edit in workspace.titleDrafts) {
      if (!ids.add(edit.titleId) ||
          edit.statusSideEffectsUnverified ||
          !const {'low','medium','high'}.contains(edit.priority)) {
        throw StateError('Unsupported title changes; priority only');
      }
      final baseMatches = catalog.library.where(
        (t) => t.id == edit.titleId).toList();
      final rawMatches = library.whereType<Map>().where(
        (t) => t['id'] == edit.titleId).toList();
      if (baseMatches.length != 1 || rawMatches.length != 1) {
        throw StateError('Missing or duplicate source title');
      }
      final base = baseMatches.single;
      final stored = rawMatches.single;
      if (edit.title != base.title ||
          edit.status != base.status ||
          edit.progress != base.progress ||
          edit.rating != base.rating ||
          stored['priority'] != base.priority ||
          stored['status'] != base.status ||
          stored['title'] != base.title ||
          (stored['progress'] as num?)?.toDouble() != base.progress ||
          (stored['rating'] as num?)?.toDouble() != base.rating ||
          edit.priority == base.priority) {
        throw StateError('Draft is stale or contains unsupported field changes');
      }
      final operationId = 'review_${List.generate(16,
          (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      journal.add(NativeDraftEntry(
        operationId: operationId,
        proposal: NativeEditProposal(
          kind: NativeEditKind.setTitlePriority,
          accountId: ownerId,
          baseRevision: row.updatedAt,
          createdAt: DateTime.now().toUtc(),
          payload: {'titleId': edit.titleId, 'value': edit.priority},
        ),
      ));
    }

    final batchId = 'batch_${List.generate(16,
        (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final batch = NativeReviewBatch.stage(
      batchId: batchId, base: row, journal: journal,
    );
    final check = NativeSyncReview.inspect(
      batch: batch, cloudRow: row, signedInOwnerId: ownerId,
    );
    if (!check.simulationOnly || check.mayUpload) {
      throw StateError('Review failed local-only safety checks');
    }
    _verifyOwner();
    await saveEncryptedReview(batch, ownerId);
    _verifyOwner();
    // The saved value only contains owner, revision, SHA256, and operations;
    // never the full cloud state_data or any cloud write authorization.
    return batch;
  });

  /// Explicit user action; every inspection reads a fresh full cloud row.
  /// A stale review remains encrypted but blocked, until manually discarded.
  Future<NativeReviewDecision> inspectPending() => _exclusive(() async {
    final batch = await loadEncryptedReview(ownerId);
    _verifyOwner();
    if (batch == null) {
      return const NativeReviewDecision(
        NativeReviewStatus.invalidDraft, 'No saved pending review',
      );
    }
    final NativeCloudRow row;
    try {
      row = await fetchFreshCloudRow();
    } catch (_) {
      _verifyOwner();
      return const NativeReviewDecision(
        NativeReviewStatus.missingCloudRow,
        'Fresh authenticated cloud check failed; nothing was submitted',
      );
    }
    _verifyOwner();
    return NativeSyncReview.inspect(
      batch: batch, cloudRow: row, signedInOwnerId: ownerId,
    );
  });

  /// Explicit user action. Removes only device-local encrypted review data
  /// and its key; the user's cloud account and RAM title drafts are unchanged.
  Future<void> discardPending() => _exclusive(() async {
    await clearEncryptedReview(ownerId);
    _verifyOwner();
  });
}
