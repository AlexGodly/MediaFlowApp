import '../data/mediaflow_models.dart';
import 'native_cas_protocol.dart';
import 'native_m30_shared_sync.dart';
import 'native_m53_task_completion_evidence.dart';

/// Source: MediaFlow v410 tag 410, logging/008-session-flow.js submitLog,
/// v287 Personal Order Collection queue submitLog wrapper and v348 XP hooks.
/// An audit is NOT a transaction proposal, receipt, or authorization to write.
enum NativeM54AuditStatus {
  invalidContext, noConsumption, categoryMismatch, evidenceOnly,
}

enum NativeM54Prerequisite {
  ownerAndSnapshot,
  completeDraft,
  targetMid,
  categoryGroupedHistory,
  runtimeAndItemizedTimestamps,
  experienceAndRespect,
  libraryAndCompletionTimeline,
  collectionTraversal,
  nextTaskGeneration,
  atomicAccountCommit,
}

class NativeM54Requirement {
  const NativeM54Requirement({
    required this.id, required this.name, required this.finding,
    required this.reference, required this.satisfied,
  });
  final NativeM54Prerequisite id;
  final String name, finding, reference;
  /// Means the read-only evidence supports THIS prerequisite, not writes.
  final bool satisfied;
}

/// Immutable, intentionally incomplete review of a v410 log transaction.
/// Missing effects are explicit blockers; no write intent is constructed.
class NativeM54TransactionAudit {
  const NativeM54TransactionAudit._({
    required this.status, required this.checks,
    required this.assignedCategoryId, required this.actualCategoryId,
    required this.indicativeQuantity, required this.mightSkipRecommendation,
    required this.collectionSourceFinding,
  });

  final NativeM54AuditStatus status;
  final List<NativeM54Requirement> checks;
  final String assignedCategoryId, actualCategoryId;
  final double? indicativeQuantity;
  /// In an isolated single-title scenario the web writes an extra skipped
  /// recommendation row if no positive consumption matches assigned category.
  /// This is not a prediction about an entire multi-title logging group.
  final bool mightSkipRecommendation;
  final String collectionSourceFinding;

  bool get canCommit => false;
  bool get confirmedTaskCompleted => false;
  bool get readyForProduction => false;
  int get blockedCount => checks.where((c) => !c.satisfied).length;
  int get verifiedReadOnlyCount => checks.length - blockedCount;

  String get statusLabel => switch (status) {
    NativeM54AuditStatus.invalidContext => 'Invalid or stale task context',
    NativeM54AuditStatus.noConsumption => 'No valid draft consumption',
    NativeM54AuditStatus.categoryMismatch =>
      'Consumption belongs to another category',
    NativeM54AuditStatus.evidenceOnly => 'Read-only draft evidence available',
  };

