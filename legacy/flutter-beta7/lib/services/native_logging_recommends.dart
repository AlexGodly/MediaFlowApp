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

  /// Additional source-grounded queue suggestions for the Logging picker.
  /// These are *not* the website's live task rerolls, provider results, or
  /// fallback recommendations. It is safe to show only an explicit v287
  /// Personal Order queue when prioritization is enabled.
  ///
  /// Work is deferred until the user expands the picker. It never mutates
  /// traversal state or drafts, and it cannot turn an unresolved saved task
  /// into an apparently verified recommendation.
  static List<NativeLoggingRecommendation> browseQueue(
    MediaFlowCatalog catalog,String categoryId,{
    NativeM43RecommendationAudit? audit,
    Set<String> excludedIds=const {},
    int limit=5,
  }){
    if(limit<1||limit>8){
      throw const FormatException('Choose between 1 and 8 suggestions');
    }
    if(categoryId.isEmpty||
        !catalog.categories.any((category)=>category.id==categoryId)||
        catalog.prioritizePersonalOrder!=true){
      return const [];
    }
    final display=NativeM50TaskDisplay.fromCatalog(catalog);
    if(display.task?.categoryId==categoryId &&
        display.resolution!=NativeM50TitleResolution.exact){
      return const [];
    }
    final entries=(audit??NativeM43RecommendationAudit(catalog))
      .forCategory(categoryId).recommendations;
    if(entries.isEmpty)return const [];

    // Queue parsing itself rejects ambiguous IDs. Verify again here so
    // older/imported Library snapshots cannot surface duplicate references.
    final candidateIds={for(final entry in entries)entry.title.id};
    final seen=<String>{};
    final duplicates=<String>{};
    for(final item in catalog.library){
      if(candidateIds.contains(item.id)&&!seen.add(item.id)){
        duplicates.add(item.id);
      }
    }
    final results=<NativeLoggingRecommendation>[];
    final displayed=<String>{};
    for(final entry in entries){
      final id=entry.title.id;
      if(id.isEmpty||duplicates.contains(id)||excludedIds.contains(id)||
          !displayed.add(id)||id==display.title?.id){
        continue;
      }
      results.add(NativeLoggingRecommendation(
        source:NativeLoggingRecommendSource.personalOrderPreview,
        categoryId:categoryId,title:entry.title,
        queuePosition:entry.recommendationIndex,
        fromCollection:entry.fromCollection,
        message:'Additional Personal Order queue preview · not a '
          'confirmed live recommendation. No queue traversal or '
          'saved task is changed.',
      ));
      if(results.length>=limit)break;
    }
    return List.unmodifiable(results);
  }

  /// Build a bounded, verified queue browser once per expanded category.
  /// The widget filters/searches/pages this immutable list without repeating
  /// 100k-Library duplicate checks whenever a checkbox changes. All entries
  /// remain unconfirmed Personal Order *previews*, not generated live tasks.
  static List<NativeLoggingRecommendation> browseQueueCatalog(
    MediaFlowCatalog catalog,String categoryId,{
    NativeM43RecommendationAudit? audit,int maxCandidates=500,
  }){
    if(maxCandidates<1||maxCandidates>500){
      throw const FormatException('Queue browser limit must be 1–500');
    }
    if(categoryId.isEmpty||
        !catalog.categories.any((category)=>category.id==categoryId)||
        catalog.prioritizePersonalOrder!=true){
      return const [];
    }
    final display=NativeM50TaskDisplay.fromCatalog(catalog);
    if(display.task?.categoryId==categoryId&&
        display.resolution!=NativeM50TitleResolution.exact){
      return const [];
    }
    final entries=(audit??NativeM43RecommendationAudit(catalog))
      .forCategory(categoryId).recommendations;
    if(entries.isEmpty){return const [];}
    final candidates={for(final entry in entries)entry.title.id};
    final seen=<String>{};
    final duplicates=<String>{};
    for(final title in catalog.library){
      if(candidates.contains(title.id)&&!seen.add(title.id)){
        duplicates.add(title.id);
      }
    }
    final results=<NativeLoggingRecommendation>[];
    final listed=<String>{};
    for(final entry in entries){
      final id=entry.title.id;
      if(id.isEmpty||duplicates.contains(id)||!listed.add(id)||
          id==display.title?.id){continue;}
      results.add(NativeLoggingRecommendation(
        source:NativeLoggingRecommendSource.personalOrderPreview,
        categoryId:categoryId,title:entry.title,
        queuePosition:entry.recommendationIndex,
        fromCollection:entry.fromCollection,
        message:'Personal Order queue preview only · not a confirmed '
          'live recommendation. No queue traversal or task change.',
      ));
      if(results.length>=maxCandidates){break;}
    }
    return List.unmodifiable(results);
  }

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
