import '../data/mediaflow_models.dart';
import 'native_itemized_parity.dart';
import 'native_logging_parity_preview.dart';
import 'native_m52_task_draft_context.dart';

/// Read-only, conservative comparison. The v410 submitLog flow groups
/// consumption by the *actual Library category* and compares this with
/// currentTask.targetMid AFTER successful submission. The native projection
/// has low/high, not the required targetMid transaction evidence.
enum NativeM53EvidenceStatus {
  invalidContext, noDraft, unknownTarget, differentCategory,
  belowBand, withinBand, aboveBand,
}
enum NativeM53EvidenceSource {
  none, standardDraft, itemizedDraft, standardPreview, itemizedPreview,
}

class NativeM53TaskCompletionEvidence {
  const NativeM53TaskCompletionEvidence({
    required this.status,required this.source,
    required this.explanation,
    this.amount=0,this.low=0,this.high=0,this.unit='',
    this.repeat=false,this.projectedLibraryCompletion=false,
    this.projectedLibraryProgress,
  });

  final NativeM53EvidenceStatus status;
  final NativeM53EvidenceSource source;
  final String explanation,unit;
  final double amount,low,high;
  final bool repeat,projectedLibraryCompletion;
  final double? projectedLibraryProgress;

  /// Range comparisons are only illustrative. Nothing in this class can
  /// produce a website task-completion/History/XP commitment.
  bool get comparable=>switch(status) {
    NativeM53EvidenceStatus.belowBand ||
    NativeM53EvidenceStatus.withinBand ||
    NativeM53EvidenceStatus.aboveBand=>true,
    _=>false,
  };
  double? get bandProgress => comparable && high>0
    ?(amount/high).clamp(0.0,1.0).toDouble():null;
  bool get confirmedTaskCompleted=>false;
  bool get canSubmit=>false;
  double? get confirmedXp=>null;
  bool get canAdvanceCollection=>false;
  bool get canAwardRespect=>false;

  String get bandLabel => switch(status) {
    NativeM53EvidenceStatus.belowBand=>'Below saved target range',
    NativeM53EvidenceStatus.withinBand=>'Within saved target range',
    NativeM53EvidenceStatus.aboveBand=>'Above saved target range',
    NativeM53EvidenceStatus.differentCategory=>'Different Library category',
    NativeM53EvidenceStatus.unknownTarget=>'Saved target cannot be compared',
    NativeM53EvidenceStatus.noDraft=>'No local draft to compare',
    NativeM53EvidenceStatus.invalidContext=>'Task evidence unavailable',
  };

