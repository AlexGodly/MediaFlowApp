import 'dart:math';

import 'package:flutter/foundation.dart';
import '../data/mediaflow_models.dart';

/// Typed editable *projection*. Original full v410 fields/side effects cannot
/// be reconstructed from MediaFlowCatalog and must never be uploaded from it.
class NativeM37Fields {
  NativeM37Fields({
    required this.title,
    required this.categoryId,
    required this.status,
    required this.priority,
    required this.progress,
    required this.total,
    required this.rating,
    required this.coverUrl,
    required this.description,
    List<String> tags = const [],
  }) : tags = List.unmodifiable(tags);
  final String title, categoryId, status, priority, coverUrl, description;
  final double progress;
  final double? total, rating;
  final List<String> tags;

  factory NativeM37Fields.fromTitle(MediaFlowTitle title) =>
      NativeM37Fields(
        title: title.title, categoryId: title.categoryId,
        status: title.status, priority: title.priority,
        progress: title.progress, total: title.total, rating: title.rating,
        coverUrl: title.coverUrl, description: title.description,
        tags: title.tags,
      );

  bool sameAs(NativeM37Fields other) =>
      title == other.title && categoryId == other.categoryId &&
      status == other.status && priority == other.priority &&
      progress == other.progress && total == other.total &&
      rating == other.rating && coverUrl == other.coverUrl &&
      description == other.description &&
      listEquals(tags, other.tags);

  MediaFlowTitle preview(String id, {MediaFlowTitle? original}) =>
      MediaFlowTitle(
        id: id, title: title, categoryId: categoryId, status: status,
        priority: priority, progress: progress, total: total, rating: rating,
        coverUrl: coverUrl, tags: tags,
        seasons: original?.seasons ?? const [],
        addedAt: original?.addedAt, completedAt: original?.completedAt,
        description: description,
      );
}

class _M37Revision {
  _M37Revision(this.created, this.updated, this.deleted);
  final Map<String, NativeM37Fields> created;
  final Map<String, NativeM37Fields> updated;
  final Set<String> deleted;
}

/// A reversible, bounded, RAM-only Library change planner.
/// - Never obtains a client, writer, RPC, or raw state_data.
/// - Never mutates the source catalog, History, collections, XP or orders.
/// - A new authenticated projection invalidates existing nonempty plans.
/// - Creates are client-local temp IDs only, NOT v410 cloud Library IDs.
class NativeM37LibraryPlan extends ChangeNotifier {
  NativeM37LibraryPlan({required this.ownerId}) {
    if (ownerId.isEmpty) { throw StateError('Signed-in owner is required'); }
  }
  final String ownerId;
  MediaFlowCatalog? _base, _latest;
  Map<String, MediaFlowTitle> _source = {};
  final Set<String> _ambiguous = {};
  final Map<String, NativeM37Fields> _created = {};
  final Map<String, NativeM37Fields> _updated = {};
  final Set<String> _deleted = {};
  final List<_M37Revision> _undo = [], _redo = [];
  final Random _random = Random.secure();
  bool _stale = false;
  int _sequence = 0;

  bool get stale => _stale;
  bool get hasChanges =>
      _created.isNotEmpty || _updated.isNotEmpty || _deleted.isNotEmpty;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get creationCount => _created.length;
  int get editCount => _updated.length;
  int get deletionCount => _deleted.length;
  int get changeCount => creationCount + editCount + deletionCount;
  Iterable<String> get deletedIds => List.unmodifiable(_deleted);
  Iterable<String> get changedIds => List.unmodifiable(
      {..._created.keys,..._updated.keys,..._deleted});
  bool get mayUpload => false;
  MediaFlowCatalog? get source => _base;

  void observe(MediaFlowCatalog catalog) {
    if (identical(_latest, catalog)) { return; }
    _latest = catalog;
    if (_base != null && !identical(_base, catalog) && hasChanges) {
      _stale = true;
      return;
    }
    _attach(catalog);
    // Caller is often inside FutureBuilder.build; do not notify while building.
  }

  void _attach(MediaFlowCatalog catalog) {
    _base = catalog;
    _source = {};
    _ambiguous.clear();
    for (final title in catalog.library) {
      if (_source.containsKey(title.id)) { _ambiguous.add(title.id); }
      _source[title.id] = title;
    }
    _stale = false;
  }

  void _ensureValid() {
    if (_stale || _base == null || !identical(_base, _latest)) {
      throw StateError('Library source changed. Discard this local plan first.');
    }
  }

  void _validate(NativeM37Fields fields, {MediaFlowTitle? original}) {
    _ensureValid();
    if (fields.title.trim().isEmpty || fields.title.length > 400 ||
        !_base!.categories.any((c) => c.id == fields.categoryId) ||
        !const {'planned','active','paused','dropped','completed'}
            .contains(fields.status) ||
        !const {'low','medium','high'}.contains(fields.priority) ||
        !fields.progress.isFinite || fields.progress < 0 ||
        (fields.total != null && (!fields.total!.isFinite ||
          fields.total! < 0 || fields.progress > fields.total!)) ||
        (fields.rating != null && (!fields.rating!.isFinite ||
          fields.rating! < 0 || fields.rating! > 10)) ||
        fields.coverUrl.length > 2000 ||
        (fields.coverUrl.isNotEmpty &&
            !const {'https','http'}.contains(
              Uri.tryParse(fields.coverUrl)?.scheme)) ||
        fields.description.length > 20000 ||
        fields.tags.length > 100 ||
        fields.tags.any((t) => t.trim().isEmpty || t.length > 100)) {
      throw const FormatException('Invalid Library title fields');
    }
    if (original != null && original.seasons.isNotEmpty &&
        (fields.progress != original.progress ||
         fields.total != original.total)) {
      throw const FormatException(
        'Season aggregate editing requires verified season parity');
    }
  }

