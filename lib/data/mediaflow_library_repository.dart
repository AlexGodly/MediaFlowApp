import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/native_offline_snapshot_store.dart';
import 'mediaflow_models.dart';
import 'mediaflow_state_codec.dart';

abstract class MediaFlowLibraryRepository {
  Future<MediaFlowCatalog> load();

  /// Default fallback for test repositories. Production overrides to bypass cache.
  Future<MediaFlowCatalog> reload() => load();
}

enum NativeSnapshotSource {
  idle, checkingCloud, cloud, cloudNotCached, offline, recoveredPrevious,
  unavailable,
}

/// All native pages share the same owner-scoped read-only cloud snapshot.
/// On failed cloud reads, a verified local projection can be displayed with an
/// explicit offline status; local content is never treated as a cloud revision
/// for edits or transmitted back to the server.
class SupabaseMediaFlowLibraryRepository extends MediaFlowLibraryRepository {
  SupabaseMediaFlowLibraryRepository(
    this.client, {
    NativeOfflineSnapshotStore? offlineStore,
  }) : _offlineStore = offlineStore ?? NativeOfflineSnapshotStore(),
       _ownerId = client.auth.currentUser?.id;

  final SupabaseClient client;
  final NativeOfflineSnapshotStore _offlineStore;
  final String? _ownerId;
  final ValueNotifier<NativeSnapshotSource> source =
      ValueNotifier(NativeSnapshotSource.idle);

  Future<MediaFlowCatalog>? _cached;
  int _requestId = 0;
  bool _closed = false;

  bool _isCurrent(int id) =>
      !_closed && id == _requestId &&
      _ownerId != null && client.auth.currentUser?.id == _ownerId;

  @override
  Future<MediaFlowCatalog> load() {
    if (_cached != null) return _cached!;
    final id = ++_requestId;
    return _cached = _guardedFetch(id);
  }

  @override
  Future<MediaFlowCatalog> reload() {
    final id = ++_requestId;
    return _cached = _guardedFetch(id);
  }

  Future<MediaFlowCatalog> _guardedFetch(int id) async {
    try {
      return await _fetch(id);
    } catch (_) {
      // Network/auth failures are retryable, rather than permanently cached.
      if (id == _requestId) _cached = null;
      rethrow;
    }
  }

  Future<MediaFlowCatalog> _fetch(int id) async {
    if (!_isCurrent(id)) {
      throw StateError('A signed-in matching account is required.');
    }
    source.value = NativeSnapshotSource.checkingCloud;
    try {
      // Owner predicate AND the database's existing authenticated RLS policy.
      // No write, UPSERT, RPC or background synchronization is possible here.
      final row = await client
          .from('mediaflow_states')
          .select('state_data,updated_at')
          .eq('user_id', _ownerId!)
          .maybeSingle();
      if (!_isCurrent(id)) throw StateError('Signed-in account changed.');
      if (row == null || row['state_data'] == null) {
        throw StateError('Cloud snapshot is unavailable.');
      }

      final decoded = await decodeMediaFlowStateAsync(row['state_data']);
      if (!_isCurrent(id)) throw StateError('Signed-in account changed.');
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
        updatedAt: DateTime.tryParse((row['updated_at'] ?? '').toString()),
      );
      source.value = NativeSnapshotSource.cloud;
      // Disk serialization runs on an isolate; the cloud view is not delayed.
      unawaited(_saveVerifiedProjection(id, catalog));
      return catalog;
    } catch (_) {
      if (!_isCurrent(id)) rethrow;
      final cached = await _offlineStore.load(_ownerId!);
      if (!_isCurrent(id)) {
        throw StateError('Signed-in account changed during recovery.');
      }
      if (cached != null) {
        source.value = cached.recoveredPrevious
            ? NativeSnapshotSource.recoveredPrevious
            : NativeSnapshotSource.offline;
        return cached.catalog;
      }
      source.value = NativeSnapshotSource.unavailable;
      rethrow;
    }
  }

  Future<void> _saveVerifiedProjection(int id, MediaFlowCatalog catalog) async {
    if (!_isCurrent(id)) return;
    try {
      await _offlineStore.save(_ownerId!, catalog);
    } catch (_) {
      if (_isCurrent(id) && source.value == NativeSnapshotSource.cloud) {
        source.value = NativeSnapshotSource.cloudNotCached;
      }
    }
  }

  /// Purges the account's local copies. The in-memory view is unaffected.
  Future<void> clearOfflineCache() async {
    final owner = _ownerId;
    if (owner == null) return;
    await _offlineStore.clear(owner);
  }

  /// Called before signing out so an in-flight fetch cannot repopulate disk.
  Future<void> prepareSignOut() async {
    ++_requestId;
    _cached = null;
    await clearOfflineCache();
  }

  void dispose() {
    _closed = true;
    ++_requestId;
    source.dispose();
  }
}
