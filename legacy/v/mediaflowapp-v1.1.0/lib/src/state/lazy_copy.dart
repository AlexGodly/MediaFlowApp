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
    final copy = jsonClone(original[key]);
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