  MediaFlowTitle _requireExisting(String id) {
    _ensureValid();
    if (id.isEmpty || _ambiguous.contains(id) ||
        !_source.containsKey(id)) {
      throw StateError('Missing or duplicate Library title ID');
    }
    return _source[id]!;
  }

  _M37Revision _capture() => _M37Revision(
    Map.of(_created), Map.of(_updated), Set.of(_deleted),
  );

  void _checkpoint() {
    if (_undo.length >= 30) { _undo.removeAt(0); }
    _undo.add(_capture());
    _redo.clear();
  }

  void _restoreRevision(_M37Revision revision) {
    _created..clear()..addAll(revision.created);
    _updated..clear()..addAll(revision.updated);
    _deleted..clear()..addAll(revision.deleted);
    notifyListeners();
  }

  void create(NativeM37Fields fields) {
    _validate(fields);
    if (changeCount >= 200) { throw StateError('200 local changes maximum'); }
    _checkpoint();
    final id = 'local_m37_${++_sequence}_${_random.nextInt(1<<32).toRadixString(16)}';
    _created[id] = fields;
    notifyListeners();
  }

  void edit(String id, NativeM37Fields fields) {
    if (_created.containsKey(id)) {
      _validate(fields);
      _checkpoint();
      _created[id] = fields;
    } else {
      final original = _requireExisting(id);
      if (_deleted.contains(id)) {
        throw StateError('Restore the pending deletion before editing');
      }
      _validate(fields, original: original);
      if (!_updated.containsKey(id) && changeCount >= 200) {
        throw StateError('200 local changes maximum');
      }
      _checkpoint();
      if (fields.sameAs(NativeM37Fields.fromTitle(original))) {
        _updated.remove(id);
      } else {
        _updated[id] = fields;
      }
    }
    notifyListeners();
  }

  void stageDelete(Iterable<String> ids) {
    _ensureValid();
    final selected = ids.toSet();
    if (selected.isEmpty || selected.length > 200) {
      throw const FormatException('Choose 1–200 titles');
    }
    for (final id in selected) {
      if (!_created.containsKey(id)) _requireExisting(id);
    }
    final effective = selected.where((id) =>
      _created.containsKey(id) || !_deleted.contains(id)).toList();
    if (effective.isEmpty) { return; }
    final additional = effective.where((id) => !_created.containsKey(id) &&
      !_updated.containsKey(id)).length;
    if (changeCount + additional > 200) {
      throw StateError('200 local changes maximum');
    }
    _checkpoint();
    for (final id in effective) {
      if (_created.remove(id) != null) { continue; }
      _updated.remove(id);
      _deleted.add(id);
    }
    notifyListeners();
  }

  void restoreDeleted(String id) {
    _ensureValid();
    if (!_deleted.contains(id)) {
      throw StateError('This title has no pending deletion');
    }
    _checkpoint();
    _deleted.remove(id);
    notifyListeners();
  }

  void undo() {
    _ensureValid();
    if (_undo.isEmpty) { return; }
    _redo.add(_capture());
    _restoreRevision(_undo.removeLast());
  }

  void redo() {
    _ensureValid();
    if (_redo.isEmpty) { return; }
    _undo.add(_capture());
    _restoreRevision(_redo.removeLast());
  }

  void discard() {
    _created.clear();
    _updated.clear();
    _deleted.clear();
    _undo.clear();
    _redo.clear();
    if (_latest != null) { _attach(_latest!); }
    notifyListeners();
  }

  NativeM37Fields fieldsFor(String id) {
    _ensureValid();
    if (_created[id] != null) { return _created[id]!; }
    final original = _requireExisting(id);
    return _updated[id] ?? NativeM37Fields.fromTitle(original);
  }

  bool isTemporary(String id) => _created.containsKey(id);
  bool isEdited(String id) => _updated.containsKey(id);
  bool isDeleted(String id) => _deleted.contains(id);

  /// Immutable *view* only. Every cloud title reference remains untouched.
  /// The original catalog is returned when no changes are staged.
  MediaFlowCatalog previewCatalog() {
    _ensureValid();
    if (!hasChanges) { return _base!; }
    final source = _base!;
    final projected = <MediaFlowTitle>[];
    for (final original in source.library) {
      if (_deleted.contains(original.id)) { continue; }
      final edit = _updated[original.id];
      projected.add(edit == null ? original :
          edit.preview(original.id, original: original));
    }
    for (final entry in _created.entries) {
      projected.add(entry.value.preview(entry.key));
    }
    return MediaFlowCatalog(
      categories: source.categories, library: List.unmodifiable(projected),
      sessions: source.sessions, collections: source.collections,
      personalOrderIds: source.personalOrderIds,
      currentTask: source.currentTask, sessionActive: source.sessionActive,
      tasksPerDay: source.tasksPerDay, dailyMinutes: source.dailyMinutes,
      xpEvidence: source.xpEvidence, updatedAt: source.updatedAt,
    );
  }

  /// Unchanged read-only source holds references in related collections,
  /// personal order and past sessions even when a deletion is only staged.
  int references(String id) {
    _ensureValid();
    return _base!.collections.where((c) => c.titleIds.contains(id)).length +
      _base!.personalOrderIds.where((t) => t == id).length +
      _base!.sessions.where((s) =>
        s.titles.any((t) => t.libraryId == id)).length;
  }
}
