import '../data/mediaflow_models.dart';
import 'native_editing_workspace.dart';
import 'native_itemized_parity.dart';
import 'native_m51_task_handoff.dart';

/// Saved v410 task context is only explanatory: never a log, transaction,
/// draft prefill, History record, or task completion.
enum NativeM52ContextStatus {
  ready, wrongOwner, replacedSnapshot, changedTask, differentTitle,
  workspaceMismatch,
}

class NativeM52ContextView {
  const NativeM52ContextView({
    required this.status, required this.message,
    this.taskUnit='',this.low=0,this.high=0,this.standard,this.itemized,
  });
  final NativeM52ContextStatus status;
  final String message,taskUnit;
  final double low,high;
  final NativeLogIntent? standard;
  final NativeItemizedPreview? itemized;
  bool get ready=>status==NativeM52ContextStatus.ready;
  bool get hasExistingDraft=>standard!=null||itemized!=null;
  String get draftSummary {
    if(standard!=null) {
      return 'Existing standard draft: ${standard!.units} consumed '
        '· ${standard!.minutes} minutes · ${standard!.mode.name} mode. '
        'Preserved without changes.';
    }
    if(itemized!=null) {
      return 'Existing itemized draft: ${itemized!.consumed} units '
        '· season ${itemized!.seasonName}'
        ' · ${itemized!.elapsedSeconds} seconds. '
        'Preserved without changes.';
    }
    return 'No existing local draft for this title. '
      'No units or dates were prefilled from the saved task.';
  }
}

/// Explicit handoff-continuation token retained in the Logging page's RAM.
/// Every access rechecks owner, catalog identity, task fields and title ID.
class NativeM52TaskDraftContext {
  NativeM52TaskDraftContext._({
    required this.ownerId,required this.source,required this.titleId,
    required this.categoryId,required this.unit,
    required this.low,required this.high,
  });
  final String ownerId,titleId,categoryId,unit;
  final MediaFlowCatalog source;
  final double low,high;

  factory NativeM52TaskDraftContext.fromHandoff({
    required NativeM51TaskHandoffView handoff,
    required MediaFlowCatalog catalog,
    required String currentOwnerId,
  }) {
    if(currentOwnerId.isEmpty || !handoff.ready ||
        handoff.title?.id.isEmpty!=false) {
      throw StateError('Verified owner and exact saved task required');
    }
    final task=catalog.sessionActive?catalog.currentTask:null;
    if(task==null || task.libraryId!=handoff.title!.id ||
       task.categoryId!=handoff.categoryId ||
       task.unit!=handoff.taskUnit ||
       task.low!=handoff.taskTargetLow ||
       task.high!=handoff.taskTargetHigh) {
      throw StateError('Task handoff does not match current snapshot');
    }
    return NativeM52TaskDraftContext._(
      ownerId:currentOwnerId,source:catalog,
      titleId:handoff.title!.id,categoryId:task.categoryId,
      unit:task.unit,low:task.low,high:task.high);
  }

  NativeM52ContextView inspect({
    required MediaFlowCatalog catalog,
    required String currentOwnerId,
    required String forTitleId,
    NativeEditingWorkspace? workspace,
  }) {
    if(currentOwnerId!=ownerId){
      return const NativeM52ContextView(
        status:NativeM52ContextStatus.wrongOwner,
        message:'Account changed. Task context cannot be reused.');
    }
    if(!identical(source,catalog)){
      return const NativeM52ContextView(
        status:NativeM52ContextStatus.replacedSnapshot,
        message:'Library snapshot changed. Review the saved task '
          'again in Dashboard. No local drafts were modified.');
    }
    final task=catalog.sessionActive?catalog.currentTask:null;
    if(task==null || task.libraryId!=titleId ||
       task.categoryId!=categoryId || task.unit!=unit ||
       task.low!=low || task.high!=high){
      return const NativeM52ContextView(
        status:NativeM52ContextStatus.changedTask,
        message:'Saved task changed. Context is no longer valid.');
    }
    if(forTitleId!=titleId){
      return const NativeM52ContextView(
        status:NativeM52ContextStatus.differentTitle,
        message:'This context belongs to a different Library title.');
    }
    if(workspace!=null && (workspace.ownerId!=ownerId ||
        workspace.stale ||
        (workspace.baseCatalog!=null &&
          !identical(workspace.baseCatalog,catalog)))){
      return const NativeM52ContextView(
        status:NativeM52ContextStatus.workspaceMismatch,
        message:'Local editing workspace is stale or belongs to another '
          'account. Existing drafts remain untouched.');
    }
    return NativeM52ContextView(
      status:NativeM52ContextStatus.ready,
      message:'Saved task target is informational only. '
        'Logging modes, seasons, runtime and draft timestamps are '
        'controlled solely by the existing local editors.',
      taskUnit:unit,low:low,high:high,
      standard:workspace?.logDraft(titleId),
      itemized:workspace?.itemizedDraft(titleId),
    );
  }
}
