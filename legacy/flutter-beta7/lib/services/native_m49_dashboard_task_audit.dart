import '../data/mediaflow_models.dart';
import 'native_m42_mixed_queue.dart';
import 'native_m48_task_coordination.dart';

/// What the saved v410 task and currently reconstructed v287 queue can
/// actually establish. A title-text match is deliberately never used as an ID.
enum NativeM49TaskEvidenceStatus {
  inactive,
  unknownCategory,
  missingLibraryId,
  missingLibraryTitle,
  ambiguousLibraryId,
  notInQueue,
  queueMatchUnverified,
  confirmedQueueSource,
  sourceConflict,
}

class NativeM49DashboardTaskEvidence {
  const NativeM49DashboardTaskEvidence({
    required this.status,required this.categoryId,
    required this.taskLibraryId,required this.priority,
    required this.queuePreview,this.currentMatch,
    required this.details,
  });
  final NativeM49TaskEvidenceStatus status;
  final String categoryId,taskLibraryId,details;
  final NativeM48PriorityPolicy priority;
  final NativeM48TaskPreview? queuePreview;
  final NativeM42QueueTitle? currentMatch;
  bool get confirmed =>
      status==NativeM49TaskEvidenceStatus.confirmedQueueSource;
}

/// An immutable explanation of a snapshot's current task and category-local
/// Personal Order queue. Never generates tasks, rerolls, or logs History.
class NativeM49DashboardTaskAudit {
  NativeM49DashboardTaskAudit(this.catalog)
      : coordinator=NativeM48TaskCoordination(catalog);
  final MediaFlowCatalog catalog;
  final NativeM48TaskCoordination coordinator;

  NativeM49DashboardTaskEvidence inspect({String categoryId='',
      Set<String> excludedTitleIds=const {},int limit=5}) {
    final task=catalog.sessionActive?catalog.currentTask:null;
    final category=categoryId.isNotEmpty?categoryId:
        task?.categoryId??'';
    final policy=coordinator.policy;
    final available=coordinator.audit.queues.categoryIds;
    if(category.isEmpty||!available.contains(category)) {
      return NativeM49DashboardTaskEvidence(
        status:task==null?NativeM49TaskEvidenceStatus.inactive:
          NativeM49TaskEvidenceStatus.unknownCategory,
        categoryId:category,taskLibraryId:task?.libraryId??'',
        priority:policy,queuePreview:null,
        details:task==null
          ?'No active saved task. Select an existing category to inspect '
            'its Personal Order recommendations.'
          :'Current task category is absent from the available queue catalog.',
      );
    }
    final preview=coordinator.preview(category,
      excludedIds:excludedTitleIds,limit:limit);
    if(task==null||task.categoryId!=category) {
      return NativeM49DashboardTaskEvidence(
        status:NativeM49TaskEvidenceStatus.inactive,
        categoryId:category,taskLibraryId:task?.libraryId??'',
        priority:policy,queuePreview:preview,
        details:task==null?'Category queue preview only. No active saved task.'
          :'Category queue preview only. Active task belongs elsewhere.',
      );
    }
    if(task.libraryId.isEmpty) {
      return NativeM49DashboardTaskEvidence(
        status:NativeM49TaskEvidenceStatus.missingLibraryId,
        categoryId:category,taskLibraryId:'',priority:policy,
        queuePreview:preview,
        details:'Saved task has no exact Library ID. Its title text is '
          'not sufficient to identify its Personal Order source.',
      );
    }
    final id=task.libraryId;
    var matches=0;
    for(final t in catalog.library) {
      if(t.id==id) matches++;
      if(matches>1) break;
    }
    if(matches>1) {
      return NativeM49DashboardTaskEvidence(
        status:NativeM49TaskEvidenceStatus.ambiguousLibraryId,
        categoryId:category,taskLibraryId:id,priority:policy,
        queuePreview:preview,
        details:'The saved task Library ID is duplicated. '
          'No queue provenance is asserted.',
      );
    }
    if(matches==0) {
      return NativeM49DashboardTaskEvidence(
        status:NativeM49TaskEvidenceStatus.missingLibraryTitle,
        categoryId:category,taskLibraryId:id,priority:policy,
        queuePreview:preview,
        details:'The saved task Library ID cannot be resolved.',
      );
    }
    // Use the FULL category stream, not the bounded first-five preview.
    // A current task may legitimately be ranked beyond that viewport.
    final occurrence=coordinator.audit.forCategory(category)
        .recommendations.where((x)=>x.title.id==id).firstOrNull;
    if(occurrence==null) {
      return NativeM49DashboardTaskEvidence(
        status:NativeM49TaskEvidenceStatus.notInQueue,
        categoryId:category,taskLibraryId:id,priority:policy,
        queuePreview:preview,
        details:'Saved task title is not currently eligible in the '
          'category queue. It may predate a queue edit, reroll, '
          'traversal, or fallback selection.',
      );
    }
    final annotation=task.orderSource;
    if(annotation==null) {
      return NativeM49DashboardTaskEvidence(
        status:NativeM49TaskEvidenceStatus.queueMatchUnverified,
        categoryId:category,taskLibraryId:id,priority:policy,
        queuePreview:preview,currentMatch:occurrence,
        details:'This Library ID appears in the current Personal Order '
          'queue, but no saved v287 source annotation confirms that the '
          'website selected it from this queue.',
      );
    }
    final expected=occurrence.fromCollection?'collection':'title';
    final consistent=annotation.libraryId==id &&
        annotation.categoryId==category &&
        annotation.type==expected &&
        annotation.assignmentId==occurrence.assignmentId;
    return NativeM49DashboardTaskEvidence(
      status:consistent
        ?NativeM49TaskEvidenceStatus.confirmedQueueSource
        :NativeM49TaskEvidenceStatus.sourceConflict,
      categoryId:category,taskLibraryId:id,priority:policy,
      queuePreview:preview,currentMatch:occurrence,
      details:consistent
        ?'The saved v287 source annotation matches this Library ID, '
          'queue category, source type and Collection assignment. '
          'It confirms queue provenance for this snapshot, not why '
          'the scheduler chose this task.'
        :'Saved v287 source annotation conflicts with the current queue. '
          'Do not assume Collection traversal or source attribution.',
    );
  }
}
