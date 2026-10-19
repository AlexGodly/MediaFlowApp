import '../data/mediaflow_models.dart';

/// One v287 category queue slot. Collection assignments occupy exactly ONE
/// outer slot regardless of how many eligible member titles they contain.
class NativeM42QueueSlot {
  NativeM42QueueSlot({
    required this.categoryId, required this.token,
    required this.position, required this.isCollection,
    this.title, this.collection, this.assignment,
    required List<NativeM42QueueTitle> candidates,
    this.problem = '',
  }) : candidates = List.unmodifiable(candidates);
  final String categoryId, token, problem;
  final int position;
  final bool isCollection;
  final MediaFlowTitle? title;
  final MediaFlowCollection? collection;
  final MediaFlowCollectionAssignment? assignment;
  final List<NativeM42QueueTitle> candidates;
}

/// A read-only recommendation occurrence. `position` is not a Global rank:
/// source v287 queues are per category; the member index is within the
/// Collection's saved order, while recommendationIndex is inside the
/// category-specific deduplicated recommendation stream.
class NativeM42QueueTitle {
  const NativeM42QueueTitle({
    required this.title, required this.outerPosition,
    required this.collectionPosition, required this.assignmentId,
    required this.sourceType, required this.recommendationIndex,
  });
  final MediaFlowTitle title;
  final int outerPosition, collectionPosition, recommendationIndex;
  final String assignmentId, sourceType;
  bool get fromCollection => sourceType == 'collection';
}

/// Pure, source-grounded native projection of v287 and v368 behavior.
/// Neither the account's raw tokens nor Collections or traversal records
/// are ever mutated. Unknown/duplicate identifiers remain diagnostics.
class NativeM42MixedQueues {
  NativeM42MixedQueues(this.catalog) {
    for (final t in catalog.library) {
      if (t.id.isEmpty || _titles.containsKey(t.id)) {
        _ambiguousTitles.add(t.id);
      }
      _titles[t.id] = t;
    }
    for (final c in catalog.collections) {
      if (c.id.isEmpty || _collections.containsKey(c.id)) {
        _ambiguousCollections.add(c.id);
      }
      _collections[c.id] = c;
    }
    for (final a in catalog.collectionAssignments) {
      if (a.id.isEmpty || _assignments.containsKey(a.id)) {
        _ambiguousAssignments.add(a.id);
      }
      _assignments[a.id] = a;
    }
  }

  final MediaFlowCatalog catalog;
  final Map<String, MediaFlowTitle> _titles = {};
  final Map<String, MediaFlowCollection> _collections = {};
  final Map<String, MediaFlowCollectionAssignment> _assignments = {};
  final Set<String> _ambiguousTitles = {};
  final Set<String> _ambiguousCollections = {};
  final Set<String> _ambiguousAssignments = {};

  List<String> get categoryIds {
    final values = <String>{};
    for (final c in catalog.categories) {
      if (c.id.isNotEmpty) values.add(c.id);
    }
    for (final a in catalog.collectionAssignments) {
      if (a.categoryId.isNotEmpty) values.add(a.categoryId);
    }
    for (final tid in catalog.personalOrderIds) {
      final t = _titles[tid];
      if (t != null && t.categoryId.isNotEmpty) values.add(t.categoryId);
    }
    for (final cid in catalog.categoryQueues.keys) {
      if (cid.isNotEmpty) values.add(cid);
    }
    return List.unmodifiable(values);
  }

  bool _validTitle(String id) =>
      id.isNotEmpty && !_ambiguousTitles.contains(id) &&
      _titles.containsKey(id);
  bool _validCollection(String id) =>
      id.isNotEmpty && !_ambiguousCollections.contains(id) &&
      _collections.containsKey(id);
  bool _validAssignment(String id) =>
      id.isNotEmpty && !_ambiguousAssignments.contains(id) &&
      _assignments.containsKey(id);

  /// v287 eligibility for Collection members, including forced cross-category
  /// rows. Completion checks include finished progress even if status active.
  List<(MediaFlowTitle,int)> _eligibleMembers(
      MediaFlowCollectionAssignment assignment) {
    if (!_validCollection(assignment.collectionId)) return const [];
    final collection = _collections[assignment.collectionId]!;
    final traversed = assignment.traversedTitleIds.toSet();
    final items = <(MediaFlowTitle,int)>[];
    for (var i=0;i<collection.titleIds.length;i++) {
      final id=collection.titleIds[i];
      if (!_validTitle(id) || traversed.contains(id)) continue;
      final title=_titles[id]!;
      if (_isDropped(title)) continue;
      if (assignment.categoryRule != 'force' &&
          title.categoryId != assignment.categoryId) {
        continue;
      }
      if (assignment.completedRule != 'include' && _isCompleted(title)) {
        continue;
      }
      items.add((title,i+1));
    }
    return items;
  }

  static bool _isDropped(MediaFlowTitle t) =>
      t.status.toLowerCase() == 'dropped';
  static bool _isCompleted(MediaFlowTitle t) =>
      t.status.toLowerCase() == 'completed' ||
      (t.total != null && t.total!.isFinite && t.total! > 0 &&
       t.progress >= t.total!);

