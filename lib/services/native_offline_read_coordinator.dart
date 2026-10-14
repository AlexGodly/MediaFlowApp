import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/mediaflow_models.dart';
import 'native_offline_snapshot_store.dart';

/// Read-only cloud/device presentation state. Nothing in this enum grants
/// account edit permissions or indicates a server-verified write revision.
enum NativeSnapshotSource {
  idle, checkingCloud, cloud, cloudNotCached, offline, recoveredPrevious,
  offlineMemory, invalidCloud, unavailable,
}

/// A cloud row can be missing or malformed without any network failure.
/// Never silently replace this with an older device copy (which could hide
/// an account/backup problem) or create a new empty account.
class NativeMissingCloudRow implements Exception {
  const NativeMissingCloudRow();
}

/// Authenticated, single-owner read-only offline-first coordinator.
///
/// Cloud is the only authoritative source. A verified encrypted, owner-scoped
/// device cache is displayed only when the cloud request failed transiently.
/// An in-memory fallback is available if encryption/cache storage failed and
/// a previously authenticated snapshot already exists in this session.
///
/// There are NO listeners to device connectivity, timers, background sync,
/// offline editing, automatic retries, or any Supabase write operations.
/// Reconnection happens solely through explicit reload().
class NativeOfflineReadCoordinator {
  NativeOfflineReadCoordinator({
    required this.ownerId,
    required this.isOwnerCurrent,
    required this.readCloud,
    required this.readDeviceCopy,
    required this.writeDeviceCopy,
    required this.clearDeviceCopyStorage,
  });

  final String? ownerId;
  final bool Function() isOwnerCurrent;
  final Future<MediaFlowCatalog> Function() readCloud;
  final Future<NativeCachedSnapshot?> Function(String owner) readDeviceCopy;
  final Future<void> Function(String owner, MediaFlowCatalog snapshot)
      writeDeviceCopy;
  final Future<void> Function(String owner) clearDeviceCopyStorage;

  final ValueNotifier<NativeSnapshotSource> source =
      ValueNotifier(NativeSnapshotSource.idle);
  final ValueNotifier<DateTime?> offlineSavedAt = ValueNotifier(null);
  final ValueNotifier<bool> refreshing = ValueNotifier(false);
  MediaFlowCatalog? _lastReadable;
  Future<MediaFlowCatalog>? _cached;
  int _requestId = 0;
  int _cacheEpoch = 0;
  bool _closed = false;

  bool _isCurrent(int id) => !_closed && id == _requestId &&
      ownerId != null && ownerId!.isNotEmpty && isOwnerCurrent();

  Future<MediaFlowCatalog> load() => _cached ??= _issue();

  Future<MediaFlowCatalog> _issue() {
    final future = _request();
    // A failed request must not become a permanently cached failure.
    future.then<void>((_) {}, onError: (Object _, StackTrace __) {
      if (identical(_cached, future)) _cached = null;
    });
    return future;
  }

  /// Explicit refresh from Settings or a view's Refresh button.
  /// Existing offline status stays visible while a reconnect is attempted.
  Future<MediaFlowCatalog> reload() {
    final next = _issue();
    _cached = next;
    return next;
  }

  Future<MediaFlowCatalog> _request() async {
    final id = ++_requestId;
    if (!_isCurrent(id)) {
      throw StateError('A matching signed-in account is required');
    }
    refreshing.value = true;
    if (source.value == NativeSnapshotSource.idle ||
        source.value == NativeSnapshotSource.unavailable ||
        source.value == NativeSnapshotSource.invalidCloud) {
      source.value = NativeSnapshotSource.checkingCloud;
    }
    try {
      final cloud = await readCloud();
      _check(id);
      _lastReadable = cloud;
      offlineSavedAt.value = null;
      source.value = NativeSnapshotSource.cloud;
      unawaited(_persist(id, _cacheEpoch, cloud));
      return cloud;
    } on NativeMissingCloudRow {
      _check(id);
      _lastReadable = null;
      offlineSavedAt.value = null;
      source.value = NativeSnapshotSource.invalidCloud;
      rethrow;
    } on FormatException {
      _check(id);
      _lastReadable = null;
      offlineSavedAt.value = null;
      source.value = NativeSnapshotSource.invalidCloud;
      rethrow;
    } catch (_) {
      _check(id);
      NativeCachedSnapshot? device;
      try {
        device = await readDeviceCopy(ownerId!);
      } catch (_) {
        // Corrupt ciphertext/keys or locked secure storage are not accepted.
      }
      _check(id);
      if (device != null) {
        _lastReadable = device.catalog;
        offlineSavedAt.value = device.savedAt;
        source.value = device.recoveredPrevious
            ? NativeSnapshotSource.recoveredPrevious
            : NativeSnapshotSource.offline;
        return device.catalog;
      }
      if (_lastReadable != null) {
        offlineSavedAt.value = null;
        source.value = NativeSnapshotSource.offlineMemory;
        return _lastReadable!;
      }
      offlineSavedAt.value = null;
      source.value = NativeSnapshotSource.unavailable;
      rethrow;
    } finally {
      if (_isCurrent(id)) refreshing.value = false;
    }
  }

  void _check(int id) {
    if (!_isCurrent(id)) {
      throw StateError('Discarded stale read after refresh or account change');
    }
  }

  Future<void> _persist(
      int id, int epoch, MediaFlowCatalog catalog) async {
    if (!_isCurrent(id) || epoch != _cacheEpoch) return;
    try {
      await writeDeviceCopy(ownerId!, catalog);
    } catch (_) {
      if (_isCurrent(id) && epoch == _cacheEpoch &&
          source.value == NativeSnapshotSource.cloud) {
        source.value = NativeSnapshotSource.cloudNotCached;
      }
    }
  }

  /// Clear is serialized after any in-flight write by the encrypted store.
  /// The currently open read-only view is not removed from RAM; no next
  /// background cache write from the old refresh may be scheduled.
  Future<void> clearDeviceCopy() async {
    final owner = ownerId;
    if (_closed || owner == null || !isOwnerCurrent()) {
      throw StateError('Signed-in owner required to clear device copy');
    }
    ++_cacheEpoch;
    await clearDeviceCopyStorage(owner);
  }

  /// Invalidates all pending reads, then wipes this account's encrypted
  /// cached snapshots and keys; caller also clears pending encrypted reviews.
  Future<void> closeAndPurge() async {
    _closed = true;
    ++_requestId;
    ++_cacheEpoch;
    _cached = null;
    _lastReadable = null;
    if (source.value != NativeSnapshotSource.idle) {
      source.value = NativeSnapshotSource.idle;
    }
    refreshing.value = false;
    offlineSavedAt.value = null;
    if (ownerId != null && ownerId!.isNotEmpty) {
      await clearDeviceCopyStorage(ownerId!);
    }
  }

  void dispose() {
    _closed = true;
    ++_requestId;
    _cached = null;
    _lastReadable = null;
    source.dispose();
    refreshing.dispose();
    offlineSavedAt.dispose();
  }
}
