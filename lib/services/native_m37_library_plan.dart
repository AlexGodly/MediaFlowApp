import 'dart:math';

import 'package:flutter/foundation.dart';
import '../data/mediaflow_models.dart';
import 'native_m39_metadata.dart';

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
    List<MediaFlowSeason> seasons = const [],
    Map<String,String> externalIds = const {},
    Map<String,String?> manualExternalIds = const {},
    this.seasonSource = '',
  }) : tags = List.unmodifiable(tags),
       seasons = List.unmodifiable(seasons),
       externalIds = Map.unmodifiable(externalIds),
       manualExternalIds = Map.unmodifiable(manualExternalIds);
  final String title, categoryId, status, priority, coverUrl, description;
  final double progress;
  final double? total, rating;
  final List<String> tags;
  final List<MediaFlowSeason> seasons;
  final Map<String,String> externalIds;
  final Map<String,String?> manualExternalIds;
  final String seasonSource;

  factory NativeM37Fields.fromTitle(MediaFlowTitle title) =>
      NativeM37Fields(
        title: title.title, categoryId: title.categoryId,
        status: title.status, priority: title.priority,
        progress: title.progress, total: title.total, rating: title.rating,
        coverUrl: title.coverUrl, description: title.description,
        tags: title.tags, seasons: title.seasons,
        externalIds: title.externalIds,
        manualExternalIds: title.manualExternalIds,
        seasonSource: title.seasonSource,
      );

  bool sameAs(NativeM37Fields other) =>
      title == other.title && categoryId == other.categoryId &&
      status == other.status && priority == other.priority &&
      progress == other.progress && total == other.total &&
      rating == other.rating && coverUrl == other.coverUrl &&
      description == other.description &&
      listEquals(tags, other.tags) &&
      NativeM39Metadata.sameSeasons(seasons, other.seasons) &&
      mapEquals(externalIds, other.externalIds) &&
      mapEquals(manualExternalIds, other.manualExternalIds) &&
      seasonSource == other.seasonSource;

  MediaFlowTitle preview(String id, {MediaFlowTitle? original}) =>
      MediaFlowTitle(
        id: id, title: title, categoryId: categoryId, status: status,
        priority: priority, progress: progress, total: total, rating: rating,
        coverUrl: coverUrl, tags: tags,
        seasons: seasons,
        externalIds: externalIds,
        manualExternalIds: manualExternalIds,
        seasonSource: seasonSource,
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
  int _revision = 0;
  int get revision => _revision;
  int _cachedRevision = -1;
  MediaFlowCatalog? _cachedProjection;
  void _changed() {
    _revision++;
    _cachedRevision = -1;
    _cachedProjection = null;
    notifyListeners();
  }

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
          fields.total! < 0 ||
          (fields.seasons.isEmpty && fields.progress > fields.total!))) ||
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
    NativeM39Metadata.validateIds(
      fields.externalIds, fields.manualExternalIds);
    NativeM39Metadata.validateSeasons(fields.seasons);
    if (fields.seasons.isNotEmpty) {
      final aggregate = NativeM39Metadata.aggregate(fields.seasons);
      if (fields.progress != aggregate.progress ||
          fields.total != aggregate.total) {
        throw const FormatException('Season aggregate must match season rows');
      }
    }
    if (original != null && original.seasons.isNotEmpty &&
        NativeM39Metadata.sameSeasons(fields.seasons, original.seasons) &&
        (fields.progress != original.progress ||
         fields.total != original.total)) {
      throw const FormatException(
        'Edit individual seasons to change aggregate progress');
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
    _changed();
  }

  void create(NativeM37Fields fields) {
    _validate(fields);
    if (changeCount >= 200) { throw StateError('200 local changes maximum'); }
    _checkpoint();
    final id = 'local_m37_${++_sequence}_${_random.nextInt(1<<32).toRadixString(16)}';
    _created[id] = fields;
    _changed();
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
    _changed();
  }

  /// Milestone 38: one validated, undoable local-only metadata action.
  /// No implicit progress/status side effects, write transport, or XP events.
  /// All selected IDs and field values are checked before the first mutation.
  void batchEdit(Iterable<String> ids, {
    String? categoryId, String? status, String? priority,
    List<String> addTags = const [],
  }) {
    _ensureValid();
    final selected = ids.toSet();
    if (selected.isEmpty || selected.length > 200) {
      throw const FormatException('Choose 1–200 titles');
    }
    if (categoryId == null && status == null && priority == null &&
        addTags.isEmpty) {
      throw const FormatException('Choose at least one metadata change');
    }
    if (addTags.any((tag) => tag.trim().isEmpty ||
        tag.trim().length > 100)) {
      throw const FormatException('Invalid tag to add');
    }
    final pendingCreated = <String, NativeM37Fields>{};
    final pendingUpdated = <String, NativeM37Fields>{};
    final removeUnchanged = <String>{};
    for (final id in selected) {
      final local = _created[id];
      final original = local == null ? _requireExisting(id) : null;
      if (_deleted.contains(id)) {
        throw StateError('Restore pending deletions before batch editing');
      }
      final before = local ?? _updated[id] ??
          NativeM37Fields.fromTitle(original!);
      final tags = List<String>.of(before.tags);
      final knownTags = tags.map((tag) => tag.toLowerCase()).toSet();
      for (final tag in addTags) {
        final normalized = tag.trim();
        if (knownTags.add(normalized.toLowerCase())) tags.add(normalized);
      }
      final after = NativeM37Fields(
        title: before.title,
        categoryId: categoryId ?? before.categoryId,
        status: status ?? before.status,
        priority: priority ?? before.priority,
        progress: before.progress, total: before.total,
        rating: before.rating, coverUrl: before.coverUrl,
        description: before.description, tags: tags,
        seasons: before.seasons,
        externalIds: before.externalIds,
        manualExternalIds: before.manualExternalIds,
        seasonSource: before.seasonSource,
      );
      _validate(after, original: original);
      if (after.sameAs(before)) continue;
      if (local != null) {
        pendingCreated[id] = after;
      } else if (after.sameAs(NativeM37Fields.fromTitle(original!))) {
        removeUnchanged.add(id);
      } else {
        pendingUpdated[id] = after;
      }
    }
    if (pendingCreated.isEmpty && pendingUpdated.isEmpty &&
        removeUnchanged.isEmpty) { return; }
    final newChanges = pendingUpdated.keys.where(
        (id) => !_updated.containsKey(id)).length;
    if (changeCount + newChanges > 200) {
      throw StateError('200 local changes maximum');
    }
    _checkpoint();
    _created.addAll(pendingCreated);
    _updated.addAll(pendingUpdated);
    for (final id in removeUnchanged) {
      _updated.remove(id);
    }
    _changed();
  }

  /// Typed local-only external ID and season edit. Existing extra fields,
  /// tags, cover and priority remain projected unchanged; no cloud write.
  void editM39(String id, {
    Map<String,String?> idChanges = const {},
    List<MediaFlowSeason>? seasons,
  }) {
    _ensureValid();
    final old = fieldsFor(id);
    final changedIds = NativeM39Metadata.applyIdChanges(
      old.externalIds, old.manualExternalIds, idChanges);
    final nextSeasons = seasons ?? old.seasons;
    NativeM39Metadata.validateSeasons(nextSeasons);
    // Removing all seasons cannot infer the intended title-wide counters.
    // Explicit removal needs the complete website side-effect protocol.
    if (old.seasons.isNotEmpty && nextSeasons.isEmpty) {
      throw const FormatException(
        'Removing all seasons requires website-equivalent state recovery');
    }
    final aggregate = nextSeasons.isEmpty ? null :
        NativeM39Metadata.aggregate(nextSeasons);
    final next = NativeM37Fields(
      title: old.title, categoryId: old.categoryId, status: old.status,
      priority: old.priority,
      progress: aggregate?.progress ?? old.progress,
      total: aggregate?.total ?? old.total,
      rating: old.rating, coverUrl: old.coverUrl,
      description: old.description, tags: old.tags,
      seasons: nextSeasons, externalIds: changedIds.ids,
      manualExternalIds: changedIds.manual,
      seasonSource: seasons == null ? old.seasonSource : 'manual',
    );
    if (next.sameAs(old)) return;
    edit(id, next);
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
    _changed();
  }

  void restoreDeleted(String id) {
    _ensureValid();
    if (!_deleted.contains(id)) {
      throw StateError('This title has no pending deletion');
    }
    _checkpoint();
    _deleted.remove(id);
    _changed();
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
    _changed();
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
    if (_cachedProjection != null && _cachedRevision == _revision) {
      return _cachedProjection!;
    }
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
    final result = MediaFlowCatalog(
      categories: source.categories, library: List.unmodifiable(projected),
      sessions: source.sessions, collections: source.collections,
      personalOrderIds: source.personalOrderIds,
      currentTask: source.currentTask, sessionActive: source.sessionActive,
      tasksPerDay: source.tasksPerDay, dailyMinutes: source.dailyMinutes,
      xpEvidence: source.xpEvidence, updatedAt: source.updatedAt,
    );
    _cachedProjection = result;
    _cachedRevision = _revision;
    return result;
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
