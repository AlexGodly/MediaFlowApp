// The website's Logging Library picker and "Arrange your session" (v224/v242/
// v373/v378/v379): which Library titles the picker lists, and the order in which
// the titles added to a log are shown. Both are view-only — they never change
// what a log saves. The arrangement is stored in the draft (`v373Ordering`), the
// picker state in `resumeStateV285.logging.ui`, exactly where the website keeps them.

import 'dart:math' as math;

import '../util/js.dart';
import 'recommend.dart' show stableSort;

const List<(String, String)> kArrangeSorts = [
  ('logAdded', 'Added to Logging'),
  ('draftUpdated', 'Last updated in draft'),
  ('progress', 'Consumed progress'),
  ('total', 'Total progress'),
  ('remaining', 'Remaining progress'),
  ('priority', 'Priority'),
  ('title', 'Alphabetical'),
  ('logging', 'Last updated by logging'),
  ('edited', 'Last edited'),
  ('seen', 'Last seen in Title Details'),
  ('added', 'Date added to Library'),
  ('random', 'Random'),
  ('custom', 'Custom order'),
];

/// The picker offers every sort except the draft-only ones.
final List<(String, String)> kPickerSorts =
    kArrangeSorts.where((s) => s.$1 != 'custom' && s.$1 != 'draftUpdated').toList();

const List<String> kStatuses = ['planned', 'active', 'paused', 'completed', 'dropped'];
const List<String> kPriorities = ['high', 'medium', 'low'];

// ---- shared comparison (v373CompareData) ------------------------------------

double _ts(Object? v) {
  final n = jsNumOrNull(v);
  if (v != null && n != null && n > 0) return n;
  if (v is String) {
    final d = DateTime.tryParse(v);
    return d == null ? 0 : d.millisecondsSinceEpoch.toDouble();
  }
  return 0;
}

/// `v373RemainingUnits`: null when a total is unknown (sorts last).
double? remainingUnits(Map<String, dynamic>? item) {
  if (item == null) return null;
  double? validTotal(Object? v) {
    if (v == null || v == '') return null;
    final n = jsNumOrNull(v);
    return n != null && n > 0 ? n.floorToDouble() : null;
  }

  double progress(Object? v) {
    final n = jsNumOrNull(v);
    return n == null ? 0 : math.max(0, n.floorToDouble());
  }

  final seasons = asList(item['seasons']);
  if (seasons.isNotEmpty) {
    var sum = 0.0;
    for (final raw in seasons) {
      final s = asMap(raw);
      final total = validTotal(s?['total'] ?? s?['totalEpisodes'] ?? s?['total_episodes']);
      if (total == null) return null;
      sum += math.max(0, total - progress(s?['progress']));
    }
    return sum;
  }
  final total = validTotal(item['total']);
  return total == null ? null : math.max(0, total - progress(item['progress']));
}

/// `v53LastTouched` for every title: newest History time that mentions it.
Map<String, double> lastTouchedIndex(Map<String, dynamic> state) {
  final map = <String, double>{};
  final sessions = asList(state['sessions']);
  for (var n = sessions.length - 1; n >= 0; n--) {
    final s = asMap(sessions[n]);
    final ts = jsNum(s?['timestamp']);
    for (final raw in asList(s?['titles'])) {
      final t = asMap(raw);
      if (t == null) continue;
      if (jsTruthy(t['libraryId'])) map.putIfAbsent('id:${jsStr(t['libraryId'])}', () => ts);
      final title = cleanTitle(t['title']).toLowerCase();
      if (title.isNotEmpty) map.putIfAbsent('title:$title', () => ts);
    }
  }
  return map;
}

double _lastTouched(Map<String, double> index, Map<String, dynamic> item) =>
    index['id:${jsStr(item['id'])}'] ?? index['title:${cleanTitle(item['title']).toLowerCase()}'] ?? 0;

int compareTitlesNatural(String a, String b) {
  // localeCompare(..., {numeric:true, sensitivity:'base'}) approximation.
  final ra = RegExp(r'\d+|\D+');
  final pa = ra.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final pb = ra.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i], y = pb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

/// FNV-style hash used by the website's Random orders (`v373SeedHash`).
int seedHash(String s, int seed) {
  var h = (2166136261 ^ (seed & 0xFFFFFFFF)) & 0xFFFFFFFF;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
  }
  h ^= h >> 16;
  h = (h * 2246822507) & 0xFFFFFFFF;
  h ^= h >> 13;
  return h & 0xFFFFFFFF;
}

