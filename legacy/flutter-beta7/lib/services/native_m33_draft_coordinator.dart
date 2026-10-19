import '../data/mediaflow_models.dart';
import 'native_cas_protocol.dart';
import 'native_editing_workspace.dart';
import 'native_m33_offline_queue.dart';
import 'native_m34_conflict_review.dart';
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
    this.replaceStored,
  });

  final String ownerId;
  final bool Function() isOwnerCurrent;
  final Future<NativeM33OfflineDraftQueue?> Function(String owner) readStored;
  final Future<void> Function(String owner, NativeM33OfflineDraftQueue queue)
      writeStored;
  final Future<void> Function(String owner) deleteStored;
  /// Optional gated local rewrite for M34; no network or remote mutation.
  final Future<void> Function(String owner, NativeM33OfflineDraftQueue queue,
      String expectedQueueId)? replaceStored;
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

  /// M34 user-triggered inspection. All titles are classified separately,
  /// even when one title has a conflict. No full cloud state is persisted.
  Future<NativeM34ReviewReport?> inspectDetailed() => _run(() async {
    final queue = await readStored(ownerId);
    _assertOwner();
    if (queue == null) return null;
    final NativeCloudRow cloud;
    try {
      cloud = await fetchFreshCloudRow();
    } catch (_) {
      _assertOwner();
      return NativeM34ReviewEngine.unavailable(
        queue: queue, signedInOwnerId: ownerId,
      );
    }
    _assertOwner();
    return NativeM34ReviewEngine.inspect(
      queue: queue, current: cloud, signedInOwnerId: ownerId,
    );
  });

  /// M34 manual local-only resolution. Discard never needs network access.
  /// Recreate needs a new authenticated full cloud read identical to the
  /// reviewed cloud; it ALWAYS generates a *new* inert device operation,
  /// with a new original value, ID and creation time, never replaying old ID.
  ///
  /// Retained old operations + recreated operations use an *unanchored* queue
  /// because one shared cloud digest cannot describe two different baselines.
  Future<NativeM33OfflineDraftQueue?> resolveDetailed({
    required NativeM34ReviewReport reviewed,
    required Set<String> discardOperationIds,
    required Set<String> recreateOperationIds,
  }) => _run(() async {
    if (reviewed.ownerId != ownerId ||
        discardOperationIds.intersection(recreateOperationIds).isNotEmpty ||
        (discardOperationIds.isEmpty && recreateOperationIds.isEmpty)) {
      throw StateError('Invalid manual conflict selections');
    }
    final queue = await readStored(ownerId);
    _assertOwner();
    if (queue == null || queue.queueId != reviewed.queueId ||
        NativeM34ReviewEngine.queueDigest(queue) != reviewed.queueDigest) {
      throw StateError('Device drafts changed; inspect again');
    }
    final known = queue.entries.map((e) => e.operationId).toSet();
    final chosen = {...discardOperationIds, ...recreateOperationIds};
    if (!known.containsAll(chosen)) {
      throw StateError('Selection refers to an unknown operation');
    }
    NativeCloudRow? cloud;
    if (recreateOperationIds.isNotEmpty) {
      if (!reviewed.hasFreshCloud || replaceStored == null) {
        throw StateError('A fresh online cloud review is required');
      }
      cloud = await fetchFreshCloudRow();
      _assertOwner();
      if (cloud.ownerId != ownerId ||
          cloud.updatedAt != reviewed.cloudUpdatedAt ||
          NativeM34ReviewEngine.cloudDigest(cloud) != reviewed.cloudDigest) {
        throw StateError('Cloud changed after review; inspect again');
      }
    }
    final now = DateTime.now().toUtc();
    final entries = <NativeM33PriorityDraft>[];
    var retained = 0;
    for (final old in queue.entries) {
      if (discardOperationIds.contains(old.operationId)) continue;
      if (!recreateOperationIds.contains(old.operationId)) {
        entries.add(old);
        retained++;
        continue;
      }
      final evaluated = reviewed.byOperation(old.operationId);
      if (evaluated == null || !evaluated.mayRecreate ||
          evaluated.cloudPriority == null ||
          evaluated.cloudPriority == old.afterPriority) {
        throw StateError('This title cannot be safely recreated');
      }
      entries.add(NativeM33PriorityDraft(
        operationId: NativeM33OfflineDraftQueue.freshId(),
        titleId: old.titleId,
        beforePriority: evaluated.cloudPriority!,
        afterPriority: old.afterPriority,
        createdAt: now,
      ));
    }
    _assertOwner();
    if (entries.isEmpty) {
      await deleteStored(ownerId);
      _assertOwner();
      return null;
    }
    if (replaceStored == null) {
      throw StateError('Encrypted local replacement is unavailable');
    }
    final mixed = recreateOperationIds.isNotEmpty && retained != 0;
    final source = recreateOperationIds.isEmpty
        ? queue.source : mixed ? 'mixedManual' : 'cloud';
    final next = NativeM33OfflineDraftQueue(
      ownerId: ownerId, queueId: NativeM33OfflineDraftQueue.freshId(),
      source: source, createdAt: now,
      entries: entries,
      fullCloudDigest: recreateOperationIds.isEmpty
          ? queue.fullCloudDigest : mixed ? null : reviewed.cloudDigest,
      cloudUpdatedAt: recreateOperationIds.isEmpty
          ? queue.cloudUpdatedAt : mixed ? null : reviewed.cloudUpdatedAt,
    );
    _assertOwner();
    await replaceStored!(ownerId, next, queue.queueId);
    _assertOwner();
    return next;
  });

  Future<void> discard() => _run(() async {
    await deleteStored(ownerId);
    _assertOwner();
  });
}
