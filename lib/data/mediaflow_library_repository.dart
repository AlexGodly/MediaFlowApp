import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/native_offline_read_coordinator.dart';
import '../services/native_offline_snapshot_store.dart';
import '../services/native_pending_review_store.dart';
import '../services/native_editing_workspace.dart';
import '../services/native_priority_review_coordinator.dart';
import '../services/native_cas_protocol.dart';
import '../services/native_sync_review.dart';
import '../services/native_snapshot_codec.dart';
import 'mediaflow_models.dart';
import 'mediaflow_state_codec.dart';

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
  }) : _offlineStore = offlineStore ?? NativeOfflineSnapshotStore(),
       _pendingReviews = pendingReviewStore ?? NativePendingReviewStore(),
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
        ownerId: _ownerId!, revision: revision, fullPayloadDigest: digest,
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
