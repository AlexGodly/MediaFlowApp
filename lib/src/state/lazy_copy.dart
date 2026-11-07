// A copy of the account for an edit that only copies what the edit touches.
//
// An edit runs the website's logic on a copy of the account and saves the
// difference. With large accounts (tens of megabytes) copying and comparing
// everything takes seconds, while an edit usually changes a few parts (the
// Library, the XP ledger, Library History…). Here each top-level part is copied
// the first time the edit reads it; parts it never reads are never copied, and
// cannot have changed, so they need no comparing either.

import 'dart:collection';

import '../util/js.dart';

class LazyStateCopy extends MapBase<String, dynamic> {
  LazyStateCopy(this.original);

  /// The account being edited. Never changed through this copy.
  final Map<String, dynamic> original;
  final Map<String, dynamic> _own = {};
  final Set<String> _removed = {};

  /// Top-level parts this copy has copied, written or removed.
  Set<String> get touched => {..._own.keys, ..._removed};

  bool isTouched(String key) => _own.containsKey(key) || _removed.contains(key);

  /// The current value of [key] without copying it. Only for reading: the
  /// result may be the original account's own data.
  Object? peek(String key) {
    if (_own.containsKey(key)) return _own[key];
    if (_removed.contains(key)) return null;
    return original[key];
  }

  @override
  dynamic operator [](Object? key) {
    if (key is! String) return null;
    if (_own.containsKey(key)) return _own[key];
    if (_removed.contains(key) || !original.containsKey(key)) return null;
    // Copy-on-write: nothing is copied until the edit writes to it, so a
    // Library of 100,000 titles costs nothing when one title changes.
    final copy = cowWrap(original[key]);
    _own[key] = copy;
    return copy;
  }

  @override
  void operator []=(String key, dynamic value) {
    _removed.remove(key);
    _own[key] = value;
  }

  @override
  dynamic remove(Object? key) {
    if (key is! String || !containsKey(key)) return null;
    final value = this[key];
    _own.remove(key);
    if (original.containsKey(key)) _removed.add(key);
    return value;
  }

  @override
  void clear() {
    for (final k in keys.toList()) {
      remove(k);
    }
  }

  @override
  bool containsKey(Object? key) =>
      key is String && (_own.containsKey(key) || (!_removed.contains(key) && original.containsKey(key)));

  @override
  Iterable<String> get keys => {
        for (final k in original.keys)
          if (!_removed.contains(k)) k,
        ..._own.keys,
      };
}

/// [state]'s top-level [key] for reading only (no copy made for a
/// [LazyStateCopy]; the result must not be changed).
Object? readOnlyPart(Map<String, dynamic> state, String key) => state is LazyStateCopy ? state.peek(key) : state[key];

/// All of [state]'s top-level parts for reading only (see [readOnlyPart]).
Map<String, dynamic> readOnlyView(Map<String, dynamic> state) =>
    state is LazyStateCopy ? {for (final k in state.keys) k: state.peek(k)} : state;

// ---- copy-on-write parts ------------------------------------------------------

/// A copy-on-write view of JSON data from the account. Reading gives the
/// original values (nested maps and lists wrapped the same way); writing
/// changes only this view. The original is never changed.
abstract class CowValue {
  Object get source;

  /// Nothing was written through this view (or any view inside it).
  bool get pristine;

  /// A plain copy of the current value that shares unchanged parts with the
  /// original (for "before" snapshots; must not be changed).
  Object? snapshot();
}

Object? cowWrap(Object? v) => v is CowValue ? v : (v is Map ? CowMap(v) : (v is List ? CowList(v) : v));

Object? _snap(Object? v) => v is CowValue ? v.snapshot() : v;

class CowMap extends MapBase<String, dynamic> implements CowValue {
  CowMap(this.source);

  @override
  final Map source;
  Map<String, dynamic>? _own; // written values and wrapped originals
  Set<String>? _removed;
  Set<String>? _appended; // keys that now come after the original's keys
  bool _dirty = false;