int _compare(
  ({Map<String, dynamic>? item, Map<String, dynamic> entry, int index}) a,
  ({Map<String, dynamic>? item, Map<String, dynamic> entry, int index}) b,
  String field,
  String dir,
  Map<String, double> touched,
) {
  final sign = dir == 'desc' ? -1 : 1;
  final ia = a.item ?? const <String, dynamic>{}, ib = b.item ?? const <String, dynamic>{};
  if (field == 'title') {
    final ta = cleanTitle(a.item != null ? ia['title'] : a.entry['title']);
    final tb = cleanTitle(b.item != null ? ib['title'] : b.entry['title']);
    return sign * compareTitlesNatural(ta, tb);
  }
  if (field == 'priority') {
    const ranks = {'low': 0, 'medium': 1, 'high': 2};
    int r(Map<String, dynamic> i) => ranks[(jsTruthy(i['priority']) ? jsStr(i['priority']) : 'medium').toLowerCase()] ?? 1;
    return sign * (r(ia) - r(ib));
  }
  if (field == 'remaining') {
    final av = remainingUnits(a.item), bv = remainingUnits(b.item);
    if (av == null && bv != null) return 1;
    if (av != null && bv == null) return -1;
    if (av == null && bv == null) return 0;
    return sign * av!.compareTo(bv!);
  }
  double av = 0, bv = 0;
  double num(Object? v) => jsNumOrNull(v) ?? 0;
  switch (field) {
    case 'logAdded':
      av = a.index.toDouble();
      bv = b.index.toDouble();
    case 'draftUpdated':
      av = draftModifiedAt(a.entry);
      bv = draftModifiedAt(b.entry);
    case 'progress':
      av = num(ia['progress']);
      bv = num(ib['progress']);
    case 'total':
      av = num(ia['total']);
      bv = num(ib['total']);
    case 'logging':
      av = a.item == null ? 0 : _lastTouched(touched, ia);
      bv = b.item == null ? 0 : _lastTouched(touched, ib);
    case 'edited':
      av = _ts(jsTruthy(ia['modifiedAt']) ? ia['modifiedAt'] : ia['createdAt']);
      bv = _ts(jsTruthy(ib['modifiedAt']) ? ib['modifiedAt'] : ib['createdAt']);
    case 'seen':
      av = _ts(ia['lastSeenAt']);
      bv = _ts(ib['lastSeenAt']);
    case 'added':
      av = _ts(ia['createdAt']);
      bv = _ts(ib['createdAt']);
  }
  if (const ['draftUpdated', 'logging', 'edited', 'seen', 'added'].contains(field)) {
    if (av == 0 && bv != 0) return 1;
    if (av != 0 && bv == 0) return -1;
  }
  final d = av - bv;
  return sign * (d < 0 ? -1 : (d > 0 ? 1 : 0));
}

/// `v373DraftModifiedAt`.
double draftModifiedAt(Map<String, dynamic> entry) {
  var stamp = _ts(entry['v369UpdatedAt']);
  for (final u in asList(entry['v369Units'])) {
    stamp = math.max(stamp, _ts(asMap(u)?['v369UpdatedAt']));
  }
  return stamp != 0 ? stamp : _ts(entry['loggedAt']);
}

// ---- Arrange your session (logDraft.v373Ordering) --------------------------

/// `v373OrderState` (normalizes the draft's ordering in place).
Map<String, dynamic> orderState(Map<String, dynamic> draft) {
  var st = asMap(draft['v373Ordering']);
  if (st == null) {
    st = {'sort': 'logAdded', 'dir': 'desc', 'manualIds': <dynamic>[], 'randomSeed': 1, 'v517DefaultApplied': true, 'v525DefaultApplied': true};
    draft['v373Ordering'] = st;
  }
  if (st['v517DefaultApplied'] != true) {
    final untouched = st['sort'] == 'logAdded' && st['dir'] == 'asc' && asList(st['manualIds']).isEmpty;
    if (untouched) {
      st['sort'] = 'added';
      st['dir'] = 'desc';
    }
    st['v517DefaultApplied'] = true;
  }
  if (st['v525DefaultApplied'] != true) {
    if (st['sort'] == 'added' && st['dir'] == 'desc' && asList(st['manualIds']).isEmpty) {
      st['sort'] = 'logAdded';
      st['dir'] = 'desc';
    }
    st['v525DefaultApplied'] = true;
  }
  if (!kArrangeSorts.any((s) => s.$1 == st!['sort'])) {
    st['sort'] = 'logAdded';
    st['dir'] = 'desc';
  }
  st['dir'] = st['dir'] == 'desc' ? 'desc' : 'asc';
  if (st['manualIds'] is! List) st['manualIds'] = <dynamic>[];
  final seed = jsNum(st['randomSeed']);
  if (!(seed >= 1) || seed != seed.truncateToDouble()) st['randomSeed'] = 1;
  return st;
}

