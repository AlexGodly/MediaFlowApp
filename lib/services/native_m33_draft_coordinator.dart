import '../data/mediaflow_models.dart';
import 'native_cas_protocol.dart';
import 'native_editing_workspace.dart';
import 'native_m33_offline_queue.dart';
import 'native_priority_review_coordinator.dart';
import 'native_offline_read_coordinator.dart';

/// Explicit, user-operated OFFLINE draft and manual cloud comparison.
/// The encrypted storage is not an automatically replayed upload queue.
/// Even with a fresh cloud comparison, mayUpload is always false.
class NativeM33DraftCoordinator {
  NativeM33DraftCoordinator({
    required this.ownerId,
    required this.isOwnerCurrent,
    required this.readStored,
    required this.writeStored,
    required this.deleteStored,
    required this.fetchFreshCloudRow,
  });

  final String ownerId;
  final bool Function() isOwnerCurrent;
  final Future<NativeM33OfflineDraftQueue?> Function(String owner) readStored;
  final Future<void> Function(String owner, NativeM33OfflineDraftQueue queue)
      writeStored;
  final Future<void> Function(String owner) deleteStored;
  final Future<NativeCloudRow> Function() fetchFreshCloudRow;
  bool _busy = false;
  bool get busy => _busy;

  void _assertOwner() {
    if (ownerId.isEmpty || !isOwnerCurrent()) {
      throw StateError('Signed-in account changed');
    }
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    _assertOwner();
    if (_busy) throw StateError('Another offline draft operation is running');
    _busy = true;
    try {
      final response = await action();
      _assertOwner();
      return response;
    } finally {
      _busy = false;
    }
  }

  Future<NativeM33OfflineDraftQueue?> load() => _run(() async {
    final queue = await readStored(ownerId);
    _assertOwner();
    if (queue != null && queue.ownerId != ownerId) {
      throw StateError('Foreign owner in encrypted queue');
    }
    return queue;
  });

  /// Offline and recovered projections may produce *device-only* intents,
  /// with no cloud revision; they will never become an RPC request.
  Future<NativeM33OfflineDraftQueue> keep({
    required NativeEditingWorkspace workspace,
    required MediaFlowCatalog catalog,
    required NativeSnapshotSource source,
    NativePriorityCloudAnchor? liveCloudAnchor,
  }) => _run(() async {
    if (workspace.ownerId != ownerId || workspace.stale ||
        !identical(workspace.baseCatalog, catalog) ||
        workspace.titleDrafts.isEmpty ||
        workspace.logCount != 0 ||
        workspace.itemizedCount != 0 ||
        !const {
          NativeSnapshotSource.cloud, NativeSnapshotSource.cloudNotCached,
          NativeSnapshotSource.offline,
          NativeSnapshotSource.recoveredPrevious,
          NativeSnapshotSource.offlineMemory,
        }.contains(source)) {
      throw StateError('Valid account-scoped priority drafts are required');
    }
    final cloud = source == NativeSnapshotSource.cloud ||
        source == NativeSnapshotSource.cloudNotCached;
    if (cloud != (liveCloudAnchor != null) ||
        (cloud && (liveCloudAnchor!.ownerId != ownerId ||
            liveCloudAnchor.revision.isEmpty ||
            liveCloudAnchor.fullPayloadDigest.isEmpty))) {
      throw StateError('Cannot invent an authenticated cloud baseline');
    }

    if (await readStored(ownerId) != null) {
      throw StateError('Discard the saved offline draft queue first');
    }
    _assertOwner();
    final now = DateTime.now().toUtc();
    final entries = <NativeM33PriorityDraft>[];
    final ids = <String>{};
    for (final edit in workspace.titleDrafts) {
      final matched = catalog.library.where((t) => t.id == edit.titleId).toList();
      if (!ids.add(edit.titleId) || matched.length != 1 ||
          edit.statusSideEffectsUnverified) {
        throw StateError('Unsupported or ambiguous title draft');
      }
      final title = matched.single;
      if (title.title != edit.title || title.status != edit.status ||
          title.progress != edit.progress || title.rating != edit.rating ||
          title.priority == edit.priority) {
        throw StateError('Only source-consistent priority changes can be kept');
      }
      entries.add(NativeM33PriorityDraft(
        operationId: NativeM33OfflineDraftQueue.freshId(),
        titleId: title.id,
        beforePriority: title.priority,
        afterPriority: edit.priority,
        createdAt: now,
      ));
    }
    final queue = NativeM33OfflineDraftQueue(
      ownerId: ownerId,
      queueId: NativeM33OfflineDraftQueue.freshId(),
      source: cloud ? 'cloud' : source.name,
      createdAt: now, entries: entries,
      fullCloudDigest: liveCloudAnchor?.fullPayloadDigest,
      cloudUpdatedAt: liveCloudAnchor?.revision,
    );
    _assertOwner();
    await writeStored(ownerId, queue);
    _assertOwner();
    return queue;
  });

  /// A cloud connection is needed only for *manual review*, not offline save.
  /// No automatic retry, upload, rebase or conflict resolution takes place.
  Future<NativeM33CheckResult> inspect() => _run(() async {
    final queue = await readStored(ownerId);
    _assertOwner();
    if (queue == null) {
      return const NativeM33CheckResult(
        NativeM33CheckStatus.unavailable, 'No saved offline draft');
    }
    final NativeCloudRow current;
    try {
      current = await fetchFreshCloudRow();
    } catch (_) {
      _assertOwner();
      return const NativeM33CheckResult(
        NativeM33CheckStatus.unavailable,
        'Could not obtain fresh cloud data; the offline queue was not uploaded');
    }
    _assertOwner();
    return NativeM33ManualReview.inspect(
      queue: queue, current: current, signedInOwnerId: ownerId,
    );
  });

  Future<void> discard() => _run(() async {
    await deleteStored(ownerId);
    _assertOwner();
  });
}