  /// Reconcile v287 `categoryQueues` **without writing**:
  /// keep valid original t:/c: slots, shift direct titles within title slots
  /// to reflect the current direct order, then append missing tokens.
  /// Source v287 uses createdAt + assignment ID for new collection tokens.
  List<String> tokensForCategory(String categoryId) {
    if (categoryId.isEmpty) return const [];
    final direct = <String>[];
    final directSeen = <String>{};
    for (final id in catalog.personalOrderIds) {
      final title = _titles[id];
      if (_validTitle(id) && title!.categoryId == categoryId &&
          directSeen.add(id)) {
        direct.add('t:$id');
      }
    }
    final availableAssignments = [
      for (final a in catalog.collectionAssignments)
        if (_validAssignment(a.id) && a.categoryId == categoryId &&
            _validCollection(a.collectionId)) a,
    ]..sort((a,b) {
      final n=a.createdAt.compareTo(b.createdAt);
      return n!=0?n:a.id.compareTo(b.id);
    });
    final collection = [
      for (final a in availableAssignments) 'c:${a.id}',
    ];
    final allowed={...direct,...collection};
    final raw=catalog.categoryQueues[categoryId] ?? const <String>[];
    final seen=<String>{};
    final kept=<String>[];
    for (final token in raw) {
      if (allowed.contains(token) && seen.add(token)) kept.add(token);
    }
    if (kept.isEmpty) return List.unmodifiable([...direct,...collection]);

    final directInSavedOrder=[
      for (final token in direct) if (seen.contains(token)) token,
    ];
    var index=0;
    final reconciled=[
      for (final token in kept)
        if (token.startsWith('t:')) directInSavedOrder[index++]
        else token,
    ];
    final emitted=reconciled.toSet();
    for (final token in direct) {
      if (emitted.add(token)) reconciled.add(token);
    }
    for (final token in collection) {
      if (emitted.add(token)) reconciled.add(token);
    }
    return List.unmodifiable(reconciled);
  }

  List<NativeM42QueueSlot> slotsForCategory(String categoryId) {
    final tokens=tokensForCategory(categoryId);
    final output=<NativeM42QueueSlot>[];
    final seenRecommended=<String>{};
    var sequence=0;
    for (var i=0;i<tokens.length;i++) {
      final token=tokens[i], position=i+1;
      if (token.startsWith('t:')) {
        final tid=token.substring(2);
        final title=_validTitle(tid)?_titles[tid]:null;
        final valid=title!=null && title.categoryId==categoryId &&
            !_isDropped(title) && !_isCompleted(title) &&
            seenRecommended.add(tid);
        output.add(NativeM42QueueSlot(
          categoryId:categoryId,token:token,position:position,
          isCollection:false,title:title,
          candidates:valid ? [
            NativeM42QueueTitle(
              title:title,outerPosition:position,collectionPosition:0,
              assignmentId:'',sourceType:'title',
              recommendationIndex:++sequence),
          ] : const [],
          problem:title==null?'Unresolved direct title reference':'',
        ));
      } else if (token.startsWith('c:')) {
        final aid=token.substring(2);
        final a=_validAssignment(aid)?_assignments[aid]:null;
        final collection = a != null && _validCollection(a.collectionId)
            ? _collections[a.collectionId] : null;
        final candidates=<NativeM42QueueTitle>[];
        if (a != null && collection != null) {
          for (final (title,memberIndex) in _eligibleMembers(a)) {
            // v287 recommendation stream suppresses repeated titles across
            // direct entries and multiple Collection assignments.
            if (!seenRecommended.add(title.id)) continue;
            candidates.add(NativeM42QueueTitle(
              title:title,outerPosition:position,
              collectionPosition:memberIndex,assignmentId:aid,
              sourceType:'collection',recommendationIndex:++sequence));
          }
        }
        output.add(NativeM42QueueSlot(
          categoryId:categoryId,token:token,position:position,
          isCollection:true,assignment:a,collection:collection,
          candidates:candidates,
          problem:collection==null?'Unresolved Collection reference':'',
        ));
      }
    }
    return List.unmodifiable(output);
  }

  /// Empty for titles not currently reachable through v287 recommendation
  /// eligibility. Queue slot is category-local, not a universal rank.
  List<NativeM42QueueTitle> placementsForTitle(String id) {
    if (!_validTitle(id)) return const [];
    final results=<NativeM42QueueTitle>[];
    for (final categoryId in categoryIds) {
      for (final slot in slotsForCategory(categoryId)) {
        for (final candidate in slot.candidates) {
          if (candidate.title.id==id) results.add(candidate);
        }
      }
    }
    return List.unmodifiable(results);
  }

  List<NativeM42QueueTitle> recommendationSequence(String categoryId) =>
      List.unmodifiable([
        for (final slot in slotsForCategory(categoryId))
          ...slot.candidates,
      ]);

  List<String> diagnosticsForCategory(String categoryId) {
    final messages=<String>[];
    final raw=catalog.categoryQueues[categoryId] ?? const <String>[];
    final valid=tokensForCategory(categoryId).toSet();
    final duplicates=<String>{};
    final seen=<String>{};
    for (final token in raw) {
      if (!seen.add(token)) duplicates.add(token);
      if (!valid.contains(token)) {
        messages.add('Ignored unavailable or malformed queue token: $token');
      }
    }
    if (duplicates.isNotEmpty) {
      messages.add('${duplicates.length} duplicate raw token(s) ignored');
    }
    if (_ambiguousTitles.isNotEmpty ||
        _ambiguousCollections.isNotEmpty ||
        _ambiguousAssignments.isNotEmpty) {
      messages.add('Duplicate/blank IDs exist; ambiguous references excluded');
    }
    final unresolved = catalog.collectionAssignments.where((a) =>
      a.categoryId==categoryId &&
      (!_validAssignment(a.id)||!_validCollection(a.collectionId))).length;
    if (unresolved>0) {
      messages.add('$unresolved unresolved Collection assignment(s) excluded');
    }
    return List.unmodifiable(messages);
  }
}
