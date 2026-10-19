import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/mediaflow_models.dart';
import 'native_m42_mixed_queue.dart';

class _M44Checkpoint {
  _M44Checkpoint(List<MediaFlowCollectionAssignment> assignments,
      Map<String,List<String>> queues,List<String> titleIds)
      : titleIds=List.unmodifiable(titleIds),
        assignments=List.unmodifiable(assignments),
        queues=Map.unmodifiable({
          for(final entry in queues.entries)
            entry.key:List<String>.unmodifiable(entry.value),
        });
  final List<String> titleIds;
  final List<MediaFlowCollectionAssignment> assignments;
  final Map<String,List<String>> queues;
}

/// RAM-only v287 Collection assignment planner. NEVER a cloud state writer:
/// the catalog excludes unknown v410 fields, IDs are locally generated,
/// and v287's save/task/XP/traversal side effects are deliberately absent.
class NativeM44PersonalOrderPlan extends ChangeNotifier {
  NativeM44PersonalOrderPlan({required this.ownerId}) {
    if(ownerId.isEmpty) {
      throw StateError('Authenticated owner required');
    }
  }

  final String ownerId;
  final Random _random=Random.secure();
  MediaFlowCatalog? _source,_latest;
  String _currentOwner='';
  bool _stale=false;
  int _sequence=0,_operations=0;
  List<MediaFlowCollectionAssignment> _assignments=[];
  List<String> _titleIds=[];
  final Map<String,MediaFlowTitle> _sourceTitles={};
  final Set<String> _duplicateTitleIds={};
  Map<String,List<String>> _queues={};
  final List<_M44Checkpoint> _undo=[],_redo=[];
  int _revision=0,_projectedRevision=-1;
  MediaFlowCatalog? _projected;
  final Set<String> _duplicateAssignmentIds={};
  final Set<String> _duplicateCollectionIds={};
  final Set<String> _duplicateCategoryIds={};

  bool get stale => _stale;
  bool get mayUpload => false;
  bool get canEdit => !_stale && _source!=null &&
      identical(_source,_latest) && _currentOwner==ownerId;
  bool get canUndo => canEdit && _undo.isNotEmpty;
  bool get canRedo => canEdit && _redo.isNotEmpty;
  int get pendingOperations => _operations;
  MediaFlowCatalog? get source => _source;
  List<String> get directTitleIds => List.unmodifiable(_titleIds);
  List<MediaFlowCollectionAssignment> get assignments =>
      List.unmodifiable(_assignments);

  bool get hasChanges {
    final base=_source;
    if(base==null) return false;
    if(!listEquals(base.personalOrderIds,_titleIds)) return true;
    if(base.collectionAssignments.length!=_assignments.length) return true;
    for(var i=0;i<_assignments.length;i++) {
      if(!_sameAssignment(base.collectionAssignments[i],_assignments[i])) {
        return true;
      }
    }
    if(base.categoryQueues.length!=_queues.length) return true;
    for(final entry in base.categoryQueues.entries) {
      if(!listEquals(entry.value,_queues[entry.key])) return true;
    }
    return false;
  }

  static bool _sameAssignment(MediaFlowCollectionAssignment a,
      MediaFlowCollectionAssignment b) =>
    a.id==b.id && a.collectionId==b.collectionId &&
    a.categoryId==b.categoryId && a.categoryRule==b.categoryRule &&
    a.completedRule==b.completedRule &&
    a.createdAt==b.createdAt &&
    listEquals(a.traversedTitleIds,b.traversedTitleIds);

  /// An owner switch or newer cloud snapshot quarantines dirty local edits.
  /// `observe` is safe inside Flutter build: no notifications until an edit.
  void observe(MediaFlowCatalog catalog,{required String currentOwnerId}) {
    _currentOwner=currentOwnerId;
    if(currentOwnerId!=ownerId) {
      _stale=true;
      return;
    }
    if(identical(_latest,catalog)) return;
    _latest=catalog;
    if(_source!=null && !identical(_source,catalog) && hasChanges) {
      _stale=true;
      return;
    }
    _attach(catalog);
  }

