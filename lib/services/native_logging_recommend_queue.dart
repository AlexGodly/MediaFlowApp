import '../data/mediaflow_models.dart';
import 'native_m43_recommendation_audit.dart';

/// An explicitly non-authoritative Personal Order preview entry.
/// This is not a generated task, website fallback, or a reroll result.
class NativeLoggingQueueOption {
  const NativeLoggingQueueOption({
    required this.title,required this.rank,required this.fromCollection,
    required this.collectionName,
  });
  final MediaFlowTitle title;
  final int rank;
  final bool fromCollection;
  final String collectionName;
}

class NativeLoggingQueuePage {
  const NativeLoggingQueuePage({
    required this.items,required this.offset,required this.hasMore,
    required this.message,
  });
  final List<NativeLoggingQueueOption> items;
  final int offset;
  final bool hasMore;
  final String message;
}

/// Bounded v287 Personal Order queue browser for native Logging.
/// Never presents these candidates as confirmed currentTask selections.
/// Browsing never mutates the queue, traversal or recommendation history.
abstract final class NativeLoggingRecommendQueue {
  static const pageSize=5;
  static const maxBrowse=50;

  static NativeLoggingQueuePage page(MediaFlowCatalog catalog,
      String categoryId,{
      int offset=0,
      NativeM43RecommendationAudit? audit,
  }) {
    if(offset<0||offset>=maxBrowse||offset%pageSize!=0){
      throw const FormatException('Queue page must be a valid 5-item offset');
    }
    if(categoryId.isEmpty||!catalog.categories.any(
      (category)=>category.id==categoryId)){
      return const NativeLoggingQueuePage(
        items:[],offset:0,hasMore:false,
        message:'Select a valid category to inspect the queue.');
    }
    if(catalog.prioritizePersonalOrder!=true){
      return NativeLoggingQueuePage(
        items:const [],offset:0,hasMore:false,
        message:catalog.prioritizePersonalOrder==null
          ?'Priority policy is unknown. No queue can be claimed as '
            'the website recommendation.'
          :'Personal Order prioritization is disabled. Queue browse '
            'is unavailable; the website fallback is not replicated.');
    }
    final entries=(audit??NativeM43RecommendationAudit(catalog))
      .forCategory(categoryId).recommendations;
    // Bounded: inspect the requested page plus one item to establish
    // hasMore. Never materialize a whole 100k-title Library into the UI.
    final last=(offset+pageSize+1).clamp(0,entries.length);
    final candidates=entries.skip(offset).take(last-offset).toList();
    // Count IDs only for the bounded candidates; an ambiguous ID cannot be
    // selected even if v287 resolved its first occurrence.
    final counts=<String,int>{
      for(final candidate in candidates) candidate.title.id:0,
    };
    for(final title in catalog.library){
      if(counts.containsKey(title.id)){
        counts[title.id]=counts[title.id]!+1;
      }
    }
    final safe=<NativeLoggingQueueOption>[];
    for(final entry in candidates.take(pageSize)){
      if(entry.title.id.isEmpty||counts[entry.title.id]!=1)continue;
      safe.add(NativeLoggingQueueOption(
        title:entry.title,rank:entry.recommendationIndex,
        fromCollection:entry.fromCollection,
        collectionName:entry.fromCollection
          ?'Collection assignment':'',
      ));
    }
    return NativeLoggingQueuePage(
      items:List.unmodifiable(safe),
      offset:offset,
      hasMore:offset+pageSize<maxBrowse && entries.length>offset+pageSize,
      message:'Personal Order queue preview only. These are not '
        'verified website fallback picks or task rerolls; selecting '
        'a title only opens a local Logging review.',
    );
  }
}
