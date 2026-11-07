// Fast sorting and filtering for very large Libraries (100,000+ titles), used by
// the Library page and the Logging Library.
//
// The old code re-sorted every title on the screen's thread whenever a sort,
// filter or the account changed, re-reading each title's fields and re-splitting
// both titles into natural-order pieces inside every comparison — millions of
// times for a big Library, long enough for Android's "isn't responding". Here:
//
//  * a title's sort values are read once per account change into flat arrays;
//  * the natural title order ("Part 2" before "Part 10") is worked out once, as
//    a rank, so ties compare two integers;
//  * big sorts run in the background ([Isolate.run]) on those arrays, which are
//    cheap to send; the screen keeps the previous result until the new one lands;
//  * counts, search text and filter results are cached.
//
// The orderings are the same as before (`v189CompareLibraryItems` for the
// Library, `v373CompareData` for the Logging Library), now with a fixed final
// tie-break (title, then Library order) so they are stable.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show SynchronousFuture;

import '../state/models.dart';
import '../util/js.dart';
import 'log_arrange.dart' show lastTouchedIndex, remainingUnits, seedHash;

/// Below this many titles everything runs straight away (a few milliseconds).
const int kLibraryBackgroundThreshold = 4000;

/// Natural-order pieces of a title, worked out once (the same rules as
/// `compareTitlesNatural`: lower-case; two runs of digits compare as numbers,
/// anything else as text).
List<(int?, String)> naturalKey(String title) => [
      for (final m in RegExp(r'\d+|\D+').allMatches(title.toLowerCase())) (int.tryParse(m[0]!), m[0]!),
    ];

