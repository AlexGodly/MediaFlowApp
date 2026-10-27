import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/native_offline_read_coordinator.dart';
import '../services/native_offline_snapshot_store.dart';
import '../services/native_pending_review_store.dart';
import '../services/native_editing_workspace.dart';
import '../services/native_priority_review_coordinator.dart';
import '../services/native_m33_offline_queue.dart';
import '../services/native_m33_draft_store.dart';
import '../services/native_m33_draft_coordinator.dart';
import '../services/native_m34_conflict_review.dart';
import '../services/native_cas_protocol.dart';
import '../services/native_sync_review.dart';
import '../services/native_snapshot_codec.dart';
import 'mediaflow_models.dart';
import 'mediaflow_full_state.dart';
import 'mediaflow_state_codec.dart';
import '../services/native_cloud_state_committer.dart';

export '../services/native_offline_read_coordinator.dart'
    show NativeSnapshotSource;

String _m32FullDigest(Map<String, dynamic> raw) => sha256.convert(
  utf8.encode(NativeSnapshotCodec.canonicalJson(raw)),
).toString();

abstract class MediaFlowLibraryRepository {
  Future<MediaFlowCatalog> load();

  /// Default fallback for test repositories. Production bypasses cache.
  Future<MediaFlowCatalog> reload() => load();
}

/// One signed-in owner's shared, read-only, offline-first data source.
///
/// Cloud remains authoritative, device recovery stays encrypted and lossy,
/// and pending review records are never automatically submitted to cloud.
/// The website and production database are not changed.
class SupabaseMediaFlowLibraryRepository extends MediaFlowLibraryRepository {
  SupabaseMediaFlowLibraryRepository(
    this.client, {
    NativeOfflineSnapshotStore? offlineStore,
    NativePendingReviewStore? pendingReviewStore,
    NativeM33DraftStore? offlineDraftStore,
  }) : _offlineStore = offlineStore ?? NativeOfflineSnapshotStore(),
       _pendingReviews = pendingReviewStore ?? NativePendingReviewStore(),
       _offlineDraftStore = offlineDraftStore ?? NativeM33DraftStore(),
       _ownerId = client.auth.currentUser?.id {
    _readCoordinator = NativeOfflineReadCoordinator(
      ownerId: _ownerId,
      isOwnerCurrent: () => !_closed &&
          _ownerId != null && client.auth.currentUser?.id == _ownerId,
      readCloud: _readCloud,
      readDeviceCopy: _offlineStore.load,
      writeDeviceCopy: _offlineStore.save,
      clearDeviceCopyStorage: _offlineStore.clear,
    );
  }

  final SupabaseClient client;
  final NativeOfflineSnapshotStore _offlineStore;
  final NativePendingReviewStore _pendingReviews;
  final NativeM33DraftStore _offlineDraftStore;
  final String? _ownerId;
  bool _closed = false;
  late final NativeOfflineReadCoordinator _readCoordinator;
  final Expando<NativePriorityCloudAnchor> _cloudAnchors =
      Expando<NativePriorityCloudAnchor>('m32-authoritative-catalog');
  NativePriorityReviewCoordinator? _priorityReviewCoordinator;
  NativePriorityReviewCoordinator get _priorityReview =>
      _priorityReviewCoordinator ??= NativePriorityReviewCoordinator(
        ownerId: _ownerId ?? '',
        isOwnerCurrent: () => !_closed && _ownerId != null &&
            client.auth.currentUser?.id == _ownerId,
        fetchFreshCloudRow: _readFreshForPriorityReview,
        loadEncryptedReview: _pendingReviews.load,
        saveEncryptedReview: _pendingReviews.save,
        clearEncryptedReview: _pendingReviews.clear,
      );
  NativeM33DraftCoordinator? _offlineDraftCoordinator;
  NativeM33DraftCoordinator get _m33 => _offlineDraftCoordinator ??=
      NativeM33DraftCoordinator(
        ownerId: _ownerId ?? '',
        isOwnerCurrent: () => !_closed && _ownerId != null &&
            client.auth.currentUser?.id == _ownerId,
        readStored: _offlineDraftStore.load,
        writeStored: _offlineDraftStore.save,
        deleteStored: _offlineDraftStore.clear,
        replaceStored: _offlineDraftStore.replaceForResolution,
        fetchFreshCloudRow: _readFreshForPriorityReview,
      );
  NativeEditingWorkspace? _editingWorkspace;
  NativeEditingWorkspace get editingWorkspace =>
      _editingWorkspace ??= NativeEditingWorkspace(ownerId: _ownerId ?? '');

