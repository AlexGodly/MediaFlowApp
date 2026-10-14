import 'dart:math';

import 'package:flutter/foundation.dart';
import '../data/mediaflow_models.dart';

/// A deliberately lossy *screen preview*, never an account state_data writer.
class NativeM40CollectionFields {
  NativeM40CollectionFields({
    required this.title, required this.description,
    required this.coverUrl, required List<String> titleIds,
  }) : titleIds = List.unmodifiable(titleIds);

  final String title, description, coverUrl;
  final List<String> titleIds;

  factory NativeM40CollectionFields.fromCollection(MediaFlowCollection item) =>
      NativeM40CollectionFields(title: item.title,
        description: item.description, coverUrl: item.coverUrl,
        titleIds: item.titleIds);

  NativeM40CollectionFields copyWith({
    String? title, String? description, String? coverUrl,
    List<String>? titleIds,
  }) => NativeM40CollectionFields(
    title: title ?? this.title, description: description ?? this.description,
    coverUrl: coverUrl ?? this.coverUrl,
    titleIds: titleIds ?? this.titleIds,
  );

  bool matches(NativeM40CollectionFields other) =>
      title == other.title && description == other.description &&
      coverUrl == other.coverUrl && listEquals(titleIds, other.titleIds);

  MediaFlowCollection preview(String id) => MediaFlowCollection(
    id: id, title: title, description: description,
    coverUrl: coverUrl, titleIds: titleIds,
  );
}

class _CollectionRevision {
  _CollectionRevision(this.created, this.edited, this.deleted);
  final Map<String, NativeM40CollectionFields> created, edited;
  final Set<String> deleted;
}

/// Owner-scoped, RAM-only collection change planner. Not connected to
/// Supabase or to the M33 offline write queue.
///
/// Collection metadata on the v410 website also contains background settings,
/// created/updated times, tombstones and Personal Order assignments. The
/// MediaFlowCatalog projection omits some of them, so this projection must
/// NEVER be serialized to an account snapshot.
class NativeM40CollectionPlan extends ChangeNotifier {
  NativeM40CollectionPlan({required this.ownerId}) {
    if (ownerId.isEmpty) throw StateError('Authenticated owner required');
  }
  final String ownerId;
  final Random _random = Random.secure();
  MediaFlowCatalog? _base, _latest;
  final Map<String, MediaFlowCollection> _source = {};
  final Map<String, MediaFlowTitle> _library = {};
  final Set<String> _ambiguousCollections = {}, _ambiguousTitles = {};
  final Map<String, NativeM40CollectionFields> _created = {}, _edited = {};
  final Set<String> _deleted = {};
  final List<_CollectionRevision> _undo = [], _redo = [];
  bool _stale = false;
  int _sequence = 0, _revision = 0, _projectedRevision = -1;
  MediaFlowCatalog? _projected;

  bool get stale => _stale;
  bool get hasChanges => _created.isNotEmpty || _edited.isNotEmpty ||
      _deleted.isNotEmpty;
  bool get canUndo => !_stale && _undo.isNotEmpty;
  bool get canRedo => !_stale && _redo.isNotEmpty;
  bool get mayUpload => false;
  int get creations => _created.length;
  int get edits => _edited.length;
  int get deletions => _deleted.length;
  int get changeCount => creations + edits + deletions;
  MediaFlowCatalog? get source => _base;
  Iterable<String> get deletedIds => List.unmodifiable(_deleted);
  Iterable<String> get changedIds => List.unmodifiable(
    {..._created.keys, ..._edited.keys, ..._deleted},
  );

  void observe(MediaFlowCatalog catalog) {
    if (identical(catalog, _latest)) return;
    _latest = catalog;
    if (_base != null && !identical(_base, catalog) && hasChanges) {
      _stale = true;
      // No notifier here: observe is called while widgets build.
      return;
    }
    _attach(catalog);
  }

