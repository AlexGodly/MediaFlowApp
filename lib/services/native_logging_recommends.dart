import '../data/mediaflow_models.dart';
import 'native_m43_recommendation_audit.dart';
import 'native_m50_task_display.dart';

enum NativeLoggingRecommendSource {
  savedTask, personalOrderPreview, unavailable,
}

/// Source-pinned read-only entry point for MediaFlow Recommends in Logging.
/// The website's v382 "Use recommended title" adds a title to its draft;
/// this native subset only selects the exact existing Library title.
class NativeLoggingRecommendation {
  const NativeLoggingRecommendation({
    required this.source,required this.message,this.title,
    this.categoryId='',this.queuePosition=0,this.fromCollection=false,
  });
  final NativeLoggingRecommendSource source;
  final String message,categoryId;
  final MediaFlowTitle? title;
  final int queuePosition;
  final bool fromCollection;
  bool get canUse=>title!=null &&
    source!=NativeLoggingRecommendSource.unavailable;

  static NativeLoggingRecommendation forCategory(
    MediaFlowCatalog catalog,String categoryId,{
    NativeM43RecommendationAudit? audit,
  }){
    if(categoryId.isEmpty || !catalog.categories.any(
        (category)=>category.id==categoryId)){
      return const NativeLoggingRecommendation(
        source:NativeLoggingRecommendSource.unavailable,
        message:'Select a category to inspect saved recommendations.');
    }
    final display=NativeM50TaskDisplay.fromCatalog(catalog);
    if(display.task?.categoryId==categoryId){
      if(display.resolution==NativeM50TitleResolution.exact &&
          display.title!=null) {
        return NativeLoggingRecommendation(
          source:NativeLoggingRecommendSource.savedTask,
          message:'Saved current task · exact Library ID. '
            'Use Recommended Title only adds it to this local Logging '
            'selection; no task or progress is submitted.',
          title:display.title,categoryId:categoryId);
      }
      // Never silently replace an unresolved saved task with another
      // queue title and call it the user's current recommendation.
      return NativeLoggingRecommendation(
        source:NativeLoggingRecommendSource.unavailable,
        categoryId:categoryId,
        message:'Current saved task Library ID is missing or ambiguous. '
          'The native app will not guess its title.');
    }
    if(catalog.prioritizePersonalOrder!=true){
      return NativeLoggingRecommendation(
        source:NativeLoggingRecommendSource.unavailable,
        categoryId:categoryId,
        message:catalog.prioritizePersonalOrder==null
          ?'Recommendation policy not present in this snapshot. '
            'The website picker cannot be reconstructed safely.'
          :'Personal Order prioritization is disabled. '
            'The website fallback picker is not reproduced.');
    }
    final reader=audit??NativeM43RecommendationAudit(catalog);
    final entry=reader.forCategory(categoryId).firstEligible();
    if(entry==null){
      return NativeLoggingRecommendation(
        source:NativeLoggingRecommendSource.unavailable,
        categoryId:categoryId,
        message:'No eligible Personal Order queue candidate for this '
          'category. The website fallback picker is not reproduced.');
    }
    // A queue title reference is not an identity proof when legacy
    // Library rows contain duplicate IDs. Quarantine duplicates.
    var matches=0;
    for(final title in catalog.library){
      if(title.id==entry.title.id){matches++;}
      if(matches>1){break;}
    }
    if(matches!=1||entry.title.id.isEmpty){
      return NativeLoggingRecommendation(
        source:NativeLoggingRecommendSource.unavailable,
        categoryId:categoryId,
        message:'Queue candidate has a missing or duplicated Library '
          'ID; recommendation cannot be added safely.');
    }
    return NativeLoggingRecommendation(
      source:NativeLoggingRecommendSource.personalOrderPreview,
      categoryId:categoryId,
      title:entry.title,
      queuePosition:entry.recommendationIndex,
      fromCollection:entry.fromCollection,
      message:'Personal Order queue preview only · not a confirmed '
        'website task or fallback recommendation. Queue position and '
        'Collection traversal are unchanged.');
  }
}
