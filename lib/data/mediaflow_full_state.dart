import 'dart:convert';

import '../services/native_snapshot_codec.dart';
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