int compareNaturalKeys(List<(int?, String)> a, List<(int?, String)> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = a[i], y = b[i];
    final xn = x.$1, yn = y.$1;
    final c = xn != null && yn != null ? xn.compareTo(yn) : x.$2.compareTo(y.$2);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

/// Each title's place in natural title order (0 = first). Titles that compare
/// equal share a rank, so ties fall through to the next rule, as before.
Int32List titleRanks(List<String> titles) {
  final keys = [for (final t in titles) naturalKey(t)];
  final order = List<int>.generate(titles.length, (i) => i);
  order.sort((a, b) {
    final c = compareNaturalKeys(keys[a], keys[b]);
    return c != 0 ? c : a - b;
  });
  final rank = Int32List(titles.length);
  for (var i = 0; i < order.length; i++) {
    final same = i > 0 && compareNaturalKeys(keys[order[i]], keys[order[i - 1]]) == 0;
    rank[order[i]] = same ? rank[order[i - 1]] : i;
  }
  return rank;
}

/// What a sort compares, as flat arrays (so it can be sent to the background).
class SortSpec {
  SortSpec({
    required this.key,
    this.missing,
    this.sign = 1,
    this.titleTie = true,
  });

  /// The value compared first (title rank for a title sort).
  final Float64List key;

  /// Titles with no value: always after the ones that have one.
  final Uint8List? missing;
  final int sign;

  /// Ties go to natural title order (ascending), then Library order.
  final bool titleTie;
}

/// Sorts [rows] (positions in the Library) by [spec]. Pure; runs anywhere.
Int32List sortRows(Int32List rows, SortSpec spec, Int32List rank) {
  final key = spec.key, missing = spec.missing, sign = spec.sign, titleTie = spec.titleTie;
  final list = List<int>.of(rows);
  list.sort((a, b) {
    if (missing != null) {
      final ma = missing[a] == 1, mb = missing[b] == 1;
      if (ma != mb) return ma ? 1 : -1;
    }
    final d = key[a] - key[b];
    if (d != 0) return d < 0 ? -sign : sign;
    if (titleTie) {
      final t = rank[a] - rank[b];
      if (t != 0) return t;
    }
    return a - b;
  });
  return Int32List.fromList(list);
}

Future<Int32List> _ranksInBackground(List<String> titles) => Isolate.run(() => titleRanks(titles));

Future<Int32List> _sortInBackground(Int32List rows, SortSpec spec, Int32List rank) {
  final key = spec.key, missing = spec.missing, sign = spec.sign, titleTie = spec.titleTie;
  return Isolate.run(() => sortRows(rows, SortSpec(key: key, missing: missing, sign: sign, titleTie: titleTie), rank));
}

/// One Library's prepared sort and filter data. Made once per account change
/// ([LibraryIndex.of]); every screen and every sort shares it.
class LibraryIndex {
  LibraryIndex._(this.state, this.items, this.titles);

  final Map<String, dynamic> state;
  final List<Map<String, dynamic>> items;
  final List<LibraryTitle> titles;

  int get length => items.length;

  // ---- the shared index -------------------------------------------------------

  static LibraryIndex? _latest;
  static String _latestKey = '';

  static String _keyFor(Map<String, dynamic> state) =>
      '${identityHashCode(state)}|${jsNum(state['savedAt'])}|${asList(state['library']).length}|${asList(state['sessions']).length}';

  /// The index for [state]. Saving a log, editing a title or a sync makes a new
  /// one; typing in the logging form (which only saves the draft) does not.
  static LibraryIndex of(Map<String, dynamic> state) {
    final key = _keyFor(state);
    final hit = _latest;
    if (hit != null && identical(hit.state, state) && key == _latestKey) return hit;
    final items = <Map<String, dynamic>>[];
    for (final raw in asList(state['library'])) {
      final m = asMap(raw);
      if (m != null) items.add(m);
    }
    final fresh = LibraryIndex._(state, items, [for (final m in items) LibraryTitle(m)]);
    _latest = fresh;
    _latestKey = key;
    return fresh;
  }

  // ---- natural title order ----------------------------------------------------

  Int32List? _rank;
  Future<Int32List>? _rankJob;

  /// The title rank if ready; otherwise starts it and returns null.
  Int32List? get rankNow => _rank;

  Future<Int32List> rank() {
    final ready = _rank;
    if (ready != null) return SynchronousFuture(ready);
    final job = _rankJob;
    if (job != null) return job;
    final titleList = [for (final t in titles) t.title];
    if (length < kLibraryBackgroundThreshold) {
      final r = titleRanks(titleList);
      _rank = r;
      return SynchronousFuture(r);
    }
    return _rankJob = _ranksInBackground(titleList).then((r) => _rank = r);
  }

  // ---- per-field sort values -----------------------------------------------------

  final Map<String, ({Float64List key, Uint8List? missing})> _fields = {};

  ({Float64List key, Uint8List? missing}) field(String name, {bool missingIfZero = false}) {
    final cacheKey = '$name|$missingIfZero';
    return _fields[cacheKey] ??= () {
      final key = Float64List(length);
      Uint8List? missing;
      double n(Object? v) => jsNumOrNull(v) ?? 0;
      double ts(Object? v) {
        final x = jsNumOrNull(v);
        if (v != null && x != null && x > 0) return x;
        if (v is String) {
          final d = DateTime.tryParse(v);
          return d == null ? 0 : d.millisecondsSinceEpoch.toDouble();
        }
        return 0;
      }

      Map<String, double>? touched;
      if (name == 'logging') touched = lastTouchedIndex(state);
      if (name == 'remaining' || missingIfZero) missing = Uint8List(length);
      for (var i = 0; i < length; i++) {
        final it = items[i];
        double v;
        switch (name) {
          case 'remaining':
            final r = remainingUnits(it);
            if (r == null) {
              missing![i] = 1;
              v = 0;
            } else {
              v = r;
            }
          case 'priority':
            // The Logging Library ignores case ("High"); the Library page
            // (`v189CompareLibraryItems`) does not.
            v = _priorityRank(it).toDouble();
          case 'priorityExact':
            const ranks = {'low': 0, 'medium': 1, 'high': 2};
            v = (ranks[jsStr(it['priority']).isEmpty ? 'medium' : jsStr(it['priority'])] ?? 1).toDouble();
          case 'rating':
            v = n(it['rating']);
          case 'progress':
            v = n(it['progress']);
          case 'total':
            v = n(it['total']);
          case 'logging':
            // `v53LastTouched`: by Library id, else by title.
            v = touched!['id:${jsStr(it['id'])}'] ?? touched['title:${cleanTitle(it['title']).toLowerCase()}'] ?? 0;
          case 'seen':
            v = missingIfZero ? ts(it['lastSeenAt']) : n(it['lastSeenAt']);
          case 'added':
            v = missingIfZero ? ts(it['createdAt']) : n(it['createdAt']);
          case 'edited':
            final raw = jsTruthy(it['modifiedAt']) ? it['modifiedAt'] : it['createdAt'];
            v = missingIfZero ? ts(raw) : n(raw);
          default:
            v = 0;
        }
        key[i] = v;
        if (missingIfZero && name != 'remaining' && v == 0) missing![i] = 1;
      }
      return (key: key, missing: missing);
    }();
  }

  static int _priorityRank(Map<String, dynamic> it) {
    const ranks = {'low': 0, 'medium': 1, 'high': 2};
    return ranks[(jsTruthy(it['priority']) ? jsStr(it['priority']) : 'medium').toLowerCase()] ?? 1;
  }

  Float64List _randomKey(int seed) {
    final key = Float64List(length);
    for (var i = 0; i < length; i++) {
      key[i] = seedHash(jsStr(items[i]['id']), seed).toDouble();
    }
    return key;
  }

  Float64List _rankKey(Int32List rank) {
    final key = Float64List(length);
    for (var i = 0; i < length; i++) {
      key[i] = rank[i].toDouble();
    }
    return key;
  }

  // ---- sorted orders -----------------------------------------------------------------

  final Map<String, Int32List> _orders = {};
  final Map<String, Future<Int32List>> _orderJobs = {};

  /// The whole Library in the Library page's order (`v189CompareLibraryItems`).
  /// Ready orders come back synchronously.
  Future<Int32List> libraryOrder(String sort, String dir, int seed) =>
      _order('lib|$sort|$dir|${sort == 'random' ? seed : 0}', (rank) => _librarySpec(sort, dir, seed, rank));

  /// The Logging Library's order (`v373CompareData`) for the sorts that don't
  /// depend on the draft; "Log added" is handled by the caller.
  Future<Int32List> pickerOrder(String sort, String dir, int seed) =>
      _order('pick|$sort|$dir|${sort == 'random' ? seed : 0}', (rank) => _pickerSpec(sort, dir, seed, rank));

  Future<Int32List> _order(String cacheKey, SortSpec Function(Int32List rank) spec) {
    final ready = _orders[cacheKey];
    if (ready != null) return SynchronousFuture(ready);
    final all = Int32List.fromList(List<int>.generate(length, (i) => i));
    if (length < kLibraryBackgroundThreshold) {
      // Small Library: done now, so the first frame already has it.
      final rank = _rank ??= titleRanks([for (final t in titles) t.title]);
      final out = sortRows(all, spec(rank), rank);
      _orders[cacheKey] = out;
      return SynchronousFuture(out);
    }
    return _orderJobs[cacheKey] ??= () async {
      final rank = await this.rank();
      final out = await _sortInBackground(all, spec(rank), rank);
      _orders[cacheKey] = out;
      _orderJobs.remove(cacheKey);
      return out;
    }();
  }

  SortSpec _librarySpec(String sort, String dir, int seed, Int32List rank) {
    final asc = dir == 'asc';
    switch (sort) {
      case 'title':
        return SortSpec(key: _rankKey(rank), sign: asc ? 1 : -1, titleTie: false);
      case 'remaining':
        final f = field('remaining');
        return SortSpec(key: f.key, missing: f.missing, sign: asc ? 1 : -1);
      case 'random':
        return SortSpec(key: _randomKey(seed));
      case 'priority':
        return SortSpec(key: field('priorityExact').key, sign: asc ? 1 : -1);
      case 'rating':
      case 'progress':
      case 'total':
      case 'logging':
      case 'seen':
      case 'added':
        return SortSpec(key: field(sort).key, sign: asc ? 1 : -1);
      default:
        return SortSpec(key: field('edited').key, sign: asc ? 1 : -1);
    }
  }

  SortSpec _pickerSpec(String sort, String dir, int seed, Int32List rank) {
    final sign = dir == 'desc' ? -1 : 1;
    switch (sort) {
      case 'random':
        // `stableSort` by the seeded hash only (Library order breaks ties).
        return SortSpec(key: _randomKey(seed), titleTie: false);
      case 'title':
        return SortSpec(key: _rankKey(rank), sign: sign, titleTie: false);
      case 'remaining':
        final f = field('remaining');
        return SortSpec(key: f.key, missing: f.missing, sign: sign);
      case 'priority':
      case 'progress':
      case 'total':
        return SortSpec(key: field(sort).key, sign: sign);
      case 'logging':
      case 'edited':
      case 'seen':
      case 'added':
        final f = field(sort, missingIfZero: true);
        return SortSpec(key: f.key, missing: f.missing, sign: sign);
      default:
        return SortSpec(key: Float64List(length), sign: sign);
    }
  }

  // ---- search, filters and counts ---------------------------------------------------

  List<String>? _librarySearch, _titleSearch;

  /// The Library page searches the title and its tags.
  List<String> get librarySearch => _librarySearch ??= [
        for (final t in titles) '${t.title} ${asList(t.raw['tags']).map(jsStr).join(' ')}'.toLowerCase(),
      ];

  /// The Logging Library searches the title only.
  List<String> get titleSearch => _titleSearch ??= [
        for (final it in items) cleanTitle(it['title']).trim().toLowerCase(),
      ];

  late final Map<String, int> categoryCounts = () {
    final out = <String, int>{};
    for (final t in titles) {
      out[t.categoryId] = (out[t.categoryId] ?? 0) + 1;
    }
    return out;
  }();

  late final int unrated = titles.where((t) => !(t.rating != null && t.rating! > 0)).length;
  late final int missingCovers = titles.where((t) => t.coverUrl.isEmpty).length;

  final Map<String, List<LibraryTitle>> _filtered = {};

  /// The Library page's rows: [order] filtered (cached per filter).
  List<LibraryTitle> libraryRows(Int32List order, String orderKey,
      {required String status, required String priority, required Set<String> categories, required String query}) {
    final q = query.trim().toLowerCase();
    final cats = (categories.toList()..sort()).join(',');
    final cacheKey = '$orderKey|$status|$priority|$cats|$q';
    final hit = _filtered[cacheKey];
    if (hit != null) return hit;
    final search = q.isEmpty ? null : librarySearch;
    final out = <LibraryTitle>[];
    for (final i in order) {
      final t = titles[i];
      if (status != 'all' && t.status != status) continue;
      if (priority != 'all' && (jsStr(t.raw['priority']).isEmpty ? 'medium' : jsStr(t.raw['priority'])) != priority) continue;
      if (categories.isNotEmpty && !categories.contains(t.categoryId)) continue;
      if (search != null && !search[i].contains(q)) continue;
      out.add(t);
    }
    if (_filtered.length > 6) _filtered.clear();
    return _filtered[cacheKey] = out;
  }

  /// The Logging Library's rows (`pickerCandidates` filters) in [order].
  List<Map<String, dynamic>> pickerRows(Iterable<int> order,
      {required String status, required String priority, required List<String> categories, required String query}) {
    final q = query.trim().toLowerCase();
    final cats = categories.isEmpty ? null : categories.toSet();
    final search = q.isEmpty ? null : titleSearch;
    final out = <Map<String, dynamic>>[];
    for (final i in order) {
      final item = items[i];
      if (!jsTruthy(item['id'])) continue;
      if (search != null && !search[i].contains(q)) continue;
      if (cats != null && !cats.contains(jsStr(item['categoryId']))) continue;
      if (status != 'all' && (jsTruthy(item['status']) ? jsStr(item['status']) : 'planned').toLowerCase() != status) continue;
      if (priority != 'all' && (jsTruthy(item['priority']) ? jsStr(item['priority']) : 'medium').toLowerCase() != priority) continue;
      out.add(item);
    }
    return out;
  }

  final Map<String, int> _positions = {};

  /// Library position of a title id (-1 if missing).
  int positionOf(String id) {
    if (_positions.isEmpty) {
      for (var i = 0; i < length; i++) {
        _positions.putIfAbsent(jsStr(items[i]['id']), () => i);
      }
    }
    return _positions[id] ?? -1;
  }
}
