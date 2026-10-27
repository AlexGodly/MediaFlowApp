import 'dart:convert';

import '../services/native_snapshot_codec.dart';
import '../services/native_m39_metadata.dart';
import 'mediaflow_models.dart';
import 'mediaflow_state_codec.dart';

/// The *complete* JSONB v410 account payload, not the intentionally lossy
/// MediaFlowCatalog screen projection. Reads and defensive local simulations
/// only: no Supabase transport, persistence, or cloud update operation.
enum MediaFlowWireFormat { jsonObject, jsonString, gzipEnvelope }

class MediaFlowFullState {
  MediaFlowFullState._(
    this._originalWire,
    this._state,
    this.format, {
    required this.isLocalSimulation,
  });

  final Object _originalWire;
  final Map<String, dynamic> _state;
  final MediaFlowWireFormat format;
  final bool isLocalSimulation;

  /// Fail closed: a missing cloud row must never become an empty replacement.
  factory MediaFlowFullState.parse(
    Object? raw, {bool requireCore = true}
  ) {
    if (raw == null || (raw is! Map && raw is! String)) {
      throw const FormatException('Missing or unsupported MediaFlow account snapshot');
    }
    final original = _clone(raw);
    if (original is Map &&
        original.containsKey('__mediaflowCompressed') &&
        original['__mediaflowCompressed'] != 'gzip') {
      throw const FormatException('Unsupported MediaFlow compression');
    }
    final format = original is String
        ? MediaFlowWireFormat.jsonString
        : original is Map && original['__mediaflowCompressed'] == 'gzip'
            ? MediaFlowWireFormat.gzipEnvelope
            : MediaFlowWireFormat.jsonObject;
    final decoded = NativeSnapshotCodec.decode(original);
    _validate(decoded, requireCore: requireCore);
    return MediaFlowFullState._(original, decoded, format,
      isLocalSimulation: false);
  }

  /// A copy of the exact source JSON value, including original compression
  /// envelope metadata if present. Never exposes mutable internal state.
  Object get originalWire => _clone(_originalWire);

  /// All original root keys, nested settings, unknown fields, original dates,
  /// optional fields, ordering and ledger identifiers are retained.
  Map<String, dynamic> get json => NativeSnapshotCodec.deepClone(_state);

  /// Returns an isolated copy of any root, including arrays and opaque roots.
  /// Missing and explicit-null roots are distinguishable with containsRoot().
  Object? root(String key) => _cloneNullable(_state[key]);
  bool containsRoot(String key) => _state.containsKey(key);

  /// Reads, but never flattens or casts away, unknown nested fields.
  Object? at(List<Object> path) => _cloneNullable(_lookup(_state, path));

  /// Existing UI projections remain deliberately read-only and lossy.
  /// The full state must *never* be reconstructed from this catalog.
  MediaFlowCatalog readOnlyCatalog() =>
      decodeMediaFlowState(_state, requireCoreCollections: true);

  MediaFlowStateCoverage inspect() => MediaFlowStateCoverage._(
    roots: _state.keys.toList(growable: false),
    settings: _state['settings'] is Map
        ? (_state['settings'] as Map).keys.map((key) => key.toString()).toList()
        : const [],
    libraryCount: (_state['library'] as List?)?.length ?? 0,
    sessionCount: (_state['sessions'] as List?)?.length ?? 0,
    collectionCount: (_state['collections'] as List?)?.length ?? 0,
    orderTitleCount: _state['orderPlan'] is Map &&
            (_state['orderPlan'] as Map)['titleIds'] is List
        ? ((_state['orderPlan'] as Map)['titleIds'] as List).length : 0,
  );

  /// Reconstructs the payload in its original JSON object/string/gzip form.
  /// Only for local parity tests: do NOT pass this to a Supabase write.
  /// An unchanged source is returned without recompression.
  Object encodeForLocalParityTest() {
    if (!isLocalSimulation) return _clone(_originalWire);
    switch (format) {
      case MediaFlowWireFormat.jsonString:
        return jsonEncode(_state);
      case MediaFlowWireFormat.gzipEnvelope:
        return NativeSnapshotCodec.encodeLike(_state, _originalWire);
      case MediaFlowWireFormat.jsonObject:
        return NativeSnapshotCodec.deepClone(_state);
    }
  }

