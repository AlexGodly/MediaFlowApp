import '../data/mediaflow_models.dart';
import 'native_m42_mixed_queue.dart';
import 'native_m43_recommendation_audit.dart';

enum NativeM48PriorityPolicy { enabled, disabled, unknown }

/// A queue-only, read-only snapshot of a possible task recommendation.
/// It is NOT a substitute for v410's task generator, reroll history, or
/// successful-logging transaction.
class NativeM48TaskPreview {
  const NativeM48TaskPreview({
    required this.categoryId,
    required this.policy,
    required this.currentTaskMatchesCategory,
    required this.sessionActive,
    required this.eligibleCount,
    required this.excludedCount,
    required this.candidates,
  });
  final String categoryId;
  final NativeM48PriorityPolicy policy;
  final bool currentTaskMatchesCategory, sessionActive;
  final int eligibleCount, excludedCount;
  final List<NativeM42QueueTitle> candidates;
  NativeM42QueueTitle? get first => candidates.firstOrNull;
  bool get canInferTaskSelection =>
      policy==NativeM48PriorityPolicy.enabled && first!=null;

  /// When disabled, absent, or exhausted the website uses other picker
  /// behavior that cannot be inferred from the Personal Order projection.
  bool get fallbackOrUnknown =>
      policy!=NativeM48PriorityPolicy.enabled || first==null;
}

class NativeM48TraversalPreview {
  const NativeM48TraversalPreview({
    required this.before,
    required this.after,
    required this.wouldAdvanceCollection,
    required this.assignmentId,
  });
  final NativeM48TaskPreview before, after;
  final bool wouldAdvanceCollection;
  final String assignmentId;
}

/// Pure v287 queue prioritization and v180 exclusion coordination.
/// A successful Log (quantity/progress validation and save) is essential
/// before the real website stages Collection traversal. Native app does not
/// know those outcomes, so this service ONLY models a hypothetical success.
class NativeM48TaskCoordination {
  NativeM48TaskCoordination(this.catalog)
      : audit=NativeM43RecommendationAudit(catalog);
  final MediaFlowCatalog catalog;
  final NativeM43RecommendationAudit audit;

  NativeM48PriorityPolicy get policy => switch(catalog.prioritizePersonalOrder) {
    true => NativeM48PriorityPolicy.enabled,
    false => NativeM48PriorityPolicy.disabled,
    null => NativeM48PriorityPolicy.unknown,
  };

  String get activeCategoryId =>
      catalog.sessionActive ? catalog.currentTask?.categoryId??'' : '';

  NativeM48TaskPreview preview(String categoryId,{
    Set<String> excludedIds=const {},
    int limit=5,
  }) {
    if(categoryId.isEmpty || !audit.queues.categoryIds.contains(categoryId)) {
      throw StateError('Unknown Personal Order category');
    }
    if(limit<1 || limit>20) {
      throw const FormatException('Preview must contain 1–20 candidates');
    }
    if(excludedIds.length>200) {
      throw const FormatException('At most 200 hypothetical exclusions');
    }
    final scoped=audit.forCategory(categoryId).recommendations;
    final selected=<NativeM42QueueTitle>[];
    var exclusionsApplied=0;
    for(final entry in scoped) {
      if(excludedIds.contains(entry.title.id)) {
        exclusionsApplied++;
        continue;
      }
      if(selected.length<limit) selected.add(entry);
    }
    return NativeM48TaskPreview(
      categoryId:categoryId,
      policy:policy,
      currentTaskMatchesCategory:activeCategoryId==categoryId,
      sessionActive:catalog.sessionActive,
      eligibleCount:scoped.length,
      excludedCount:exclusionsApplied,
      candidates:List.unmodifiable(selected),
    );
  }

  /// Preview the next *queue* candidate IF an eligible Collection title is
  /// actually consumed and successfully logged. No cloud, History, task,
  /// Library, Collection, or live traversal state is changed.
  NativeM48TraversalPreview afterSuccessfulCollectionConsumption(
      String categoryId,NativeM42QueueTitle candidate,{
      Set<String> excludedIds=const {},int limit=5}) {
    final before=preview(categoryId,excludedIds:excludedIds,limit:limit);
    final actual=audit.forCategory(categoryId).recommendations.any(
      (entry)=>entry.title.id==candidate.title.id &&
        entry.assignmentId==candidate.assignmentId &&
        entry.outerPosition==candidate.outerPosition &&
        entry.recommendationIndex==candidate.recommendationIndex &&
        entry.sourceType==candidate.sourceType);
    if(!actual || excludedIds.contains(candidate.title.id)) {
      throw StateError('Candidate is not eligible in this queue preview');
    }
    if(!candidate.fromCollection) {
      return NativeM48TraversalPreview(
        before:before,after:before,wouldAdvanceCollection:false,
        assignmentId:'');
    }
    final matching=catalog.collectionAssignments.where((a)=>
      a.id==candidate.assignmentId && a.categoryId==categoryId).toList();
    if(matching.length!=1 ||
        matching.single.traversedTitleIds.contains(candidate.title.id)) {
      throw StateError('Collection assignment cannot be advanced safely');
    }
    final original=matching.single;
    final changed=MediaFlowCollectionAssignment(
      id:original.id,collectionId:original.collectionId,
      categoryId:original.categoryId,categoryRule:original.categoryRule,
      completedRule:original.completedRule,createdAt:original.createdAt,
      traversedTitleIds:List.unmodifiable([
        ...original.traversedTitleIds,candidate.title.id,
      ]),
    );
    final projected=MediaFlowCatalog(
      library:catalog.library,categories:catalog.categories,
      sessions:catalog.sessions,collections:catalog.collections,
      personalOrderIds:catalog.personalOrderIds,
      collectionAssignments:List.unmodifiable([
        for(final a in catalog.collectionAssignments)
          if(identical(a,original)) changed else a,
      ]),
      categoryQueues:catalog.categoryQueues,
      prioritizePersonalOrder:catalog.prioritizePersonalOrder,
      currentTask:catalog.currentTask,
      sessionActive:catalog.sessionActive,
      tasksPerDay:catalog.tasksPerDay,dailyMinutes:catalog.dailyMinutes,
      xpEvidence:catalog.xpEvidence,updatedAt:catalog.updatedAt,
    );
    return NativeM48TraversalPreview(
      before:before,
      after:NativeM48TaskCoordination(projected).preview(categoryId,
        excludedIds:excludedIds,limit:limit),
      wouldAdvanceCollection:true,
      assignmentId:original.id,
    );
  }
}