  void _attach(MediaFlowCatalog catalog) {
    _source=catalog;
    _stale=false;
    _assignments=List.of(catalog.collectionAssignments);
    _titleIds=List.of(catalog.personalOrderIds);
    _sourceTitles.clear();
    _duplicateTitleIds.clear();
    _duplicateIds(catalog.library.map((t)=>t.id),_duplicateTitleIds);
    for(final title in catalog.library) {
      _sourceTitles[title.id]=title;
    }
    _queues={
      for(final e in catalog.categoryQueues.entries)
        e.key:List.of(e.value),
    };
    _duplicateAssignmentIds.clear();
    _duplicateCollectionIds.clear();
    _duplicateCategoryIds.clear();
    _duplicateIds(catalog.collectionAssignments.map((a)=>a.id),
      _duplicateAssignmentIds);
    _duplicateIds(catalog.collections.map((c)=>c.id),
      _duplicateCollectionIds);
    _duplicateIds(catalog.categories.map((c)=>c.id),
      _duplicateCategoryIds);
    _undo.clear();
    _redo.clear();
    _operations=0;
    _projected=null;
    _projectedRevision=-1;
  }

  static void _duplicateIds(Iterable<String> ids,Set<String> duplicates) {
    final seen=<String>{};
    for(final id in ids) {
      if(id.isEmpty || !seen.add(id)) duplicates.add(id);
    }
  }

  void _ensureCurrent() {
    if(!canEdit) {
      throw StateError('Personal Order source/owner changed; '
        'discard quarantined changes before editing');
    }
  }

  void _assertCollection(String id) {
    _ensureCurrent();
    if(id.isEmpty || _duplicateCollectionIds.contains(id) ||
        !_source!.collections.any((c)=>c.id==id)) {
      throw StateError('Missing or ambiguous Collection ID');
    }
  }

  void _assertCategory(String id) {
    _ensureCurrent();
    if(id.isEmpty || _duplicateCategoryIds.contains(id) ||
        !_source!.categories.any((c)=>c.id==id)) {
      throw StateError('Missing or ambiguous task category');
    }
  }

  MediaFlowCollectionAssignment _assignment(String id) {
    _ensureCurrent();
    if(id.isEmpty || _duplicateAssignmentIds.contains(id)) {
      throw StateError('Ambiguous Collection assignment ID');
    }
    final match=_assignments.where((a)=>a.id==id).toList();
    if(match.length!=1) {
      throw StateError('Missing or duplicate Collection assignment ID');
    }
    return match.single;
  }

  /// Search is bounded for large accounts; cannot add an already-assigned pair.
  List<MediaFlowCollection> availableCollections(String categoryId,{
    String search='',int limit=60,
  }) {
    _assertCategory(categoryId);
    if(limit<1 || limit>200) {
      throw const FormatException('Invalid Collection picker limit');
    }
    final used={
      for(final a in _assignments)
        if(a.categoryId==categoryId) a.collectionId,
    };
    final needle=search.trim().toLowerCase();
    final out=<MediaFlowCollection>[];
    for(final c in _source!.collections) {
      if(c.id.isEmpty || _duplicateCollectionIds.contains(c.id) ||
          used.contains(c.id)) { continue; }
      if(needle.isNotEmpty &&
          !c.title.toLowerCase().contains(needle) &&
          !c.description.toLowerCase().contains(needle)) { continue; }
      out.add(c);
      if(out.length>=limit) { break; }
    }
    return List.unmodifiable(out);
  }

  _M44Checkpoint _capture() => _M44Checkpoint(_assignments,_queues,_titleIds);

  void _checkpoint() {
    _ensureCurrent();
    if(_operations>=200) {
      throw StateError('Maximum 200 staged Personal Order changes');
    }
    if(_undo.length>=30) _undo.removeAt(0);
    _undo.add(_capture());
    _redo.clear();
    // A staged edit changes the input to queue reconciliation immediately.
    _projected=null;
    _projectedRevision=-1;
    _operations++;
  }

  void _changed() {
    _revision++;
    _projectedRevision=-1;
    _projected=null;
    notifyListeners();
  }

  void _restore(_M44Checkpoint entry) {
    _assignments=List.of(entry.assignments);
    _titleIds=List.of(entry.titleIds);
    _queues={
      for(final e in entry.queues.entries)
        e.key:List.of(e.value),
    };
    _changed();
  }

  /// Source queue reconciliation happens only on this projected draft.
  /// Real categoryQueues and titleIds are never modified.
  List<String> tokens(String categoryId) {
    _ensureCurrent();
    return NativeM42MixedQueues(previewCatalog())
        .tokensForCategory(categoryId);
  }

  String addCollection(String collectionId,String categoryId) {
    _assertCollection(collectionId);
    _assertCategory(categoryId);
    if(_assignments.any((a)=>a.collectionId==collectionId &&
        a.categoryId==categoryId)) {
      throw StateError('Collection already assigned to this category');
    }
    _checkpoint();
    final now=DateTime.now().millisecondsSinceEpoch;
    final id='local_m44_${++_sequence}_${_random.nextInt(1<<32).toRadixString(16)}';
    _assignments=[
      ..._assignments,
      MediaFlowCollectionAssignment(
        id:id,collectionId:collectionId,categoryId:categoryId,
        categoryRule:'match',completedRule:'skip',
        traversedTitleIds:const [],createdAt:now),
    ];
    // Source adds new Collection blocks AFTER existing mixed slots.
    _queues[categoryId]=List.of(tokens(categoryId));
    _changed();
    return id;
  }