  /// Pure copy-on-write *simulation*, restricted to an existing scalar leaf.
  /// No collection replacement, unknown-field removal, implicit defaults,
  /// list resizing, XP awarding, or cloud mutation is supported.
  ///
  /// Existing order and all unrelated subtrees are checked after every edit.
  MediaFlowFullState simulateScalarReplacement(
    List<Object> path, Object? nextValue,
  ) {
    if (path.length < 2 || path.length > 48) {
      throw const FormatException('Expected a bounded nested existing field path');
    }
    if (nextValue is Map || nextValue is List ||
        (nextValue != null && nextValue is! String &&
         nextValue is! num && nextValue is! bool) ||
        (nextValue is double && !nextValue.isFinite)) {
      throw const FormatException('Local simulation only supports JSON scalars');
    }
    final clone = NativeSnapshotCodec.deepClone(_state);
    final oldValue = _lookup(clone, path);
    if (oldValue is Map || oldValue is List) {
      throw const FormatException('Cannot replace an object or array');
    }
    if (NativeSnapshotCodec.equivalent(oldValue, nextValue)) {
      throw const FormatException('Simulation must make a real change');
    }
    _setExisting(clone, path, nextValue);
    _validate(clone, requireCore: true);

    // Reverting the single permitted path MUST reconstruct the entire source
    // byte-for-JSON-value canonical state. This catches accidental collateral
    // edits to opaque fields, array ordering, or future v410 schema additions.
    final restored = NativeSnapshotCodec.deepClone(clone);
    _setExisting(restored, path, oldValue);
    if (!NativeSnapshotCodec.equivalent(restored, _state)) {
      throw StateError('Unexpected field loss during local simulation');
    }
    return MediaFlowFullState._(
      _originalWire, clone, format, isLocalSimulation: true,
    );
  }

  /// Creates a complete-state draft for an explicit CAS save. The new root
  /// is restricted to the existing account's resume-state envelope; every
  /// other root is retained byte-for-JSON-value in the decoded payload.
  MediaFlowFullState simulateRootReplacement(
    String key,
    Object nextValue,
  ) {
    if (key != 'resumeStateV285') {
      throw const FormatException('Only the existing v285 resume root is writable here');
    }
    if (nextValue is! Map) {
      throw const FormatException('Resume state must be a JSON object');
    }
    final clone = NativeSnapshotCodec.deepClone(_state);
    clone[key] = NativeSnapshotCodec.deepClone(
      Map<String, dynamic>.from(nextValue),
    );
    _validate(clone, requireCore: true);
    for (final entry in _state.entries) {
      if (entry.key == key) continue;
      if (!NativeSnapshotCodec.equivalent(entry.value, clone[entry.key])) {
        throw StateError('Unexpected account field change during resume save');
      }
    }
    return MediaFlowFullState._(
      _originalWire, clone, format, isLocalSimulation: true,
    );
  }

  /// Encodes a validated local mutation in the account's original wire format.
  /// Only explicitly simulated payloads may be handed to the CAS writer.
  Object encodeForCommit() {
    if (!isLocalSimulation) {
      throw const FormatException('Refusing to write an unmodified cloud snapshot');
    }
    switch (format) {
      case MediaFlowWireFormat.jsonString:
        return jsonEncode(_state);
      case MediaFlowWireFormat.gzipEnvelope:
        return NativeSnapshotCodec.encodeLike(_state, _originalWire);
      case MediaFlowWireFormat.jsonObject:
        return NativeSnapshotCodec.deepClone(_state);
    }
  }