  static NativeM53TaskCompletionEvidence evaluate({
    required NativeM52ContextView context,
    required MediaFlowCatalog catalog,
    required String titleId,
    NativeLoggingPreview? standardPreview,
    NativeItemizedPreview? itemizedPreview,
  }) {
    if(!context.ready) {
      return NativeM53TaskCompletionEvidence(
        status:NativeM53EvidenceStatus.invalidContext,
        source:NativeM53EvidenceSource.none,
        explanation:context.message);
    }

    final task=catalog.sessionActive?catalog.currentTask:null;
    if(task==null || task.libraryId!=titleId ||
       task.low!=context.low || task.high!=context.high ||
       task.unit!=context.taskUnit){
      return const NativeM53TaskCompletionEvidence(
        status:NativeM53EvidenceStatus.invalidContext,
        source:NativeM53EvidenceSource.none,
        explanation:'Task identity or target has changed.');
    }

    // Never accept ambiguous Library IDs, including when an editor provides
    // an externally constructed preview that happens to have a matching ID.
    MediaFlowTitle? title;
    for(final item in catalog.library){
      if(item.id!=titleId) { continue; }
      if(title!=null){
        return const NativeM53TaskCompletionEvidence(
          status:NativeM53EvidenceStatus.invalidContext,
          source:NativeM53EvidenceSource.none,
          explanation:'Duplicate Library IDs block task evidence.');
      }
      title=item;
    }
    if(title==null){
      return const NativeM53TaskCompletionEvidence(
        status:NativeM53EvidenceStatus.invalidContext,
        source:NativeM53EvidenceSource.none,
        explanation:'Task title is missing from the Library.');
    }
    // A source-projected preview is only acceptable for exactly this title.
    // The existing draft editor calculates the quantity separately; this
    // evaluator must not generate, save or modify that calculation.
    if(standardPreview!=null && itemizedPreview!=null){
      return const NativeM53TaskCompletionEvidence(
        status:NativeM53EvidenceStatus.invalidContext,
        source:NativeM53EvidenceSource.none,
        explanation:'Conflicting preview methods. Choose one editor.');
    }
    if(itemizedPreview!=null && itemizedPreview.titleId!=titleId){
      return const NativeM53TaskCompletionEvidence(
        status:NativeM53EvidenceStatus.invalidContext,
        source:NativeM53EvidenceSource.none,
        explanation:'Itemized preview belongs to another title.');
    }

    final standard=context.standard;
    final itemized=context.itemized;
    final source=standardPreview!=null
      ?NativeM53EvidenceSource.standardPreview
      :itemizedPreview!=null?NativeM53EvidenceSource.itemizedPreview
      :standard!=null?NativeM53EvidenceSource.standardDraft
      :itemized!=null?NativeM53EvidenceSource.itemizedDraft
      :NativeM53EvidenceSource.none;
    final quantity=standardPreview?.consumed ??
      itemizedPreview?.consumed.toDouble() ??
      standard?.units ?? itemized?.consumed.toDouble();
    if(quantity==null){
      return NativeM53TaskCompletionEvidence(
        status:NativeM53EvidenceStatus.noDraft,source:source,
        explanation:'No draft is staged for this title. No History or task '
          'progress has been recorded.');
    }

    final repeat=standardPreview?.repeat ??
      itemizedPreview?.repeat ??
      standard?.repeat ?? itemized?.repeat ?? false;
    final libraryComplete=standardPreview?.wouldComplete ??
      itemizedPreview?.completionCandidate ??
      standard?.wouldComplete ?? itemized?.completionCandidate ?? false;
    final libraryProgress=standardPreview?.projectedLibraryProgress ??
      itemizedPreview?.afterTitleProgress ??
      standard?.projectedProgress ?? itemized?.afterTitleProgress;

    if(!quantity.isFinite || quantity<=0){
      return NativeM53TaskCompletionEvidence(
        status:NativeM53EvidenceStatus.noDraft,source:source,
        explanation:'Draft does not contain positive finite consumption.');
    }
    final low=context.low,high=context.high;
    if(!low.isFinite || !high.isFinite || low<=0 || high<low ||
       context.taskUnit.trim().isEmpty){
      return NativeM53TaskCompletionEvidence(
        status:NativeM53EvidenceStatus.unknownTarget,source:source,
        amount:quantity,repeat:repeat,
        explanation:'Target bounds or unit are unavailable or inconsistent.');
    }
    if(title.categoryId!=task.categoryId){
      // Force Queue can intentionally recommend another category. v410 logs
      // that title under its actual category and may create a skipped row
      // for the assigned task; it cannot be called task completion.
      return NativeM53TaskCompletionEvidence(
        status:NativeM53EvidenceStatus.differentCategory,source:source,
        amount:quantity,low:low,high:high,unit:context.taskUnit,
        repeat:repeat,projectedLibraryCompletion:libraryComplete,
        projectedLibraryProgress:libraryProgress,
        explanation:'The saved task category differs from this title’s '
          'actual Library category. v410 logs by actual category; the '
          'assigned recommendation may be marked skipped.');
    }
    final band=quantity<low?NativeM53EvidenceStatus.belowBand
      :quantity>high?NativeM53EvidenceStatus.aboveBand
      :NativeM53EvidenceStatus.withinBand;
    return NativeM53TaskCompletionEvidence(
      status:band,source:source,amount:quantity,low:low,
      high:high,unit:context.taskUnit,
      repeat:repeat,projectedLibraryCompletion:libraryComplete,
      projectedLibraryProgress:libraryProgress,
      explanation:'Indicative quantity band only. v410 compares the '
        'successful log group with currentTask.targetMid (not available '
        'in this native snapshot), potentially includes additional '
        'titles in the category, and requires successful History and '
        'Library persistence. This does not verify task completion.');
  }
}
