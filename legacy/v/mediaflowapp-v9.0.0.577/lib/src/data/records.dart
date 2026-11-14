// The website's per-record cloud storage (v556, `public.mediaflow_records`):
// the account as one row per title, History log, activity entry, collection
// and settings/XP section. A save sends only the rows that changed; another
// device fetches only rows changed since its last sync.
//
// This file is a straight port of the website's pure parts —
// `mf556Decompose`, `mf556Compose`, `mf556Positions`, `mf556Hash` — so the app
// writes exactly the rows the website writes (`test/records_golden_test.dart`
// checks them against the website's own code).

import 'dart:convert';

const String kRecordTable = 'mediaflow_records';
const List<String> kRecordArrays = ['library', 'sessions', 'activityLog', 'collections'];
const String _sep = '\u001f';

/// One record: `kind`, `record_id`, `pos` (array order) and the exact JSON text.
class Rec {
  const Rec(this.k, this.i, this.pos, this.j);
  final String k, i;
  final double? pos;
  final String j;

  String get key => recordKey(k, i);
}

String recordKey(String k, String i) => '$k\u0001$i';

/// A row as the cloud returns it.
class RecordRow {
  RecordRow({required this.kind, required this.recordId, this.pos, this.data, this.deleted = false, this.updatedAt = ''});
  final String kind, recordId;
  final double? pos;
  final String? data;
  final bool deleted;
  final String updatedAt;

  factory RecordRow.fromJson(Map<String, dynamic> m) => RecordRow(
        kind: '${m['kind'] ?? ''}',
        recordId: '${m['record_id'] ?? ''}',
        pos: m['pos'] is num ? (m['pos'] as num).toDouble() : null,
        data: m['data'] is String ? m['data'] as String : null,
        deleted: m['deleted'] == true,
        updatedAt: '${m['updated_at'] ?? ''}',
      );
}

// ---- JSON text exactly as JavaScript's JSON.stringify writes it ------------

/// `JSON.stringify(value)`: whole-number doubles have no ".0", NaN and
/// Infinity become null. Strings and key order are written as given.
String jsStringify(Object? value) {
  final out = StringBuffer();
  _write(out, value);
  return out.toString();
}

void _write(StringBuffer out, Object? v) {
  if (v == null) {
    out.write('null');
  } else if (v is String) {
    out.write(jsonEncode(v));
  } else if (v is bool) {
    out.write(v ? 'true' : 'false');
  } else if (v is int) {
    out.write(v);
  } else if (v is double) {
    out.write(jsNumberText(v));
  } else if (v is List) {
    out.write('[');
    for (var n = 0; n < v.length; n++) {
      if (n > 0) out.write(',');
      _write(out, v[n]);
    }
    out.write(']');
  } else if (v is Map) {
    out.write('{');
    var first = true;
    v.forEach((key, value) {
      if (!first) out.write(',');
      first = false;
      out.write(jsonEncode('$key'));
      out.write(':');
      _write(out, value);
    });
    out.write('}');
  } else {
    out.write(jsonEncode(v));
  }
}

/// A number as JavaScript prints it (`String(n)`): 1024, 1536.5, 1e+21, null for NaN.
String jsNumberText(num v) {
  if (v is int) return '$v';
  if (v.isNaN || v.isInfinite) return 'null';
  if (v == v.truncateToDouble() && v.abs() < 1e21) return v.toInt().toString();
  return v.toString();
}

// ---- mf556Hash (cyrb53) -------------------------------------------------------

int _imul(int a, int b) {
  final r = ((a & 0xffffffff) * (b & 0xffffffff)) & 0xffffffff;
  return r >= 0x80000000 ? r - 0x100000000 : r;
}

int _u(int x) => x & 0xffffffff;
int _i32(int x) {
  final r = x & 0xffffffff;
  return r >= 0x80000000 ? r - 0x100000000 : r;
}

/// The website's 53-bit string hash, as base-36 text.
String recordHash(String str) {
  var h1 = _i32(0xdeadbeef), h2 = _i32(0x41c6ce57);
  for (var i = 0; i < str.length; i++) {
    final ch = str.codeUnitAt(i);
    h1 = _imul(h1 ^ ch, 2654435761);
    h2 = _imul(h2 ^ ch, 1597334677);
  }
  h1 = _i32(_imul(h1 ^ (_u(h1) >> 16), 2246822507) ^ _imul(h2 ^ (_u(h2) >> 13), 3266489909));
  h2 = _i32(_imul(h2 ^ (_u(h2) >> 16), 2246822507) ^ _imul(h1 ^ (_u(h1) >> 13), 3266489909));
  return (4294967296 * (2097151 & h2) + _u(h1)).toRadixString(36);
}