  void _attach(MediaFlowCatalog catalog) {
    _base = catalog;
    _stale = false;
    _source.clear();
    _library.clear();
    _ambiguousCollections.clear();
    _ambiguousTitles.clear();
    for (final c in catalog.collections) {
      if (_source.containsKey(c.id)) _ambiguousCollections.add(c.id);
      _source[c.id] = c;
    }
    for (final t in catalog.library) {
      if (_library.containsKey(t.id)) _ambiguousTitles.add(t.id);
      _library[t.id] = t;
    }
    _projectedRevision = -1;
    _projected = null;
  }

  void _ensureCurrent() {
    if (_base == null || _stale || !identical(_base, _latest)) {
      throw StateError('Collections source changed; discard stale changes first');
    }
  }

  void _validate(NativeM40CollectionFields fields) {
    _ensureCurrent();
    final uri = Uri.tryParse(fields.coverUrl);
    if (fields.title.trim().isEmpty || fields.title.length > 240 ||
        fields.description.length > 20000 || fields.coverUrl.length > 2000 ||
        (fields.coverUrl.isNotEmpty &&
          (uri == null || !{'http','https'}.contains(uri.scheme) ||
            uri.host.isEmpty)) ||
        fields.titleIds.length > 100000 ||
        fields.titleIds.any((id) => id.isEmpty || id.length > 256) ||
        fields.titleIds.toSet().length != fields.titleIds.length) {
      throw const FormatException('Invalid collection metadata or title ordering');
    }
  }

  void _assertRealCollection(String id) {
    _ensureCurrent();
    if (!_source.containsKey(id) || _ambiguousCollections.contains(id) ||
        id.isEmpty) {
      throw StateError('Missing or duplicate Collection ID');
    }
  }

  void _assertLibraryId(String id) {
    if (!_library.containsKey(id) || _ambiguousTitles.contains(id) ||
        id.isEmpty) {
      throw StateError('Missing or duplicate Library title ID');
    }
  }

  NativeM40CollectionFields fieldsFor(String id) {
    _ensureCurrent();
    final local = _created[id];
    if (local != null) return local;
    _assertRealCollection(id);
    return _edited[id] ?? NativeM40CollectionFields.fromCollection(_source[id]!);
  }

  bool isCreated(String id) => _created.containsKey(id);
  bool isEdited(String id) => _edited.containsKey(id);
  bool isDeleted(String id) => _deleted.contains(id);

  _CollectionRevision _capture() => _CollectionRevision(
    Map.of(_created), Map.of(_edited), Set.of(_deleted),
  );
  void _checkpoint() {
    if (_undo.length >= 30) _undo.removeAt(0);
    _undo.add(_capture());
    _redo.clear();
  }
  void _changed() {
    _revision++;
    _projectedRevision = -1;
    _projected = null;
    notifyListeners();
  }
  void _restore(_CollectionRevision checkpoint) {
    _created..clear()..addAll(checkpoint.created);
    _edited..clear()..addAll(checkpoint.edited);
    _deleted..clear()..addAll(checkpoint.deleted);
    _changed();
  }

  String create(NativeM40CollectionFields fields) {
    _validate(fields);
    for (final id in fields.titleIds) { _assertLibraryId(id); }
    if (changeCount >= 200) throw StateError('200 local changes maximum');
    _checkpoint();
    final id = 'local_m40_${++_sequence}_${_random.nextInt(1<<32).toRadixString(16)}';
    _created[id] = fields;
    _changed();
    return id;
  }

  void edit(String id, NativeM40CollectionFields fields) {
    _validate(fields);
    if (_deleted.contains(id)) {
      throw StateError('Restore collection before editing');
    }
    final old = fieldsFor(id);
    // Unresolved legacy references may be retained, but cannot be added.
    final previously = old.titleIds.toSet();
    for (final tid in fields.titleIds) {
      if (!previously.contains(tid)) _assertLibraryId(tid);
    }
    if (fields.matches(old)) return;
    if (!_created.containsKey(id) && !_edited.containsKey(id) &&
        changeCount >= 200) {
      throw StateError('200 local changes maximum');
    }
    _checkpoint();
    if (_created.containsKey(id)) {
      _created[id] = fields;
    } else if (fields.matches(
        NativeM40CollectionFields.fromCollection(_source[id]!))) {
      _edited.remove(id);
    } else {
      _edited[id] = fields;
    }
    _changed();
  }