  void setRules(String id,{String? categoryRule,String? completedRule}) {
    final original=_assignment(id);
    final category=categoryRule??original.categoryRule;
    final completed=completedRule??original.completedRule;
    if(!const ['match','force'].contains(category) ||
        !const ['skip','include'].contains(completed)) {
      throw const FormatException('Invalid Collection queue rules');
    }
    if(category==original.categoryRule &&
        completed==original.completedRule) { return; }
    _checkpoint();
    _assignments=[
      for(final a in _assignments)
        if(identical(a,original))
          MediaFlowCollectionAssignment(
            id:a.id,collectionId:a.collectionId,categoryId:a.categoryId,
            categoryRule:category,completedRule:completed,
            traversedTitleIds:a.traversedTitleIds,createdAt:a.createdAt)
        else a,
    ];
    _changed();
  }

  void setPosition(String id,int position) {
    final a=_assignment(id);
    final current=tokens(a.categoryId);
    final from=current.indexOf('c:$id');
    if(from<0 || position<1 || position>current.length) {
      throw const FormatException('Invalid mixed queue position');
    }
    if(from==position-1) return;
    _checkpoint();
    final next=List<String>.of(current);
    final token=next.removeAt(from);
    next.insert(position-1,token);
    _queues[a.categoryId]=next;
    _changed();
  }

  void move(String id,int delta) {
    final a=_assignment(id);
    final current=tokens(a.categoryId);
    final from=current.indexOf('c:$id');
    if(from<0) throw StateError('Missing Collection queue slot');
    setPosition(id,(from+1+delta).clamp(1,current.length).toInt());
  }


  /// Move one v287 outer queue token to an exact 1-based category slot.
  /// A Collection remains one slot; crossing a direct title also updates the
  /// category's direct-title sequence in the SAME undo checkpoint so source
  /// v287 reconciliation does not silently undo the user's mixed order.
  /// Other categories' global direct-title slots retain their positions.
  void positionMixedToken(String categoryId,String token,int position) {
    _assertCategory(categoryId);
    _validateDirectOrder();
    if(token.startsWith('t:')) {
      final id=token.substring(2);
      _assertTitle(id);
      if(_sourceTitles[id]!.categoryId!=categoryId ||
          !_titleIds.contains(id)) {
        throw StateError('Direct title is not in the selected category queue');
      }
    } else if(token.startsWith('c:')) {
      final assignment=_assignment(token.substring(2));
      if(assignment.categoryId!=categoryId) {
        throw StateError('Collection block belongs to a different category');
      }
      _assertCollection(assignment.collectionId);
    } else {
      throw const FormatException('Malformed mixed queue token');
    }
    final current=tokens(categoryId);
    final from=current.indexOf(token);
    if(from<0) throw StateError('Queue token is not in the selected category');
    if(position<1||position>current.length) {
      throw const FormatException('Invalid mixed queue position');
    }
    if(position==from+1) return;
    final ordered=List<String>.of(current);
    ordered.removeAt(from);
    ordered.insert(position-1,token);

    // A bad/dangling direct reference must never be guessed, dropped, or
    // silently reindexed to a different title during a mixed-queue move.
    final directIds=[
      for(final t in ordered)
        if(t.startsWith('t:')) t.substring(2),
    ];
    final sourceIndexes=<int>[];
    for(var i=0;i<_titleIds.length;i++) {
      final id=_titleIds[i];
      if(_sourceTitles[id]?.categoryId==categoryId) {
        if(_duplicateTitleIds.contains(id)) {
          throw StateError('Ambiguous direct title in selected category');
        }
        sourceIndexes.add(i);
      }
    }
    if(sourceIndexes.length!=directIds.length ||
        sourceIndexes.toSet().length!=directIds.length ||
        directIds.toSet().length!=directIds.length) {
      throw StateError('Unresolved direct references prevent mixed queue editing');
    }
    final nextTitles=List<String>.of(_titleIds);
    for(var i=0;i<sourceIndexes.length;i++) {
      nextTitles[sourceIndexes[i]]=directIds[i];
    }
    _checkpoint();
    _titleIds=nextTitles;
    _queues[categoryId]=ordered;
    _changed();
  }