/// `v373EntryKey`: a stable key per added title.
String entryKey(Map<String, dynamic> e) {
  if (!jsTruthy(e['v373Key'])) e['v373Key'] = 'mf373-${mediaFlowUid()}';
  return jsStr(e['v373Key']);
}

/// `v373OrderedEntries`: indexes into `draft.entries` in display order.
List<int> orderedEntries(Map<String, dynamic> draft, Map<String, dynamic> state) {
  final st = orderState(draft);
  final library = <String, Map<String, dynamic>>{};
  for (final raw in asList(state['library'])) {
    final m = asMap(raw);
    if (m != null && jsTruthy(m['id'])) library.putIfAbsent(jsStr(m['id']), () => m);
  }
  final entries = asList(draft['entries']);
  final rows = <({Map<String, dynamic>? item, Map<String, dynamic> entry, int index, String id})>[];
  for (var i = 0; i < entries.length; i++) {
    final e = asMap(entries[i]);
    if (e == null) continue;
    rows.add((item: library[jsStr(e['libraryId'])], entry: e, index: i, id: entryKey(e)));
  }
  final sort = jsStr(st['sort']), dir = jsStr(st['dir']);
  if (sort == 'custom') {
    final positions = <String, int>{};
    final ids = asList(st['manualIds']);
    for (var i = 0; i < ids.length; i++) {
      positions[jsStr(ids[i])] = i;
    }
    stableSort(rows, (a, b) {
      final pa = positions[a.id] ?? 1 << 52, pb = positions[b.id] ?? 1 << 52;
      return pa != pb ? pa.compareTo(pb) : a.index - b.index;
    });
  } else if (sort == 'random') {
    final seed = jsNum(st['randomSeed']).toInt();
    stableSort(rows, (a, b) {
      final d = seedHash(a.id, seed).compareTo(seedHash(b.id, seed));
      return d != 0 ? d : a.index - b.index;
    });
  } else if (sort == 'logAdded' && dir == 'asc') {
    stableSort(rows, (a, b) => a.index - b.index);
  } else {
    final touched = sort == 'logging' ? lastTouchedIndex(state) : const <String, double>{};
    stableSort(rows, (a, b) {
      final d = _compare((item: a.item, entry: a.entry, index: a.index), (item: b.item, entry: b.entry, index: b.index), sort, dir, touched);
      return d != 0 ? d : a.index - b.index;
    });
  }
  return [for (final r in rows) r.index];
}

/// `v373SetSort`.
void setArrangeSort(Map<String, dynamic> draft, Map<String, dynamic> state, String value) {
  final st = orderState(draft);
  final next = kArrangeSorts.any((s) => s.$1 == value) ? value : 'logAdded';
  if (next == 'custom' && st['sort'] != 'custom') {
    final entries = asList(draft['entries']);
    st['manualIds'] = [for (final i in orderedEntries(draft, state)) entryKey(asMap(entries[i])!)];
  }
  if (const ['logAdded', 'draftUpdated', 'added', 'remaining'].contains(next) && st['sort'] != next) st['dir'] = 'desc';
  st['sort'] = next;
}

/// `v373ToggleDirection`.
void toggleArrangeDirection(Map<String, dynamic> draft) {
  final st = orderState(draft);
  if (st['sort'] == 'custom' || st['sort'] == 'random') return;
  st['dir'] = st['dir'] == 'asc' ? 'desc' : 'asc';
}

/// `v373Reshuffle`.
void reshuffle(Map<String, dynamic> draft, int now) {
  final st = orderState(draft);
  st['sort'] = 'random';
  final seed = now % 2147483647;
  st['randomSeed'] = seed == 0 ? 1 : seed;
}

/// `v373Move`: moves the title at entries[index] to display position [target].
void moveEntry(Map<String, dynamic> draft, Map<String, dynamic> state, int index, int target) {
  final st = orderState(draft);
  final order = orderedEntries(draft, state);
  final at = order.indexOf(index);
  if (at < 0 || order.length < 2) return;
  final end = target.clamp(0, order.length - 1);
  if (end == at) return;
  final entries = asList(draft['entries']);
  final ids = [for (final i in order) entryKey(asMap(entries[i])!)];
  final id = ids.removeAt(at);
  ids.insert(end, id);
  st['manualIds'] = ids;
  st['sort'] = 'custom';
}

// ---- Logging Library picker -------------------------------------------------

/// The picker's saved state (`logging.ui`, website V89_LOG fields).
class PickerState {
  PickerState({
    this.categories = const [],
    this.status = 'all',
    this.priority = 'all',
    this.sortBase = 'added',
    this.sortDir = 'desc',
    this.page = 0,
    this.open = false,
    this.seed = 1,
  });

