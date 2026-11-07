// A replayable account edit made on this device (Library, History, Collections,
// Personal Order, settings…).
//
// The app performs an edit the way the website does — on a copy of the account,
// with the website's own logic and side effects (rewards, Library History,
// completion timeline…) — and records the difference as small changes, each
// with the value it replaced. On a newer cloud copy the changes are replayed:
//   • set     – a value; if someone else changed it since, the newer change
//               wins (the element's modifiedAt decides); other fields are kept
//   • insert  – an element of an id'd list; skipped if it already exists
//   • remove  – an element of an id'd list; kept if it was changed after this
//   • order   – the order of an id'd list (unknown elements keep their place)
//   • add/del – an element of a list without ids (completion timeline…)
//
// Paths are lists of keys; `#<id>` selects the element of a list whose id is <id>.

import 'dart:convert';

import '../logic/leveling.dart';
import '../state/lazy_copy.dart';
import '../util/js.dart';
import 'account_ops.dart';

Object? _clone(Object? v) => v == null ? null : jsonClone(v);
String _json(Object? v) => jsonEncode(v);

class Change {
  Change(this.t, this.path, this.value, this.prev, [this.index]);

  final String t; // set (null value: remove the field) | null (set the field to null) | insert | remove | order | add | del
  final List<String> path;
  final Object? value;
  final Object? prev;
  final int? index;

  Map<String, dynamic> toJson() => {'t': t, 'path': path, 'value': value, 'prev': prev, if (index != null) 'index': index};

  static Change fromJson(Map<String, dynamic> j) => Change(
        jsStr(j['t']).isEmpty ? 'set' : jsStr(j['t']),
        asList(j['path']).map(jsStr).toList(),
        j['value'],
        j['prev'],
        j['index'] == null ? null : jsNum(j['index']).toInt(),
      );

  /// The change that undoes this one.
  Change inverse() => switch (t) {
        'insert' => Change('remove', path, jsStr(asMap(value)?['id']), value, index),
        'remove' => Change('insert', path, prev, null, index),
        'add' => Change('del', path, value, null),
        'del' => Change('add', path, value, null),
        'order' => Change('order', path, prev, value),
        'null' => Change('set', path, prev, null),
        _ => Change('set', path, prev, value),
      };
}

Object? _child(Object? node, String key) {
  if (node == null) return null;
  if (key.startsWith('#')) {
    if (node is! List) return null;
    final id = key.substring(1);
    for (final e in node) {
      if (e is Map && jsStr(e['id']) == id) return e;
    }
    return null;
  }
  return node is Map ? node[key] : null;
}

Object? readPath(Object? root, List<String> path) {
  Object? node = root;
  for (final k in path) {
    node = _child(node, k);
    if (node == null) return null;
  }
  return node;
}

/// The parent container of [path] (maps are created on the way).
Map? _parent(Map<String, dynamic> root, List<String> path) {
  Object node = root;
  for (var i = 0; i < path.length - 1; i++) {
    final k = path[i];
    var next = _child(node, k);
    if (next == null && !k.startsWith('#') && node is Map) {
      next = <String, dynamic>{};
      node[k] = next;
    }
    if (next == null) return null;
    node = next;
  }
  return node is Map ? node : null;
}

List<dynamic>? _list(Map<String, dynamic> root, List<String> path, {bool create = false}) {
  final v = readPath(root, path);
  if (v is List) return v;
  if (!create || v != null) return null;
  final p = _parent(root, path);
  if (p == null) return null;
  final l = <dynamic>[];
  p[path.last] = l;
  return l;
}

/// Newest element stamp along [path] (for "newest change wins").
double _stamp(Map<String, dynamic> root, List<String> path) {
  Object? node = root;
  double stamp = 0;
  for (final k in path) {
    node = _child(node, k);
    if (node == null) break;
    if (node is Map) {
      final s = jsNum(node['modifiedAt'] ?? node['updatedAt']);
      if (s > 0) stamp = s;
    }
  }
  return stamp;
}

/// Whether the field at [path] exists (possibly with the value null).
bool _has(Map<String, dynamic> root, List<String> path) {
  final parent = path.length == 1 ? root : readPath(root, path.sublist(0, path.length - 1));
  return parent is Map && parent.containsKey(path.last);
}