  /// v410-aware **simulation only**, not a cloud save payload.
  /// Copy the full original state and modify only a uniquely identified
  /// Library title's external IDs/manual provenance/season rows.
  /// Untouched fields, season-specific opaque metadata, History and XP retain
  /// their exact original JSON representations.
  MediaFlowFullState simulateTitleMetadata({
    required String titleId,
    Map<String,String?> idChanges = const {},
    List<MediaFlowSeason>? seasons,
  }) {
    if (titleId.isEmpty || (idChanges.isEmpty && seasons == null)) {
      throw const FormatException('Choose a title and metadata changes');
    }
    final library = _state['library'];
    if (library is! List) {
      throw const FormatException('Missing v410 Library');
    }
    final matches = <int>[];
    for (var i = 0; i < library.length; i++) {
      final item = library[i];
      if (item is Map && item['id']?.toString() == titleId) matches.add(i);
    }
    if (matches.length != 1) {
      throw StateError('Missing or duplicate original title ID');
    }
    final index = matches.single;
    final clone = NativeSnapshotCodec.deepClone(_state);
    final rows = clone['library'] as List;
    final record = Map<String,dynamic>.from(rows[index] as Map);
    final originalRecord = NativeSnapshotCodec.deepClone(record);

    if (idChanges.isNotEmpty) {
      final rawIds = record['externalIds'];
      final rawManual = record['v377ManualExternalIds'];
      if (rawIds != null && rawIds is! Map ||
          rawManual != null && rawManual is! Map) {
        throw const FormatException('Unsupported ID metadata shape');
      }
      final ids = <String,String>{
        for (final e in (rawIds as Map? ?? const {}).entries)
          e.key.toString(): e.value.toString(),
      };
      final manual = <String,String?>{
        for (final e in (rawManual as Map? ?? const {}).entries)
          e.key.toString(): e.value?.toString(),
      };
      final result = NativeM39Metadata.applyIdChanges(ids,manual,idChanges);
      record['externalIds'] = Map<String,String>.of(result.ids);
      record['v377ManualExternalIds'] =
          Map<String,String?>.of(result.manual);
      // Deliberately leave legacy malId/mal_id aliases intact in this local
      // test: cloud edits require coordinated v377 alias cleanup.
    }

    if (seasons != null) {
      NativeM39Metadata.validateSeasons(seasons);
      final rawSeasons = record['seasons'];
      if (rawSeasons != null &&
          (rawSeasons is! List || rawSeasons.any((s) => s is! Map))) {
        throw const FormatException('Invalid source seasons');
      }
      final old = (rawSeasons as List? ?? const [])
          .map((e) => Map<String,dynamic>.from(e as Map)).toList();
      if (old.isNotEmpty && seasons.isEmpty) {
        throw const FormatException(
          'Cannot remove every season in an offline simulation');
      }
      final byId = <String,Map<String,dynamic>>{};
      for (final raw in old) {
        final id = raw['id']?.toString() ?? '';
        if (id.isEmpty || byId.containsKey(id)) {
          throw StateError('Ambiguous source season identity');
        }
        byId[id] = raw;
      }
      final oldModels = old.map(MediaFlowSeason.fromJson).toList();
      if (!NativeM39Metadata.sameSeasons(oldModels, seasons)) {
        final updated = <Map<String,dynamic>>[];
        for (final season in seasons) {
          final source = byId[season.id];
          if (source == null && !season.id.startsWith('local-m39-')) {
            throw const FormatException('Unknown season identity');
          }
          final current = source == null ? null :
              MediaFlowSeason.fromJson(source);
          if (current != null &&
              NativeM39Metadata.sameSeasons([current],[season])) {
            updated.add(source!);
          } else {
            updated.add({
              ...?source,
              'id': season.id,
              'name': season.name,
              'number': season.number?.toInt(),
              'progress': season.progress.toInt(),
              'total': season.total?.toInt(),
              'source': season.source.isEmpty ? 'manual' : season.source,
              'manual': season.manual,
              'synthetic': season.synthetic,
            });
          }
        }
        record['seasons'] = updated;
        if (seasons.isNotEmpty) {
          final aggregate = NativeM39Metadata.aggregate(seasons);
          record['progress'] = aggregate.progress.toInt();
          record['total'] = aggregate.total?.toInt();
          record['seasonSource'] = 'manual';
          record['seasonViewEnabled'] = true;
        }
      }
    }
    if (NativeSnapshotCodec.equivalent(record, originalRecord)) {
      throw const FormatException('Metadata patch contains no changes');
    }
    rows[index] = record;
    _validate(clone, requireCore: true);
    final restored = NativeSnapshotCodec.deepClone(clone);
    (restored['library'] as List)[index] = originalRecord;
    if (!NativeSnapshotCodec.equivalent(restored,_state)) {
      throw StateError('Loss of unrelated v410 account fields');
    }
    return MediaFlowFullState._(
      _originalWire, clone, format, isLocalSimulation:true);
  }