  void moveMixedToken(String categoryId,String token,int delta) {
    _assertCategory(categoryId);
    final current=tokens(categoryId);
    final index=current.indexOf(token);
    if(index<0) throw StateError('Queue token is not in the selected category');
    positionMixedToken(categoryId,token,
      (index+1+delta).clamp(1,current.length).toInt());
  }

  /// v138 direct Personal Order title operations. All use the same M44
  /// owner-pinned checkpoint stack as Collection assignment mutations.
  /// Unknown legacy order references are left untouched unless specifically
  /// removed; no account payload is ever rebuilt from this projection.
  void _assertTitle(String id) {
    _ensureCurrent();
    if(id.isEmpty || _duplicateTitleIds.contains(id) ||
        !_sourceTitles.containsKey(id)) {
      throw StateError('Missing or ambiguous Library title ID');
    }
  }

  void _validateDirectOrder() {
    _ensureCurrent();
    if(_titleIds.toSet().length!=_titleIds.length) {
      throw StateError('Duplicate saved Personal Order IDs; cannot reorder');
    }
  }

  /// Search is capped before materialization and retains the source Library
  /// ordering, just like v138 selected title additions.
  List<MediaFlowTitle> browseDirectTitlePicker({
    String categoryId='',String search='',bool alreadyOrdered=false,
    int limit=60,
  }) {
    _ensureCurrent();
    if(limit<1 || limit>200) {
      throw const FormatException('Invalid title picker page limit');
    }
    if(categoryId.isNotEmpty) _assertCategory(categoryId);
    final selected=_titleIds.toSet();
    final needle=search.trim().toLowerCase();
    final result=<MediaFlowTitle>[];
    for(final title in _source!.library) {
      if(title.id.isEmpty||_duplicateTitleIds.contains(title.id)) {
        continue;
      }
      if(categoryId.isNotEmpty && title.categoryId!=categoryId) {
        continue;
      }
      if(selected.contains(title.id)!=alreadyOrdered) {
        continue;
      }
      if(needle.isNotEmpty && !title.searchText.contains(needle) &&
          !title.id.toLowerCase().contains(needle)) {
        continue;
      }
      result.add(title);
      if(result.length>=limit) { break; }
    }
    return List.unmodifiable(result);
  }

  /// v138 selected Add follows Library order, independently of click order.
  /// A single checked batch is one reversible checkpoint, never a cloud edit.
  void addDirectTitles(Iterable<String> ids) {
    _validateDirectOrder();
    final picked=ids.toSet();
    if(picked.isEmpty || picked.length>200) {
      throw const FormatException('Select 1–200 Library titles');
    }
    for(final id in picked) { _assertTitle(id); }
    final known=_titleIds.toSet();
    final additions=<String>[];
    for(final item in _source!.library) {
      if(picked.contains(item.id) && known.add(item.id)) {
        additions.add(item.id);
      }
    }
    if(additions.isEmpty) { return; }
    _checkpoint();
    _titleIds=[..._titleIds,...additions];
    _changed();
  }

  /// Removes only direct-order references; Collection member blocks and
  /// Library titles are never deleted or modified.
  void removeDirectTitles(Iterable<String> ids) {
    _validateDirectOrder();
    final picked=ids.toSet();
    if(picked.isEmpty || picked.length>200) {
      throw const FormatException('Select 1–200 ordered titles');
    }
    if(!_titleIds.toSet().containsAll(picked)) {
      throw StateError('Selected direct titles are not in saved order');
    }
    // Explicit removal can clean dangling IDs, but never guessed IDs.
    _checkpoint();
    _titleIds=[
      for(final id in _titleIds) if(!picked.contains(id)) id,
    ];
    _changed();
  }

  /// Set a 1-based position globally or among titles of a single task
  /// category. In category mode, nonmatching titles keep their global slots.
  void positionDirectTitle(String id,int position,{String categoryId=''}) {
    _validateDirectOrder();
    _assertTitle(id);
    if(!_titleIds.contains(id)) {
      throw StateError('Title not currently in Personal Order');
    }
    if(categoryId.isNotEmpty) {
      _assertCategory(categoryId);
      if(_sourceTitles[id]!.categoryId!=categoryId) {
        throw StateError('Title does not belong to the chosen category');
      }
    }
    final indexes=<int>[];
    for(var i=0;i<_titleIds.length;i++) {
      final title=_sourceTitles[_titleIds[i]];
      if(categoryId.isEmpty || title?.categoryId==categoryId) {
        indexes.add(i);
      }
    }
    if(position<1 || position>indexes.length) {
      throw const FormatException('Invalid direct-title order position');
    }
    final ordered=[for(final i in indexes) _titleIds[i]];
    final from=ordered.indexOf(id);
    if(from<0) throw StateError('Ordered title is missing from category');
    if(from==position-1) { return; }
    _checkpoint();
    final moved=ordered.removeAt(from);
    ordered.insert(position-1,moved);
    final updated=List<String>.of(_titleIds);
    for(var i=0;i<indexes.length;i++) {
      updated[indexes[i]]=ordered[i];
    }
    _titleIds=updated;
    _changed();
  }