  @override
  dynamic operator [](Object? key) {
    if (key is! String) return null;
    final own = _own;
    if (own != null && own.containsKey(key)) return own[key];
    if (_removed?.contains(key) == true || !source.containsKey(key)) return null;
    final v = source[key];
    if (v is Map || v is List) {
      final w = cowWrap(v);
      (_own ??= {})[key] = w;
      return w;
    }
    return v;
  }

  @override
  void operator []=(String key, dynamic value) {
    _dirty = true;
    final inSource = source.containsKey(key);
    // Like a plain map: a removed key that comes back moves to the end.
    if (_removed?.remove(key) == true || !inSource) (_appended ??= <String>{}).add(key);
    (_own ??= {})[key] = value;
  }

  @override
  dynamic remove(Object? key) {
    if (key is! String || !containsKey(key)) return null;
    final value = this[key];
    _dirty = true;
    _own?.remove(key);
    _appended?.remove(key);
    if (source.containsKey(key)) (_removed ??= <String>{}).add(key);
    return value;
  }

  @override
  void clear() {
    for (final k in keys.toList()) {
      remove(k);
    }
  }

  @override
  bool containsKey(Object? key) {
    if (key is! String) return false;
    if (_own?.containsKey(key) == true) return true;
    return _removed?.contains(key) != true && source.containsKey(key);
  }

  @override
  Iterable<String> get keys {
    final removed = _removed, appended = _appended;
    if (removed == null && appended == null) return source.keys.map((k) => k is String ? k : '$k');
    return [
      for (final k in source.keys)
        if (!(removed?.contains('$k') ?? false) && !(appended?.contains('$k') ?? false)) k is String ? k : '$k',
      ...?appended,
    ];
  }

  @override
  int get length => (_removed == null && _appended == null) ? source.length : keys.length;

  @override
  bool get pristine {
    if (_dirty) return false;
    final own = _own;
    if (own == null) return true;
    for (final v in own.values) {
      if (v is! CowValue || !v.pristine) return false;
    }
    return true;
  }

  @override
  Object? snapshot() {
    if (pristine) return source;
    return <String, dynamic>{for (final k in keys) k: _snap(this[k])};
  }
}

class CowList extends ListBase<dynamic> implements CowValue {
  CowList(this.source) : _items = List<dynamic>.of(source);

  @override
  final List source;
  final List<dynamic> _items;
  Set<Object>? _originals;
  bool _dirty = false;

  bool _isOriginal(Object v) => (_originals ??= Set<Object>.identity()..addAll(source.whereType<Object>())).contains(v);

  @override
  int get length => _items.length;

  @override
  set length(int n) {
    _dirty = true;
    _items.length = n;
  }

  @override
  dynamic operator [](int index) {
    final v = _items[index];
    if ((v is Map || v is List) && v is! CowValue && _isOriginal(v as Object)) {
      final w = cowWrap(v);
      _items[index] = w;
      return w;
    }
    return v;
  }

  @override
  void operator []=(int index, dynamic value) {
    _dirty = true;
    _items[index] = value;
  }

  @override
  void add(dynamic element) {
    _dirty = true;
    _items.add(element);
  }

  @override
  void addAll(Iterable<dynamic> iterable) {
    _dirty = true;
    _items.addAll(iterable);
  }

  @override
  bool get pristine {
    if (_dirty || _items.length != source.length) return false;
    for (var i = 0; i < _items.length; i++) {
      final v = _items[i];
      if (identical(v, source[i])) continue;
      if (v is CowValue && identical(v.source, source[i]) && v.pristine) continue;
      return false;
    }
    return true;
  }

  @override
  Object? snapshot() {
    if (pristine) return source;
    return <dynamic>[
      for (final v in _items)
        v is CowValue
            ? v.snapshot()
            : (v is Map || v is List)
                ? (_isOriginal(v as Object) ? v : jsonClone(v))
                : v,
    ];
  }
}