/// `h` for a record: hash of its JSON text and position.
String recHash(String j, double? pos) => recordHash('$j|${pos == null ? '' : jsNumberText(pos)}');

// ---- mf556Positions --------------------------------------------------------------

/// Keeps the position of every element whose relative order is unchanged
/// (longest increasing run) and gives new or moved ones positions between their
/// neighbours, so appending or editing never moves other records.
List<double> recordPositions(List<String> ids, Map<String, double> prev) {
  final n = ids.length;
  final old = [for (final id in ids) prev[id]];
  final tails = <double>[], tailIdx = <int>[];
  final parent = List<int>.filled(n, -1);
  for (var i = 0; i < n; i++) {
    final v = old[i];
    if (v == null) continue;
    var lo = 0, hi = tails.length;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      if (tails[m] < v) {
        lo = m + 1;
      } else {
        hi = m;
      }
    }
    if (lo == tails.length) {
      tails.add(v);
      tailIdx.add(i);
    } else {
      tails[lo] = v;
      tailIdx[lo] = i;
    }
    parent[i] = lo > 0 ? tailIdx[lo - 1] : -1;
  }
  final keep = <int>{};
  for (var i = tails.isEmpty ? -1 : tailIdx[tails.length - 1]; i >= 0; i = parent[i]) {
    keep.add(i);
  }
  final pos = List<double>.filled(n, 0);
  var i = 0;
  while (i < n) {
    if (keep.contains(i)) {
      pos[i] = old[i]!;
      i++;
      continue;
    }
    var j = i;
    while (j < n && !keep.contains(j)) {
      j++;
    }
    final double? lo = i > 0 ? pos[i - 1] : null;
    final double? hi = j < n ? old[j] : null;
    final count = j - i;
    for (var t = 0; t < count; t++) {
      if (lo == null && hi == null) {
        pos[i + t] = (i + t) * 1024.0;
      } else if (lo == null) {
        pos[i + t] = hi! - (count - t) * 1024;
      } else if (hi == null) {
        pos[i + t] = lo + (t + 1) * 1024;
      } else {
        pos[i + t] = lo + (hi - lo) * (t + 1) / (count + 1);
      }
    }
    i = j;
  }
  for (var k = 0; k < n; k++) {
    if (!keep.contains(k)) pos[k] = _jsRound(pos[k] * 1e4) / 1e4;
  }
  for (var k = 1; k < n; k++) {
    if (!(pos[k] > pos[k - 1]) || pos[k] - pos[k - 1] < 2e-4) {
      for (var m = 0; m < n; m++) {
        pos[m] = m * 1024.0;
      }
      break;
    }
  }
  return pos;
}

/// JavaScript's Math.round (halves round up, also for negatives).
double _jsRound(double v) => (v + 0.5).floorToDouble();

bool _arrayHasIds(Object? arr) {
  if (arr is! List) return false;
  final seen = <String>{};
  for (final el in arr) {
    if (el is! Map) return false;
    final id = el['id'];
    if (id is! String && id is! num) return false;
    final s = id is num ? jsNumberText(id) : id as String;
    if (s.isEmpty || s.length > 250) return false;
    if (!seen.add(s)) return false;
  }
  return true;
}

String _idText(Object? id) => id is num ? jsNumberText(id) : '$id';

// ---- mf556Decompose / mf556Compose ----------------------------------------------------

/// Breaks [state] into records. [prevPos] gives the positions the cloud already
/// has (by record key), so unchanged array order keeps its positions.
Map<String, Rec> decomposeState(Map<String, dynamic> state, double? Function(String key) prevPos) {
  final out = <String, Rec>{};
  void add(String k, String i, double? pos, String j) => out[recordKey(k, i)] = Rec(k, i, pos, j);
  final keys = state.keys.toList();
  add('doc', '__keys', null, jsStringify(keys));
  for (final key in keys) {
    final v = state[key];
    if (kRecordArrays.contains(key) && _arrayHasIds(v)) {
      final list = v as List;
      final ids = [for (final el in list) _idText((el as Map)['id'])];
      final prev = <String, double>{};
      for (final id in ids) {
        final p = prevPos(recordKey(key, id));
        if (p != null) prev[id] = p;
      }
      final pos = recordPositions(ids, prev);
      add('doc', '__array$_sep$key', null, '1');
      for (var n = 0; n < list.length; n++) {
        add(key, ids[n], pos[n], jsStringify(list[n]));
      }
      continue;
    }
    if (v is Map) {
      final sub = v.keys.map((k) => '$k').toList();
      add('doc', '$key$_sep', null, jsStringify(sub));
      for (final s in sub) {
        add('doc', '$key$_sep$s', null, jsStringify(v[s]));
      }
      continue;
    }
    add('doc', key, null, jsStringify(v));
  }
  return out;
}