  static NativeM54TransactionAudit inspect({
    required MediaFlowCatalog catalog,
    required String titleId,
    required NativeM53TaskCompletionEvidence evidence,
  }) {
    final task = catalog.sessionActive ? catalog.currentTask : null;
    final validContext = evidence.status !=
        NativeM53EvidenceStatus.invalidContext &&
        task != null && task.libraryId == titleId && titleId.isNotEmpty;
    MediaFlowTitle? title;
    var ambiguousTitle = false;
    if (validContext) {
      for (final item in catalog.library) {
        if (item.id != titleId) continue;
        if (title != null) {
          ambiguousTitle = true; // Exact ID must be unique.
          break;
        }
        title = item;
      }
    }
    final usableContext = validContext && title != null && !ambiguousTitle;
    final usableConsumption = usableContext &&
        (evidence.comparable ||
         evidence.status == NativeM53EvidenceStatus.differentCategory) &&
        evidence.amount.isFinite && evidence.amount > 0;
    final foreignCategory = usableConsumption &&
        title!.categoryId != task!.categoryId;
    final status = !usableContext
        ? NativeM54AuditStatus.invalidContext
        : !usableConsumption
            ? NativeM54AuditStatus.noConsumption
            : foreignCategory
                ? NativeM54AuditStatus.categoryMismatch
                : NativeM54AuditStatus.evidenceOnly;
    final assignedId = usableContext ? task!.categoryId : '';
    final actualId = usableContext ? title!.categoryId : '';
    final mightSkip = foreignCategory;
    final order = usableContext ? task!.orderSource : null;
    String traversal;
    if (order == null) {
      traversal = 'No trusted Collection source transaction is available. '
          'The source may be absent or may be a direct title.';
    } else if (order.type != 'collection') {
      traversal = order.type == 'title'
          ? 'Saved source claims a direct title; no Collection traversal '
              'should be inferred.'
          : 'Unrecognized saved source type; traversal cannot be inferred.';
    } else {
      final matchingAssignments = catalog.collectionAssignments.where(
          (a) => a.id == order.assignmentId &&
                 a.categoryId == order.categoryId).toList();
      final assignment = matchingAssignments.length == 1
          ? matchingAssignments.single : null;
      final matchingCollections = assignment == null
          ? const <MediaFlowCollection>[]
          : catalog.collections.where(
              (c) => c.id == assignment.collectionId).toList();
      if (order.libraryId != titleId ||
          order.categoryId != assignedId ||
          order.assignmentId.isEmpty ||
          assignment == null ||
          matchingCollections.length != 1 ||
          !matchingCollections.single.titleIds.contains(titleId)) {
        traversal = 'Collection source is missing, ambiguous, or no longer '
            'matches this assignment, title, and Collection membership.';
      } else if (assignment.traversedTitleIds.contains(titleId)) {
        traversal = 'Title is already traversed. Do not stage traversal twice.';
      } else {
        traversal = 'Unique saved Collection membership is present; '
            'actual successful consumption, rollback and atomic persistence '
            'remain unverified.';
      }
    }
    const web = 'MediaFlow v410 website tag 410';
    final checks = <NativeM54Requirement>[
      NativeM54Requirement(
        id: NativeM54Prerequisite.ownerAndSnapshot,
        name: 'Owner, exact ID and snapshot',
        satisfied: usableContext,
        finding: usableContext
            ? 'M51–M53 owner/snapshot-pinned task is valid for display only.'
            : 'Owner, snapshot, active task or unique title is invalid.',
        reference: 'Native M51/M52/M53 context'),
      NativeM54Requirement(
        id: NativeM54Prerequisite.completeDraft,
        name: 'Complete consumption draft',
        satisfied: false,
        finding: !usableConsumption
            ? 'No valid local consumption can be used for analysis.'
            : foreignCategory
                ? 'Single-title draft belongs to the actual Library category; '
                    'assigned recommendation may be skipped.'
                : 'Single-title quantity is known, but the complete multi-title '
                    'Logging group, timestamps and updateLibrary choice are not.',
        reference: web + ' submitLog entries grouping'),
      const NativeM54Requirement(
        id: NativeM54Prerequisite.targetMid,
        name: 'Authoritative completion threshold',
        satisfied: false,
        finding: 'v410 uses currentTask.targetMid, not the native low/high '
            'display range. targetMid is not retained as verified native '
            'transaction state. No complete/partial/over outcome is proven.',
        reference: 'v410 logging/008-session-flow.js · targetMid'),
      const NativeM54Requirement(
        id: NativeM54Prerequisite.categoryGroupedHistory,
        name: 'History rows and skipped recommendation',
        satisfied: false,
        finding: 'History writes one row per actual category plus an assigned '
            'skipped row when none was consumed. Distinct row IDs, logical '
            'sessionGroupId and accurate per-title membership are required.',
        reference: 'v410 logging/008-session-flow.js · S.sessions.push'),
      const NativeM54Requirement(
        id: NativeM54Prerequisite.runtimeAndItemizedTimestamps,
        name: 'Runtime and Advanced Logging timestamps',
        satisfied: false,
        finding: 'Weighted group minutes, v369 unit seconds, individual '
            'loggedAt, repeat units and Library progress projections must '
            'match the real submission, not only editor previews.',
        reference: 'v410 logging/008-session-flow.js · v369'),
      const NativeM54Requirement(
        id: NativeM54Prerequisite.experienceAndRespect,
        name: 'Consumption XP, streak and System Respect',
        satisfied: false,
        finding: 'Source-dependent health, consumption XP, streak bonuses, '
            'v165 one-time Respect and v348 ledger side effects lack '
            'a complete native transaction contract.',
        reference: 'v410 submitLog · v165 · v348 XP hooks'),
      NativeM54Requirement(
        id: NativeM54Prerequisite.libraryAndCompletionTimeline,
        name: 'Library and completion timeline',
        satisfied: false,
        finding: evidence.repeat
            ? 'Repeat units count as consumption without advancing Library '
                'progress; History and XP still need a single atomic save.'
            : 'updateLibrary may change progress, seasons, completedAt, '
                'status and completionTimeline once. A preview is not a save.',
        reference: 'v410 logging/008-session-flow.js · updateLibrary'),
      NativeM54Requirement(
        id: NativeM54Prerequisite.collectionTraversal,
        name: 'Personal Order Collection traversal',
        satisfied: false, finding: traversal,
        reference: 'v410 221-v287-personal-order-collection-queues.js'),
      const NativeM54Requirement(
        id: NativeM54Prerequisite.nextTaskGeneration,
        name: 'Generate and persist the next task',
        satisfied: false,
        finding: 'Successful logging feeds consumed category IDs into '
            'generateTask, respecting mixed queues, rerolls, source metadata '
            'and configured recommendations. Local queue previews cannot '
            'reproduce the authoritative result.',
        reference: 'v410 submitLog · generateTask · v287 wrapper'),
      NativeM54Requirement(
        id: NativeM54Prerequisite.atomicAccountCommit,
        name: 'Atomic, idempotent cross-device synchronization',
        satisfied: false,
        finding: !NativeCloudCapabilities.cloudWritesEnabled &&
                !NativeCloudCapabilities.hasServerSideCas &&
                !NativeM30Protocol.deployed
            ? 'Native writes disabled; shared revisioned CAS is not deployed. '
                'All website writers must migrate, with server-side owner RLS, '
                'operation receipts, conflict handling and atomic multi-root '
                'side effects before any production task transaction.'
            : 'A verified account-wide server transaction, legacy-writer '
                'cutover and idempotent receipts are mandatory; an audit '
                'never authorizes production writes.',
        reference: 'Native M9/M30 shared synchronization safety'),
    ];
    return NativeM54TransactionAudit._(
      status: status,
      checks: List.unmodifiable(checks),
      assignedCategoryId: assignedId,
      actualCategoryId: actualId,
      indicativeQuantity: usableConsumption ? evidence.amount : null,
      mightSkipRecommendation: mightSkip,
      collectionSourceFinding: traversal,
    );
  }
}