  ValueListenable<NativeSnapshotSource> get source => _readCoordinator.source;
  ValueListenable<DateTime?> get offlineSavedAt =>
      _readCoordinator.offlineSavedAt;
  ValueListenable<bool> get refreshing => _readCoordinator.refreshing;

  @override
  Future<MediaFlowCatalog> load() => _readCoordinator.load();

  @override
  Future<MediaFlowCatalog> reload() => _readCoordinator.reload();


  /// Fetches the complete cloud payload for a future explicit, reviewed save.
  /// Never returns the lossy catalog as a write payload.
  Future<NativeCloudStateSnapshot> loadFullStateSnapshot() async {
    if (_closed || _ownerId == null ||
        client.auth.currentUser?.id != _ownerId) {
      throw StateError('Signed-in account changed. Cloud read blocked.');
    }
    final row = await client.from('mediaflow_states')
        .select('state_data,updated_at')
        .eq('user_id', _ownerId)
        .maybeSingle();
    if (_closed || client.auth.currentUser?.id != _ownerId) {
      throw StateError('Signed-in account changed while loading full state.');
    }
    if (row == null || row['state_data'] == null ||
        row['updated_at'] == null) {
      throw const FormatException('A complete existing cloud row is required');
    }
    // Parse strictly now, before the snapshot can be used as a save anchor.
    MediaFlowFullState.parse(row['state_data']);
    return NativeCloudStateSnapshot(
      ownerId: _ownerId!,
      stateData: row['state_data'],
      updatedAt: row['updated_at'].toString(),
    );
  }

  /// Explicit CAS save entry point. Callers must supply a complete payload
  /// derived from loadFullStateSnapshot, never a rebuilt MediaFlowCatalog.
  Future<NativeCloudCommitResult> commitFullState({
    required NativeCloudStateSnapshot base,
    required Object nextStateData,
  }) {
    if (_closed || _ownerId == null || base.ownerId != _ownerId ||
        client.auth.currentUser?.id != _ownerId) {
      throw StateError('Signed-in account changed. Cloud write blocked.');
    }
    return NativeCloudStateCommitter(
      client: client,
      ownerId: _ownerId!,
    ).commit(
      expectedStateData: base.stateData,
      expectedUpdatedAt: base.updatedAt,
      nextStateData: nextStateData,
    );
  }

  Future<MediaFlowCatalog> _readCloud() async {
    if (_closed || _ownerId == null ||
        client.auth.currentUser?.id != _ownerId) {
      throw StateError('Signed-in account changed.');
    }
    // Owner-scoped SELECT and existing RLS. No insert/upsert/update/RPC.
    final row = await client.from('mediaflow_states')
        .select('state_data,updated_at')
        .eq('user_id', _ownerId)
        .maybeSingle();
    if (row == null || row['state_data'] == null) {
      throw const NativeMissingCloudRow();
    }
    final MediaFlowCatalog decoded;
    try {
      decoded = await decodeMediaFlowStateAsync(row['state_data']);
    } catch (_) {
      // Isolate parsing may wrap FormatException in a RemoteError.
      // Malformed authenticated cloud rows must NEVER be masked by cache.
      throw const FormatException('Invalid MediaFlow cloud state');
    }
    final catalog = MediaFlowCatalog(
      categories: decoded.categories,
      library: decoded.library,
      sessions: decoded.sessions,
      collections: decoded.collections,
      personalOrderIds: decoded.personalOrderIds,
      collectionAssignments: decoded.collectionAssignments,
      categoryQueues: decoded.categoryQueues,
      prioritizePersonalOrder: decoded.prioritizePersonalOrder,
      currentTask: decoded.currentTask,
      sessionActive: decoded.sessionActive,
      tasksPerDay: decoded.tasksPerDay,
      dailyMinutes: decoded.dailyMinutes,
      xpEvidence: decoded.xpEvidence,
      updatedAt: DateTime.tryParse((row['updated_at'] ?? '').toString()),
    );
    final revision = (row['updated_at'] ?? '').toString();
    if (revision.isNotEmpty && row['state_data'] is Map) {
      final digest = await compute(_m32FullDigest,
          Map<String, dynamic>.from(row['state_data'] as Map));
      if (_closed || client.auth.currentUser?.id != _ownerId) {
        throw StateError('Signed-in account changed while anchoring');
      }
      _cloudAnchors[catalog] = NativePriorityCloudAnchor(
        ownerId: _ownerId, revision: revision, fullPayloadDigest: digest,
      );
    }
    return catalog;
  }

