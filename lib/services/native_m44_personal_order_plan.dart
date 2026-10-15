import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/mediaflow_models.dart';
import 'native_m42_mixed_queue.dart';

class _M44Checkpoint {
  _M44Checkpoint(List<MediaFlowCollectionAssignment> assignments,
      Map<String,List<String>> queues)
      : assignments=List.unmodifiable(assignments),
        queues=Map.unmodifiable({
          for(final entry in queues.entries)
            entry.key:List<String>.unmodifiable(entry.value),
        });
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
  List<MediaFlowCollectionAssignment> get assignments =>
      List.unmodifiable(_assignments);

  bool get hasChanges {
    final base=_source;
    if(base==null) return false;
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

  _M44Checkpoint _capture() => _M44Checkpoint(_assignments,_queues);

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
    _projected=MediaFlowCatalog(
      library:base.library,categories:base.categories,
      collections:base.collections,sessions:base.sessions,
      personalOrderIds:base.personalOrderIds,
      collectionAssignments:List.unmodifiable(_assignments),
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