bool applyChange(Map<String, dynamic> state, Change c, int createdAt) {
  switch (c.t) {
    case 'insert':
      final item = asMap(c.value);
      final list = _list(state, c.path, create: true);
      if (item == null || list == null) return false;
      final id = jsStr(item['id']);
      if (id.isNotEmpty && list.any((e) => e is Map && jsStr(e['id']) == id)) return false;
      list.insert((c.index ?? list.length).clamp(0, list.length), _clone(item));
      return true;
    case 'remove':
      final list = _list(state, c.path);
      if (list == null) return false;
      final i = list.indexWhere((e) => e is Map && jsStr(e['id']) == jsStr(c.value));
      if (i < 0) return false;
      final cur = list[i];
      if (cur is Map && c.prev != null && !_deepEq(cur, c.prev) && jsNum(cur['modifiedAt'] ?? cur['updatedAt']) > createdAt) {
        return false; // changed elsewhere after this device removed it
      }
      list.removeAt(i);
      return true;
    case 'order':
      final list = _list(state, c.path);
      if (list == null) return false;
      final want = asList(c.value).map(jsStr).toList();
      final pos = {for (var i = 0; i < want.length; i++) want[i]: i};
      final known = [for (final e in list) if (e is Map && pos.containsKey(jsStr(e['id']))) e];
      known.sort((a, b) => pos[jsStr(a['id'])]!.compareTo(pos[jsStr(b['id'])]!));
      var k = 0;
      final next = [for (final e in list) (e is Map && pos.containsKey(jsStr(e['id']))) ? known[k++] : e];
      if (_deepEq(next, list)) return false;
      list
        ..clear()
        ..addAll(next);
      return true;
    case 'add':
      final list = _list(state, c.path, create: true);
      if (list == null || list.any((e) => _deepEq(e, c.value))) return false;
      list.add(_clone(c.value));
      return true;
    case 'del':
      final list = _list(state, c.path);
      if (list == null) return false;
      final i = list.indexWhere((e) => _deepEq(e, c.value));
      if (i < 0) return false;
      list.removeAt(i);
      return true;
    default: // 'set', and 'null' (the field stays, with the value null)
      final keepNull = c.t == 'null';
      final cur = readPath(state, c.path);
      if (c.value == null && !keepNull ? !_has(state, c.path) : _deepEq(cur, c.value) && (cur != null || _has(state, c.path))) {
        return false;
      }
      if (!_deepEq(cur, c.prev) && _stamp(state, c.path.sublist(0, c.path.length - 1)) > createdAt) return false;
      final p = _parent(state, c.path);
      if (p == null) return false;
      if (c.value == null && !keepNull) {
        p.remove(c.path.last);
      } else {
        p[c.path.last] = _clone(c.value);
      }
      return true;
  }
}

class EditOp extends AccountOp {
  EditOp({
    required this.id,
    required this.createdAt,
    required this.changes,
    this.label = '',
    this.annotateStreaks = false,
  });

  @override
  final String id;
  final int createdAt;
  final List<Change> changes;

  /// What this edit did ("Edited Title", "Deleted 3 History entries"…), for undo.
  final String label;

  /// Re-annotates History streak XP after replay (History edits).
  final bool annotateStreaks;

  @override
  String get kind => 'edit';

  @override
  bool apply(Map<String, dynamic> state) {
    var changed = false;
    for (final c in changes) {
      if (applyChange(state, c, createdAt)) changed = true;
    }
    if (!changed) return false;
    if (annotateStreaks) annotateStreakXP(state, Leveling(state));
    if (createdAt > jsNum(state['savedAt'])) state['savedAt'] = createdAt;
    return true;
  }

  @override
  Map<String, dynamic> toJson() => {
        'kind': kind,
        'id': id,
        'createdAt': createdAt,
        'changes': [for (final c in changes) c.toJson()],
        'label': label,
        'annotateStreaks': annotateStreaks,
      };

  static EditOp fromJson(Map<String, dynamic> j) => EditOp(
        id: jsStr(j['id']),
        createdAt: jsNum(j['createdAt']).toInt(),
        changes: [for (final c in asList(j['changes'])) Change.fromJson(asMap(c) ?? const {})],
        label: jsStr(j['label']),
        annotateStreaks: j['annotateStreaks'] == true,
      );
}