  List<String> categories;
  String status;
  String priority;
  String sortBase;
  String sortDir;
  int page;
  bool open;
  int seed;

  /// From `resumeStateV285.logging.ui` (`v373NormalizePickerSort` defaults).
  static PickerState fromUi(Object? raw) {
    final ui = asMap(raw) ?? const {};
    var base = jsStr(ui['sortBase']).toLowerCase();
    var dir = jsStr(ui['sortDir']) == 'asc' ? 'asc' : 'desc';
    if (!kPickerSorts.any((s) => s.$1 == base)) {
      base = 'added';
      dir = 'desc';
    }
    return PickerState(
      categories: asList(ui['categories']).map(jsStr).toList(),
      status: jsTruthy(ui['status']) ? jsStr(ui['status']) : 'all',
      priority: jsTruthy(ui['priority']) ? jsStr(ui['priority']) : 'all',
      sortBase: base,
      sortDir: dir,
      page: math.max(0, jsNum(ui['page']).floor()),
      open: ui['libraryOpen'] == true,
    );
  }

  Map<String, dynamic> toUi() => {
        'libraryOpen': open,
        'page': page,
        'categories': categories,
        'status': status,
        'priority': priority,
        'sort': '$sortBase-$sortDir',
        'sortBase': sortBase,
        'sortDir': sortDir,
      };
}

/// The Library titles the picker shows, filtered and sorted like the website.
List<Map<String, dynamic>> pickerCandidates(
    Map<String, dynamic> state, Map<String, dynamic>? draft, PickerState st, String query) {
  final q = query.trim().toLowerCase();
  final cats = st.categories.isEmpty ? null : st.categories.toSet();
  final rows = <Map<String, dynamic>>[];
  for (final raw in asList(state['library'])) {
    final item = asMap(raw);
    if (item == null || !jsTruthy(item['id'])) continue;
    if (q.isNotEmpty && !cleanTitle(item['title']).trim().toLowerCase().contains(q)) continue;
    if (cats != null && !cats.contains(jsStr(item['categoryId']))) continue;
    final status = (jsTruthy(item['status']) ? jsStr(item['status']) : 'planned').toLowerCase();
    if (st.status != 'all' && status != st.status) continue;
    final priority = (jsTruthy(item['priority']) ? jsStr(item['priority']) : 'medium').toLowerCase();
    if (st.priority != 'all' && priority != st.priority) continue;
    rows.add(item);
  }
  if (rows.length < 2) return rows;
  int byTitle(Map<String, dynamic> a, Map<String, dynamic> b) =>
      compareTitlesNatural(cleanTitle(a['title']), cleanTitle(b['title']));
  if (st.sortBase == 'random') {
    stableSort(rows, (a, b) => seedHash(jsStr(a['id']), st.seed).compareTo(seedHash(jsStr(b['id']), st.seed)));
    return rows;
  }
  final sign = st.sortDir == 'desc' ? -1 : 1;
  if (st.sortBase == 'logAdded') {
    final selected = <String, double>{};
    final entries = asList(draft?['entries']);
    for (var i = 0; i < entries.length; i++) {
      final e = asMap(entries[i]);
      final ts = _ts(e?['loggedAt']);
      selected[jsStr(e?['libraryId'])] = ts != 0 ? ts : (i + 1).toDouble();
    }
    stableSort(rows, (a, b) {
      final av = selected[jsStr(a['id'])] ?? 0, bv = selected[jsStr(b['id'])] ?? 0;
      if (av == 0 && bv != 0) return 1;
      if (av != 0 && bv == 0) return -1;
      final d = sign * (av - bv);
      return d != 0 ? (d < 0 ? -1 : 1) : byTitle(a, b);
    });
    return rows;
  }
  final touched = st.sortBase == 'logging' ? lastTouchedIndex(state) : const <String, double>{};
  final index = <Map<String, dynamic>, int>{for (var i = 0; i < rows.length; i++) rows[i]: i};
  stableSort(rows, (a, b) {
    final d = _compare((item: a, entry: {'title': a['title']}, index: index[a]!),
        (item: b, entry: {'title': b['title']}, index: index[b]!), st.sortBase, st.sortDir, touched);
    return d != 0 ? d : byTitle(a, b);
  });
  return rows;
}

/// `v175PageSize('loggingLibrary')`.
int loggingPageSize(Map<String, dynamic> state) {
  final sizes = asMap(asMap(state['settings'])?['v175PageSizes']);
  final n = jsNumOrNull(sizes?['loggingLibrary']);
  if (sizes == null || !sizes.containsKey('loggingLibrary') || n == null || n < 1) return 20;
  return math.min(5000, n.floor());
}
