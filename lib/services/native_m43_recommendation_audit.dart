import '../data/mediaflow_models.dart';
import 'native_m42_mixed_queue.dart';

/// Trace of one title's actual source slot. Null recommendationIndex means
/// the saved reference exists but v287 skips it for the shown reason.
class NativeM43TitlePlacement {
  const NativeM43TitlePlacement({
    required this.title, required this.categoryId,
    required this.token, required this.slotPosition,
    required this.memberPosition, required this.directSavedPosition,
    required this.assignmentId, required this.collectionName,
    required this.recommendationIndex, required this.reason,
  });
  final MediaFlowTitle title;
  final String categoryId, token, assignmentId, collectionName, reason;
  final int slotPosition, memberPosition, directSavedPosition;
  final int? recommendationIndex;
  bool get eligible => recommendationIndex != null;
  bool get fromCollection => assignmentId.isNotEmpty;
}

class NativeM43CategoryAudit {
  NativeM43CategoryAudit({
    required this.categoryId, required List<NativeM42QueueSlot> slots,
    required List<NativeM42QueueTitle> recommendations,
    required Map<String,List<NativeM43TitlePlacement>> placements,
    required this.unresolvedMembers,
  }) : slots=List.unmodifiable(slots),
       recommendations=List.unmodifiable(recommendations),
       placements=Map.unmodifiable({
         for(final e in placements.entries)
           e.key:List<NativeM43TitlePlacement>.unmodifiable(e.value),
       });
  final String categoryId;
  final List<NativeM42QueueSlot> slots;
  final List<NativeM42QueueTitle> recommendations;
  final Map<String,List<NativeM43TitlePlacement>> placements;
  final int unresolvedMembers;

  NativeM42QueueTitle? firstEligible({Set<String> excludedIds=const {}}) {
    for (final entry in recommendations) {
      if (!excludedIds.contains(entry.title.id)) return entry;
    }
    return null;
  }

  int get ineligibleOccurrences =>
      placements.values.fold(0,(total,entries)=>total+
        entries.where((entry)=>!entry.eligible).length);
}

/// v287 source-grounded Personal Order explanation, NOT a task generator.
/// Inspect v287RecommendationEntries, v287CollectionItemsForAssignment and
/// pickLibraryTitle priority toggle on the original website v410 tag.
/// The outer slot, member order and recommendation index are distinct.
class NativeM43RecommendationAudit {
  NativeM43RecommendationAudit(this.catalog,{NativeM42MixedQueues? reader})
      : queues=reader??NativeM42MixedQueues(catalog) {
    for(final t in catalog.library) {
      _library.putIfAbsent(t.id,()=>t);
    }
    for(var i=0;i<catalog.personalOrderIds.length;i++) {
      _savedOrder.putIfAbsent(catalog.personalOrderIds[i],()=>i+1);
    }
  }

  final MediaFlowCatalog catalog;
  final NativeM42MixedQueues queues;
  final Map<String,MediaFlowTitle> _library={};
  final Map<String,int> _savedOrder={};
  final Map<String,NativeM43CategoryAudit> _cached={};

  /// The website only uses the Personal Order first candidate when this
  /// setting is true. It falls back to its existing picker otherwise.
  /// Null means the source snapshot does not explicitly contain the toggle.
  bool? get priorityEnabled => catalog.prioritizePersonalOrder;

  NativeM43CategoryAudit forCategory(String categoryId) =>
    _cached.putIfAbsent(categoryId,()=>_build(categoryId));