  /// Explicit Settings-only review actions. No cloud writes or uploads.
  Future<NativeReviewBatch?> loadPriorityReview() =>
      _priorityReview.pendingReview();

  Future<NativeReviewBatch> stagePriorityReview() {
    final workspace = _editingWorkspace;
    final catalog = workspace?.baseCatalog;
    final anchor = catalog == null ? null : _cloudAnchors[catalog];
    if (workspace == null || catalog == null || anchor == null ||
        !_readCoordinator.isCurrentCloudCatalog(catalog)) {
      throw StateError('Open and draft an online Library title first');
    }
    return _priorityReview.stage(
      workspace: workspace, catalog: catalog, anchor: anchor,
      isDisplayedAuthoritativeCloud:
          _readCoordinator.isCurrentCloudCatalog(catalog),
    );
  }

  Future<NativeReviewDecision> inspectPriorityReview() =>
      _priorityReview.inspectPending();

  Future<void> discardPriorityReview() =>
      _priorityReview.discardPending();

  Future<NativeCloudRow> _readFreshForPriorityReview() async {
    if (_closed || _ownerId == null ||
        client.auth.currentUser?.id != _ownerId) {
      throw StateError('Signed-in account changed');
    }
    // ONLY authenticated RLS-bound SELECT, never an RPC or mutation.
    final result = await client.from('mediaflow_states')
        .select('state_data,updated_at')
        .eq('user_id', _ownerId)
        .maybeSingle();
    if (_closed || client.auth.currentUser?.id != _ownerId) {
      throw StateError('Signed-in account changed while fetching');
    }
    if (result == null || result['state_data'] is! Map ||
        result['updated_at'] == null ||
        result['updated_at'].toString().isEmpty) {
      throw const FormatException('Complete cloud row required');
    }
    return NativeCloudRow(
      ownerId: _ownerId,
      updatedAt: result['updated_at'].toString(),
      stateData: Map<String, dynamic>.from(result['state_data'] as Map),
    );
  }

  /// M33 offline *device-only* queue; no automated cloud replay.
  Future<NativeM33OfflineDraftQueue?> loadOfflineDraftQueue() =>
      _m33.load();

  Future<NativeM33OfflineDraftQueue> keepOfflinePriorityDrafts() {
    final workspace = _editingWorkspace;
    final catalog = workspace?.baseCatalog;
    if (workspace == null || catalog == null) {
      throw StateError('Draft a Library title priority first');
    }
    final sourceStatus = source.value;
    final anchored = _readCoordinator.isCurrentCloudCatalog(catalog);
    if ((sourceStatus == NativeSnapshotSource.cloud ||
         sourceStatus == NativeSnapshotSource.cloudNotCached) && !anchored) {
      throw StateError('The cloud Library has changed; review again');
    }
    return _m33.keep(
      workspace: workspace, catalog: catalog, source: sourceStatus,
      liveCloudAnchor: anchored ? _cloudAnchors[catalog] : null,
    );
  }

  Future<NativeM33CheckResult> inspectOfflineDraftQueue() => _m33.inspect();
  Future<void> discardOfflineDraftQueue() => _m33.discard();

  /// M34: manual per-title conflict comparison and LOCAL choices only.
  Future<NativeM34ReviewReport?> reviewOfflineDraftConflicts() =>
      _m33.inspectDetailed();

  Future<NativeM33OfflineDraftQueue?> resolveOfflineDraftConflicts({
    required NativeM34ReviewReport reviewed,
    required Set<String> discardOperationIds,
    required Set<String> recreateOperationIds,
  }) => _m33.resolveDetailed(
    reviewed: reviewed,
    discardOperationIds: discardOperationIds,
    recreateOperationIds: recreateOperationIds,
  );

  Future<void> clearOfflineCache() => _readCoordinator.clearDeviceCopy();

  /// Called before signing out. Revokes in-flight network reads, cached
  /// memory, encrypted snapshot generations and pending-review encryption keys.
  Future<void> prepareSignOut() async {
    _closed = true;
    _editingWorkspace?.discardAll();
    Object? failure;
    try {
      await _readCoordinator.closeAndPurge();
    } catch (error) {
      failure = error;
    }
    try {
      if (_ownerId != null) await _pendingReviews.clear(_ownerId);
    } catch (error) {
      failure ??= error;
    }
    try {
      if (_ownerId != null) await _offlineDraftStore.clear(_ownerId);
    } catch (error) {
      failure ??= error;
    }
    if (failure != null) {
      throw StateError('Could not completely clear local account data');
    }
  }

  void dispose() {
    _closed = true;
    _editingWorkspace?.dispose();
    _readCoordinator.dispose();
  }
}