class IncompleteRecords implements Exception {
  @override
  String toString() => 'Your cloud records are incomplete. Nothing was changed; try syncing again.';
}

/// Rebuilds the account from records (key order, array order and object key
/// order kept). Throws [IncompleteRecords] when the key list is missing.
Map<String, dynamic> composeState(Iterable<Rec> records) {
  final docs = <String, String>{};
  final arrays = <String, List<Rec>>{};
  for (final r in records) {
    if (r.k == 'doc') {
      docs[r.i] = r.j;
    } else if (kRecordArrays.contains(r.k)) {
      (arrays[r.k] ??= []).add(r);
    }
  }
  final keysJson = docs['__keys'];
  if (keysJson == null) throw IncompleteRecords();
  final state = <String, dynamic>{};
  for (final key in (jsonDecode(keysJson) as List).map((k) => '$k')) {
    if (docs.containsKey('__array$_sep$key')) {
      final rows = [...?arrays[key]]
        ..sort((a, b) {
          // JavaScript: `a.pos-b.pos||…` (a missing position counts as 0).
          final d = (a.pos ?? 0) - (b.pos ?? 0);
          if (d < 0) return -1;
          if (d > 0) return 1;
          return a.i.compareTo(b.i);
        });
      state[key] = [for (final r in rows) jsonDecode(r.j)];
      continue;
    }
    final subKeys = docs['$key$_sep'];
    if (subKeys != null) {
      final obj = <String, dynamic>{};
      for (final s in (jsonDecode(subKeys) as List).map((k) => '$k')) {
        final j = docs['$key$_sep$s'];
        if (j != null) obj[s] = jsonDecode(j);
      }
      state[key] = obj;
      continue;
    }
    final j = docs[key];
    if (j != null) state[key] = jsonDecode(j);
  }
  return state;
}

// ---- what this device knows about the cloud's records -------------------------------

/// For each record the cloud has: its position and hash (not the text — the
/// account itself is kept separately), plus how far this device has read.
class RecordIndex {
  RecordIndex({Map<String, (double?, String)>? entries, this.cursor = '', this.fallbackAt = ''})
      : entries = entries ?? {};
  final Map<String, (double?, String)> entries;

  /// The latest `updated_at` read from the cloud.
  String cursor;

  /// `updated_at` of the last fallback copy this device wrote.
  String fallbackAt;

  double? pos(String key) => entries[key]?.$1;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'cursor': cursor,
        'fallbackAt': fallbackAt,
        'k': [for (final e in entries.entries) e.key],
        'p': [for (final e in entries.values) e.$1],
        'h': [for (final e in entries.values) e.$2],
      };

  static RecordIndex? fromJson(Object? raw) {
    if (raw is! Map || raw['v'] != 1) return null;
    final k = raw['k'], p = raw['p'], h = raw['h'];
    if (k is! List || p is! List || h is! List || k.length != p.length || k.length != h.length) return null;
    final entries = <String, (double?, String)>{};
    for (var n = 0; n < k.length; n++) {
      entries['${k[n]}'] = (p[n] is num ? (p[n] as num).toDouble() : null, '${h[n]}');
    }
    return RecordIndex(entries: entries, cursor: '${raw['cursor'] ?? ''}', fallbackAt: '${raw['fallbackAt'] ?? ''}');
  }

  RecordIndex copy() => RecordIndex(entries: Map.of(entries), cursor: cursor, fallbackAt: fallbackAt);
}

/// A record to upload (`data` null with [deleted] for a deletion).
class RecordUpload {
  RecordUpload(this.k, this.i, this.pos, this.j, {this.deleted = false});
  final String k, i;
  final double? pos;
  final String? j;
  final bool deleted;
}