  NativeM43CategoryAudit _build(String cid) {
    final slots=queues.slotsForCategory(cid);
    final occurrences=<String,List<NativeM43TitlePlacement>>{};
    var unresolved=0;
    void include(MediaFlowTitle title,NativeM42QueueSlot slot,{
      required int memberPosition,required String assignmentId,
      required String collectionName,required String reason,
      NativeM42QueueTitle? candidate,
    }) {
      (occurrences[title.id]??=[]).add(NativeM43TitlePlacement(
        title:title,categoryId:cid,token:slot.token,
        slotPosition:slot.position,memberPosition:memberPosition,
        directSavedPosition:_savedOrder[title.id]??0,
        assignmentId:assignmentId,collectionName:collectionName,
        recommendationIndex:candidate?.recommendationIndex,
        reason:candidate==null?reason:'Eligible recommendation',
      ));
    }
    final candidates=<NativeM42QueueTitle>[];
    for(final slot in slots) {
      candidates.addAll(slot.candidates);
      if(!slot.isCollection) {
        final title=slot.title;
        if(title==null) { unresolved++;continue; }
        final selected=slot.candidates.firstOrNull;
        include(title,slot,
          memberPosition:0,assignmentId:'',collectionName:'',
          reason:_ineligibleDirectReason(title),
          candidate:selected);
        continue;
      }
      final assignment=slot.assignment,collection=slot.collection;
      if(assignment==null||collection==null) {
        unresolved++;
        continue;
      }
      final shown={
        for(final c in slot.candidates)c.title.id:c,
      };
      final traversed=assignment.traversedTitleIds.toSet();
      for(var i=0;i<collection.titleIds.length;i++) {
        final title=_library[collection.titleIds[i]];
        if(title==null) { unresolved++;continue; }
        final candidate=shown[title.id];
        String reason;
        if(traversed.contains(title.id)) {
          reason='Already traversed in this Collection assignment';
        } else if(_dropped(title)) {
          reason='Dropped title';
        } else if(assignment.categoryRule!='force' &&
            title.categoryId!=cid) {
          reason='Category does not match the task';
        } else if(assignment.completedRule!='include' &&
            _completed(title)) {
          reason='Completed title skipped by Collection rule';
        } else {
          reason='Already recommended from an earlier queue slot';
        }
        include(title,slot,memberPosition:i+1,
          assignmentId:assignment.id,collectionName:collection.title,
          reason:reason,candidate:candidate);
      }
    }
    return NativeM43CategoryAudit(
      categoryId:cid,slots:slots,
      recommendations:candidates,placements:occurrences,
      unresolvedMembers:unresolved);
  }

  static bool _dropped(MediaFlowTitle title) =>
      title.status.toLowerCase()=='dropped';
  static bool _completed(MediaFlowTitle title) =>
      title.status.toLowerCase()=='completed' ||
      (title.total!=null && title.total!.isFinite && title.total!>0 &&
       title.progress>=title.total!);
  static String _ineligibleDirectReason(MediaFlowTitle title) {
    if (_dropped(title)) return 'Dropped title';
    if (_completed(title)) return 'Completed title';
    return 'Already recommended from an earlier queue slot';
  }

  /// All known references, eligible and ineligible, across category queues.
  /// This is computed lazily and cached per category for 100k-size accounts.
  List<NativeM43TitlePlacement> placementsForTitle(String titleId) {
    if (!_library.containsKey(titleId)) return const [];
    final placements=<NativeM43TitlePlacement>[];
    for(final cid in queues.categoryIds) {
      placements.addAll(forCategory(cid).placements[titleId]??const []);
    }
    return List.unmodifiable(placements);
  }

  /// ID or title lookup; never builds UI for all Library titles.
  List<MediaFlowTitle> searchTitles(String query,{int limit=15}) {
    if(limit<1||limit>100) {
      throw const FormatException('Invalid title search limit');
    }
    final needle=query.trim().toLowerCase();
    if(needle.isEmpty) return const [];
    final matches=<MediaFlowTitle>[];
    final seen=<String>{};
    for(final title in catalog.library) {
      if(title.id.isEmpty || !seen.add(title.id)) continue;
      if(title.id.toLowerCase().contains(needle) ||
          title.searchText.contains(needle)) {
        matches.add(title);
        if(matches.length>=limit) break;
      }
    }
    return List.unmodifiable(matches);
  }

  /// Models only the v180 queue-candidate exclusion step. The actual reroll
  /// has other candidate/history rules and may fall back to its old picker.
  NativeM42QueueTitle? firstEligibleWithExclusions(
      String categoryId, Set<String> excludedTitleIds) =>
      forCategory(categoryId).firstEligible(excludedIds:excludedTitleIds);
}