  /// Add only unambiguous Library titles. Original membership/order is stable.
  void addTitles(String id, Iterable<String> titleIds) {
    _ensureCurrent();
    final ids = titleIds.toList(growable: false);
    if (ids.isEmpty || ids.length > 200) {
      throw const FormatException('Choose 1–200 titles');
    }
    for (final tid in ids) { _assertLibraryId(tid); }
    final old = fieldsFor(id);
    final seen = old.titleIds.toSet();
    final result = [...old.titleIds];
    for (final tid in ids) {
      if (seen.add(tid)) result.add(tid);
    }
    edit(id, old.copyWith(titleIds: result));
  }

  /// Removing from a collection NEVER deletes the Library title.
  void removeTitles(String id, Iterable<String> titleIds) {
    final ids = titleIds.toSet();
    if (ids.isEmpty || ids.length > 200) {
      throw const FormatException('Choose 1–200 members');
    }
    final old = fieldsFor(id);
    if (!old.titleIds.toSet().containsAll(ids)) {
      throw StateError('Collection membership changed or is missing');
    }
    edit(id, old.copyWith(
      titleIds: old.titleIds.where((tid) => !ids.contains(tid)).toList(),
    ));
  }

  void moveTitle(String id, String titleId, int position) {
    final old = fieldsFor(id);
    final index = old.titleIds.indexOf(titleId);
    if (index < 0 || position < 0 || position >= old.titleIds.length) {
      throw const FormatException('Invalid collection order position');
    }
    if (index == position) return;
    final ids = [...old.titleIds];
    final moved = ids.removeAt(index);
    ids.insert(position, moved);
    edit(id, old.copyWith(titleIds: ids));
  }

  /// Tombstones and Collection-in-Personal-Order cleanup are unverified.
  /// The deletion is only a reversible projection.
  void stageDelete(String id) {
    _ensureCurrent();
    if (!_created.containsKey(id)) _assertRealCollection(id);
    if (_deleted.contains(id)) return;
    if (!_created.containsKey(id) && !_edited.containsKey(id) &&
        changeCount >= 200) {
      throw StateError('200 local changes maximum');
    }
    _checkpoint();
    if (_created.remove(id) == null) {
      _edited.remove(id);
      _deleted.add(id);
    }
    _changed();
  }

  void restore(String id) {
    _ensureCurrent();
    if (!_deleted.contains(id)) throw StateError('No staged deletion to restore');
    _checkpoint();
    _deleted.remove(id);
    _changed();
  }

  void undo() {
    _ensureCurrent();
    if (_undo.isEmpty) return;
    _redo.add(_capture());
    _restore(_undo.removeLast());
  }
  void redo() {
    _ensureCurrent();
    if (_redo.isEmpty) return;
    _undo.add(_capture());
    _restore(_redo.removeLast());
  }
  void discard() {
    _created.clear();
    _edited.clear();
    _deleted.clear();
    _undo.clear();
    _redo.clear();
    if (_latest != null) _attach(_latest!);
    _changed();
  }

  MediaFlowCatalog previewCatalog() {
    _ensureCurrent();
    if (!hasChanges) return _base!;
    if (_projected != null && _projectedRevision == _revision) {
      return _projected!;
    }
    final base = _base!;
    final collections = <MediaFlowCollection>[
      for (final c in base.collections)
        if (!_deleted.contains(c.id))
          _edited[c.id]?.preview(c.id) ?? c,
      for (final entry in _created.entries)
        entry.value.preview(entry.key),
    ];
    _projected = MediaFlowCatalog(
      library: base.library, categories: base.categories,
      collections: List.unmodifiable(collections),
      sessions: base.sessions, personalOrderIds: base.personalOrderIds,
      currentTask: base.currentTask, sessionActive: base.sessionActive,
      tasksPerDay: base.tasksPerDay, dailyMinutes: base.dailyMinutes,
      xpEvidence: base.xpEvidence, updatedAt: base.updatedAt,
    );
    _projectedRevision = _revision;
    return _projected!;
  }
}