  void moveDirectTitle(String id,int delta,{String categoryId=''}) {
    _validateDirectOrder();
    _assertTitle(id);
    if(categoryId.isNotEmpty) _assertCategory(categoryId);
    final matching=<String>[];
    for(final item in _titleIds) {
      if(categoryId.isEmpty || _sourceTitles[item]?.categoryId==categoryId) {
        matching.add(item);
      }
    }
    final from=matching.indexOf(id);
    if(from<0) {
      throw StateError('Title missing from selected direct category');
    }
    final next=(from+delta).clamp(0,matching.length-1).toInt();
    positionDirectTitle(id,next+1,categoryId:categoryId);
  }

  /// Removes an assignment only; original Collection and Library titles stay.
  void remove(String id) {
    final a=_assignment(id);
    _checkpoint();
    _assignments=[
      for(final item in _assignments) if(item.id!=id) item,
    ];
    _queues[a.categoryId]=[
      for(final token in _queues[a.categoryId]??const <String>[])
        if(token!='c:$id') token,
    ];
    _changed();
  }

  /// Explicit draft-only reset, never the original traversal history.
  void resetTraversal(String id) {
    final original=_assignment(id);
    if(original.traversedTitleIds.isEmpty) return;
    _checkpoint();
    _assignments=[
      for(final a in _assignments)
        if(identical(a,original))
          MediaFlowCollectionAssignment(
            id:a.id,collectionId:a.collectionId,categoryId:a.categoryId,
            categoryRule:a.categoryRule,completedRule:a.completedRule,
            traversedTitleIds:const [],createdAt:a.createdAt)
        else a,
    ];
    _changed();
  }

  void undo() {
    _ensureCurrent();
    if(_undo.isEmpty) return;
    _redo.add(_capture());
    _restore(_undo.removeLast());
    if(_operations>0) _operations--;
  }

  void redo() {
    _ensureCurrent();
    if(_redo.isEmpty) return;
    if(_undo.length>=30) _undo.removeAt(0);
    _undo.add(_capture());
    _restore(_redo.removeLast());
    _operations++;
  }

  /// Explicit discard is the ONLY way to clear the quarantine. A different
  /// account can never be attached to this permanently owner-pinned plan.
  void discard() {
    _undo.clear();
    _redo.clear();
    _operations=0;
    if(_currentOwner==ownerId && _latest!=null) {
      _attach(_latest!);
    } else {
      _stale=true;
      _source=null;
      _assignments=[];
      _titleIds=[];
      _sourceTitles.clear();
      _queues={};
    }
    _changed();
  }

  MediaFlowCatalog previewCatalog() {
    _ensureCurrent();
    if(!hasChanges) return _source!;
    if(_projected!=null && _projectedRevision==_revision) {
      return _projected!;
    }
    final base=_source!;
    // Preserve pre-M45 identity contracts when a related surface is not
    // touched. Unchanged Library, Personal Order and assignments should still
    // reference exactly the original authoritative catalog structures.
    final untouchedAssignments=_assignments.length==
        base.collectionAssignments.length &&
        List.generate(_assignments.length,(i)=>i).every((i)=>
          identical(_assignments[i],base.collectionAssignments[i]));
    final sameDirectOrder=listEquals(_titleIds,base.personalOrderIds);
    _projected=MediaFlowCatalog(
      library:base.library,categories:base.categories,
      collections:base.collections,sessions:base.sessions,
      personalOrderIds:sameDirectOrder ? base.personalOrderIds :
        List.unmodifiable(_titleIds),
      collectionAssignments:untouchedAssignments ?
        base.collectionAssignments : List.unmodifiable(_assignments),
      categoryQueues:Map.unmodifiable({
        for(final e in _queues.entries)
          e.key:List<String>.unmodifiable(e.value),
      }),
      prioritizePersonalOrder:base.prioritizePersonalOrder,
      currentTask:base.currentTask,
      sessionActive:base.sessionActive,tasksPerDay:base.tasksPerDay,
      dailyMinutes:base.dailyMinutes,
      xpEvidence:base.xpEvidence,updatedAt:base.updatedAt,
    );
    _projectedRevision=_revision;
    return _projected!;
  }
}