/// The changes that turn [a] into [b] (see the header for the kinds).
/// Structural equality (no JSON text): fast, and 1 equals 1.0 like in JSON numbers.
bool _deepEq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  // An untouched copy-on-write part is the original (see lazy_copy.dart).
  if (b is CowValue && identical(b.source, a) && b.pristine) return true;
  if (a is CowValue && identical(a.source, b) && a.pristine) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || !_deepEq(e.value, b[e.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

List<Change> diffStates(Map<String, dynamic> a, Map<String, dynamic> b) {
  final out = <Change>[];
  late final void Function(List<String> path, Object? x, Object? y) diff;

  // One field of a map: null-valued and missing fields are told apart, like
  // in the saved JSON (the website writes `field: null`).
  void field(List<String> parent, Map x, bool yHas, Object? yv, String k) {
    final path = [...parent, k];
    final xHas = x.containsKey(k);
    final xv = x[k];
    if (yHas && yv == null) {
      if (!xHas || xv != null) out.add(Change('null', path, null, _clone(xv)));
      return;
    }
    if (!yHas) {
      if (xHas) out.add(Change('set', path, null, _clone(xv)));
      return;
    }
    diff(path, xv, yv);
  }

  diff = (List<String> path, Object? x, Object? y) {
    // Equal parts (most of them) are skipped without building any paths.
    if (identical(x, y) || _deepEq(x, y)) return;
    if (x is Map && y is Map) {
      for (final k in <String>{...x.keys.map((e) => '$e'), ...y.keys.map((e) => '$e')}) {
        field(path, x, y.containsKey(k), y[k], k);
      }
      return;
    }
    if (x is List && y is List && path.isNotEmpty) {
      bool idList(List l) => l.every((e) => e is Map && jsStr(e['id']).isNotEmpty);
      if (idList(x) && idList(y) && (x.isNotEmpty || y.isNotEmpty)) {
        final xi = {for (final e in x) jsStr((e as Map)['id']): e};
        final yi = {for (var i = 0; i < y.length; i++) jsStr((y[i] as Map)['id']): i};
        if (xi.length == x.length && yi.length == y.length) {
          for (final id in xi.keys) {
            if (!yi.containsKey(id)) out.add(Change('remove', path, id, _clone(xi[id]), x.indexOf(xi[id])));
          }
          for (var i = 0; i < y.length; i++) {
            final e = y[i] as Map;
            final id = jsStr(e['id']);
            if (!xi.containsKey(id)) {
              out.add(Change('insert', path, _clone(e), null, i));
            } else {
              diff([...path, '#$id'], xi[id], e);
            }
          }
          final before = [for (final e in x) if (yi.containsKey(jsStr((e as Map)['id']))) jsStr(e['id'])];
          final after = [for (final e in y) if (xi.containsKey(jsStr((e as Map)['id']))) jsStr(e['id'])];
          if (!_deepEq(before, after)) out.add(Change('order', path, after, before));
          return;
        }
      }
      if (x.every((e) => e is Map) && y.every((e) => e is Map) && path.last != 'titles') {
        final xs = x.map(_json).toList(), ys = y.map(_json).toList();
        final remaining = List.of(xs);
        for (var i = 0; i < y.length; i++) {
          final at = remaining.indexOf(ys[i]);
          if (at >= 0) {
            remaining.removeAt(at);
          } else {
            out.add(Change('add', path, _clone(y[i]), null));
          }
        }
        for (final r in remaining) {
          out.add(Change('del', path, jsonDecode(r), null));
        }
        return;
      }
    }
    out.add(Change(y == null ? 'null' : 'set', path, _clone(y), _clone(x)));
  };

  // A LazyStateCopy only differs where the edit touched it.
  if (b is LazyStateCopy && identical(b.original, a)) {
    for (final k in b.touched) {
      if (k == 'savedAt') continue;
      field(const [], a, b.containsKey(k), b.peek(k), k);
    }
    return out;
  }
  for (final k in <String>{...a.keys, ...b.keys}) {
    if (k == 'savedAt') continue;
    field(const [], a, b.containsKey(k), b[k], k);
  }
  return out;
}

/// An edit op from the original account and the edited copy.
EditOp? editFromStates(Map<String, dynamic> original, Map<String, dynamic> edited,
    {required int now, String label = '', bool annotateStreaks = false}) {
  final changes = diffStates(original, edited);
  if (changes.isEmpty) return null;
  return EditOp(id: mediaFlowUid(now), createdAt: now, changes: changes, label: label, annotateStreaks: annotateStreaks);
}