  static void _validate(Map<String, dynamic> state,
      {required bool requireCore}) {
    for (final key in ['library', 'categories', 'sessions', 'settings']) {
      if (requireCore && !state.containsKey(key)) {
        throw FormatException('Missing v410 core section: $key');
      }
    }
    for (final key in ['library', 'categories', 'sessions', 'collections']) {
      final value = state[key];
      if (value == null) {
        if (requireCore && key != 'collections') {
          throw FormatException('Missing v410 core collection: $key');
        }
        continue;
      }
      if (value is! List || value.any((element) => element is! Map)) {
        throw FormatException('Invalid v410 record list: $key');
      }
    }
    final settings = state['settings'];
    if ((requireCore && settings is! Map) ||
        (settings != null && settings is! Map)) {
      throw const FormatException('v410 settings must be an object');
    }
    for (final key in ['orderPlan', 'xpLedger', 'currentTask', 'stopwatch']) {
      final value = state[key];
      if (value != null && value is! Map) {
        throw FormatException('Invalid v410 object section: $key');
      }
    }
    final orderPlan = state['orderPlan'];
    if (orderPlan is Map && orderPlan['titleIds'] != null &&
        orderPlan['titleIds'] is! List) {
      throw const FormatException('Invalid Personal Order titleIds');
    }
  }

  static Object _clone(Object value) => jsonDecode(jsonEncode(value)) as Object;
  static Object? _cloneNullable(Object? value) =>
      value == null ? null : _clone(value);

  static Object? _lookup(Map<String, dynamic> state, List<Object> path) {
    if (path.isEmpty) throw const FormatException('Empty JSON path');
    Object? cursor = state;
    for (final segment in path) {
      if (cursor is Map && segment is String) {
        if (!cursor.containsKey(segment)) {
          throw FormatException('Missing JSON path key: $segment');
        }
        cursor = cursor[segment];
      } else if (cursor is List && segment is int &&
          segment >= 0 && segment < cursor.length) {
        cursor = cursor[segment];
      } else {
        throw const FormatException('Invalid JSON path segment or index');
      }
    }
    return cursor;
  }

  static void _setExisting(Map<String, dynamic> state,
      List<Object> path, Object? value) {
    final parent = _lookup(state, path.sublist(0, path.length - 1));
    final leaf = path.last;
    if (parent is Map && leaf is String && parent.containsKey(leaf)) {
      parent[leaf] = value;
    } else if (parent is List && leaf is int &&
        leaf >= 0 && leaf < parent.length) {
      parent[leaf] = value;
    } else {
      throw const FormatException('Refusing insertion or array expansion');
    }
  }
}

/// Observability only: no completion percentage or write authorization.
class MediaFlowStateCoverage {
  MediaFlowStateCoverage._({
    required List<String> roots, required List<String> settings,
    required this.libraryCount, required this.sessionCount,
    required this.collectionCount, required this.orderTitleCount,
  }) : rootKeys = List.unmodifiable(roots),
       settingsKeys = List.unmodifiable(settings),
       unrecognizedRoots = List.unmodifiable(
         roots.where((key) => !knownStateRoots.contains(key)),
       );

  /// Known candidate keys from v410 source audits, NOT a closed schema.
  static const knownStateRoots = <String>{
    'categories', 'categoryOrder', 'library', 'sessions', 'settings',
    'currentTask', 'sessionActive', 'profilePicture', 'stopwatch', 'malLink',
    'xpLedger', 'completionTimeline', 'orderPlan', 'activityLog',
    'collections', 'backup', 'automaticBackup', 'automaticBackup2',
    'level', 'xp', 'achievements', 'history', 'nativeXpEvidence',
  };

  final List<String> rootKeys, settingsKeys, unrecognizedRoots;
  final int libraryCount, sessionCount, collectionCount, orderTitleCount;
}
