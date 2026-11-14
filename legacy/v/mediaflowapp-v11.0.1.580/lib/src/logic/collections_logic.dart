// Collections (v274/v276/v392 + v334 create/edit XP + v348 action XP) and
// Personal Order (v138/v157/v287 + v348 action XP), ported from the website.

import 'dart:convert';
import 'dart:math' as math;

import '../config.dart' show kAppVersionLabel;
import '../state/lazy_copy.dart';
import '../util/js.dart';
import 'leveling.dart';
import 'library_hooks.dart';
import 'library_logic.dart' show v348Award;
import 'recommend.dart';

List<String> _ids(Object? v) {
  final out = <String>[];
  for (final x in asList(v)) {
    final s = jsStr(x);
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
  }
  return out;
}

// ---- Collections ---------------------------------------------------------------------

/// `v274NormalizeCollection` (keeps any extra fields the website added).
Map<String, dynamic> normalizeCollection(Map<String, dynamic> c, int now, String Function() uid) {
  final titleIds = _ids(c['titleIds']);
  final order = [for (final id in _ids(c['order'] is List ? c['order'] : titleIds)) if (titleIds.contains(id)) id];
  for (final id in titleIds) {
    if (!order.contains(id)) order.add(id);
  }
  return {
    ...c,
    'id': jsStr(c['id']).trim().isEmpty ? uid() : jsStr(c['id']).trim(),
    'title': jsStr(c['title']).trim().isEmpty ? 'Untitled Collection' : jsStr(c['title']).trim(),
    'description': jsStr(c['description']),
    'coverUrl': jsStr(c['coverUrl']).trim(),
    'titleIds': List<String>.of(order),
    'order': List<String>.of(order),
    'autoBackground': c['autoBackground'] != false,
    'createdAt': c['createdAt'] == null ? now : (jsNumOrNull(c['createdAt']) ?? now),
    'updatedAt': c['updatedAt'] == null ? now : (jsNumOrNull(c['updatedAt']) ?? now),
    'lastViewedAt': jsNumOrNull(c['lastViewedAt']) ?? 0,
  };
}

List<Map<String, dynamic>> collectionsOf(Map<String, dynamic> state) =>
    asList(state['collections']).map(asMap).whereType<Map<String, dynamic>>().toList();

Map<String, dynamic>? collectionById(Map<String, dynamic> state, String id) =>
    collectionsOf(state).where((c) => jsStr(c['id']) == id).firstOrNull;

List<String> _collectionIds(Map<String, dynamic> c) => _ids(asList(c['order']).isNotEmpty ? c['order'] : c['titleIds']);

/// `v274TouchCollection` with the v334 and v348 wrappers. [before] is the
/// collection's title order before the change (null for a new collection).
void _touchCollection(Map<String, dynamic> state, Map<String, dynamic> c, List<String>? before, int now, String Function() uid,
    {bool suppressEdit = false}) {
  final l = Leveling(state);
  final ledger = ledgerOf(state);
  final creates = mapIn(ledger, 'v334CollectionCreates'), edits = mapIn(ledger, 'v334CollectionEdits');
  final snap = {'v334CollectionCreates': Map<String, dynamic>.from(creates), 'v334CollectionEdits': Map<String, dynamic>.from(edits)};
  final id = jsStr(c['id']);
  final enabled = l.enabled;
  // base touch
  c['updatedAt'] = now;
  c['titleIds'] = _ids(c['titleIds']);
  c['order'] = List<String>.of(c['titleIds'] as List<String>);
  if (before == null) {
    if (!creates.containsKey(id)) creates[id] = enabled ? jsRound(l.reward('collectionCreateXP')) : 0;
  } else if (!suppressEdit) {
    edits[id] = jsOut(jsNum(edits[id]) + (enabled ? jsRound(l.reward('collectionEditXP')) : 0));
  }
  // v348RaiseNewRewards
  if (enabled) {
    final mult = awardMultiplier(l, asList(readOnlyPart(state, 'sessions')), now, reuse: true);
    final meta = mapIn(ledger, 'v348EventMeta');
    for (final key in snap.keys) {
      final after = mapIn(ledger, key);
      for (final e in after.entries.toList()) {
        final added = math.max(0.0, jsNum(e.value) - jsNum(snap[key]![e.key]));
        if (added <= 0) continue;
        final xp = math.max(0.0, jsRound(added * mult));
        if (xp - added > 0) after[e.key] = jsOut(jsNum(e.value) + xp - added);
        meta['$key:${e.key}:$now:${uid()}'] = {
          'kind': key, 'baseXP': jsOut(added), 'multiplier': jsOut(mult), 'xp': jsOut(xp), 'timestamp': now,
          'source': key == 'v334CollectionCreates' ? 'Collection created' : 'Collection edited', 'subjectId': e.key,
        };
      }
    }
  }
  final after = _collectionIds(c);
  if (before != null) {
    final previous = before.toSet();
    final added = after.where((x) => !previous.contains(x)).toList();
    if (added.isNotEmpty) {
      final names = {for (final i in asList(readOnlyPart(state, 'library'))) jsStr(asMap(i)?['id']): jsStr(asMap(i)?['title'])};
      v348Award(state, 'collectionAddTitleXP', added.length, now, uid,
          subjectId: id, description: added.map((t) => names[t]?.isNotEmpty == true ? names[t]! : t).take(8).join(', '));
    }
    final oldCommon = before.where(after.contains).toList(), newCommon = after.where(previous.contains).toList();
    if (oldCommon.length > 1 && oldCommon.join('\u0000') != newCommon.join('\u0000')) {
      v348Award(state, 'collectionReorderTitleXP', 1, now, uid, subjectId: id, description: jsStr(c['title']).isEmpty ? 'Collection' : jsStr(c['title']));
    }
  }
}

/// `v274SaveCollection` (+ v334 "identical save earns nothing"). Returns the id.
String saveCollection(Map<String, dynamic> state, String? id, int now, String Function() uid,
    {required String title,
    String coverUrl = '',
    String description = '',
    String backgroundUrl = '',
    bool customBackground = false,
    String? coverTitleId}) {
  final t = title.trim();
  final list = List<dynamic>.of(asList(state['collections']));
  var c = id == null ? null : collectionById(state, id);
  final before = c == null ? null : _collectionIds(c);
  final identical = c != null &&
      jsStr(c['title']) == t &&
      jsStr(c['coverUrl']) == coverUrl.trim() &&
      jsStr(c['description']) == description &&
      (c['autoBackground'] != false) == !(customBackground && backgroundUrl.trim().isNotEmpty);
  if (c == null) {
    c = normalizeCollection({'id': uid(), 'title': t, 'createdAt': now, 'updatedAt': now, 'titleIds': <String>[]}, now, uid);
    list.add(c);
    state['collections'] = list;
  }
  c['title'] = t;
  c['coverUrl'] = coverUrl.trim();
  c['description'] = description;
  c['backgroundUrl'] = backgroundUrl.trim();
  c['backgroundMode'] = customBackground && backgroundUrl.trim().isNotEmpty ? 'custom' : 'auto';
  c['autoBackground'] = c['backgroundMode'] == 'auto';
  _touchCollection(state, c, before, now, uid, suppressEdit: identical);
  // v565: the cover can follow a title (website App.v274SaveCollection wrapper:
  // set or cleared after the save, then the collection is touched again).
  if (coverTitleId != null && jsStr(c['mf565CoverTitleId']) != coverTitleId) {
    if (coverTitleId.isEmpty) {
      c.remove('mf565CoverTitleId');
    } else {
      c['mf565CoverTitleId'] = coverTitleId;
    }
    _touchCollection(state, c, _collectionIds(c), now, uid);
  }
  return jsStr(c['id']);
}

/// `v274DeleteCollection`.
bool deleteCollection(Map<String, dynamic> state, String id, int now) {
  final c = collectionById(state, id);
  if (c == null) return false;
  state['collections'] = [for (final x in asList(state['collections'])) if (jsStr(asMap(x)?['id']) != id) x];
  state['collectionTombstones'] = [...asList(state['collectionTombstones']), {'id': id, 'deletedAt': now}];
  return true;
}

/// `v392InsertCollectionTitles`. Returns how many were added.
int addCollectionTitles(Map<String, dynamic> state, String id, List<String> ids, int now, String Function() uid) {
  final c = collectionById(state, id);
  if (c == null) return 0;
  final before = _collectionIds(c);
  final have = _ids(c['titleIds']).toSet();
  final valid = asList(readOnlyPart(state, 'library')).map((i) => jsStr(asMap(i)?['id'])).toSet();
  final list = _ids(c['titleIds']);
  var n = 0;
  for (final t in ids) {
    if (t.isNotEmpty && valid.contains(t) && have.add(t)) {
      list.add(t);
      n++;
    }
  }
  if (n == 0) return 0;
  c['titleIds'] = list;
  c['order'] = List<String>.of(list);
  _touchCollection(state, c, before, now, uid);
  return n;
}

/// `v392RemoveIds`.
int removeCollectionTitles(Map<String, dynamic> state, String id, Set<String> ids, int now, String Function() uid) {
  final c = collectionById(state, id);
  if (c == null) return 0;
  final before = _collectionIds(c);
  final list = _ids(c['titleIds']);
  if (!list.any(ids.contains)) return 0;
  final next = list.where((x) => !ids.contains(x)).toList();
  c['titleIds'] = next;
  c['order'] = List<String>.of(next);
  _touchCollection(state, c, before, now, uid);
  return list.length - next.length;
}

/// `v274MoveTitle` (delta) or a drop to [toIndex].
bool moveCollectionTitle(Map<String, dynamic> state, String id, String titleId, int now, String Function() uid, {int delta = 0, int? toIndex}) {
  final c = collectionById(state, id);
  if (c == null) return false;
  final before = _collectionIds(c);
  final ids = _ids(c['titleIds']);
  final i = ids.indexOf(titleId);
  if (i < 0) return false;
  final j = (toIndex ?? i + delta).clamp(0, ids.length - 1);
  if (i == j) return false;
  final x = ids.removeAt(i);
  ids.insert(j, x);
  c['titleIds'] = ids;
  c['order'] = List<String>.of(ids);
  _touchCollection(state, c, before, now, uid);
  return true;
}

/// `v274CollectionProgress`.
({int pct, int done, int total}) collectionProgress(Map<String, dynamic> state, Map<String, dynamic> c) {
  final byId = {for (final i in asList(readOnlyPart(state, 'library'))) jsStr(asMap(i)?['id']): asMap(i)};
  final items = [for (final id in _collectionIds(c)) if (byId[id] != null) byId[id]!];
  if (items.isEmpty) return (pct: 0, done: 0, total: 0);
  var done = 0.0, total = 0.0;
  var completed = 0;
  for (final item in items) {
    final t = math.max(0.0, jsNum(item['total'])), p = math.max(0.0, jsNum(item['progress']));
    if (t > 0) {
      total += t;
      done += math.min(p, t);
    }
    if (item['status'] == 'completed' || (t > 0 && p >= t)) completed++;
  }
  final pct = total > 0 ? (done / total * 100).round() : (completed / items.length * 100).round();
  return (pct: pct.clamp(0, 100).toInt(), done: completed, total: items.length);
}

List<String> collectionTitleIds(Map<String, dynamic> c) => _collectionIds(c);

// ---- Personal Order ------------------------------------------------------------------

/// `v138NormalizeOrderPlan` + v287 extensions (unknown fields are kept).
Map<String, dynamic> ensureOrderPlan(Map<String, dynamic> state) {
  final raw = asMap(state['orderPlan']) ?? <String, dynamic>{};
  final libIds = asList(readOnlyPart(state, 'library')).map((i) => jsStr(asMap(i)?['id'])).where((x) => x.isNotEmpty).toSet();
  final cats = asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().toList();
  final catIds = cats.map((c) => jsStr(c['id'])).where((x) => x.isNotEmpty).toSet();
  List<String> unique(Object? v, Set<String> allowed) => [for (final x in _ids(v)) if (allowed.contains(x)) x];
  final custom = unique(raw['categoryOrder'], catIds);
  for (final c in cats) {
    final id = jsStr(c['id']);
    if (id.isNotEmpty && !custom.contains(id)) custom.add(id);
  }
  final assignments = <Map<String, dynamic>>[];
  final pairs = <String>{}, seenIds = <String>{};
  for (final a in asList(raw['collectionAssignments']).map(asMap).whereType<Map<String, dynamic>>()) {
    final cid = jsStr(a['categoryId']), col = jsStr(a['collectionId']);
    if (cid.isEmpty || col.isEmpty || (catIds.isNotEmpty && !catIds.contains(cid))) continue;
    if (!pairs.add('$cid\u0000$col')) continue;
    final created = jsNum(a['createdAt']);
    final norm = {
      ...a,
      'id': jsStr(a['id']).isEmpty ? 'oca_${mediaFlowUid()}' : jsStr(a['id']),
      'collectionId': col,
      'categoryId': cid,
      'categoryRule': a['categoryRule'] == 'force' ? 'force' : 'match',
      'completedRule': a['completedRule'] == 'include' ? 'include' : 'skip',
      'traversedTitleIds': _ids(a['traversedTitleIds']),
    };
    if (!(created > 0)) norm['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    if (!seenIds.add(jsStr(norm['id']))) norm['id'] = 'oca_${mediaFlowUid()}';
    assignments.add(norm);
  }
  final queues = <String, dynamic>{};
  for (final e in (asMap(raw['categoryQueues']) ?? const <String, dynamic>{}).entries) {
    if (e.key.isEmpty || (catIds.isNotEmpty && !catIds.contains(e.key))) continue;
    queues[e.key] = [for (final t in _ids(e.value)) if (RegExp(r'^[tc]:.+').hasMatch(t)) t];
  }
  final plan = <String, dynamic>{
    ...raw,
    'titleIds': unique(raw['titleIds'], libIds),
    'viewMode': raw['viewMode'] == 'category' ? 'category' : 'all',
    'categoryMode': raw['categoryMode'] == 'custom' ? 'custom' : 'default',
    'categoryOrder': custom,
    'hiddenCategories': unique(raw['hiddenCategories'], catIds),
    'modifiedAt': math.max(0.0, jsNum(raw['modifiedAt'])),
    'collectionAssignments': assignments,
    'categoryQueues': queues,
  };
  state['orderPlan'] = plan;
  return plan;
}

({List<String> titles, List<String> assignments, Map<String, List<String>> queues}) _orderSnapshot(Map<String, dynamic> p) => (
      titles: _ids(p['titleIds']),
      assignments: [for (final a in asList(p['collectionAssignments'])) if (jsStr(asMap(a)?['id']).isNotEmpty) jsStr(asMap(a)?['id'])],
      queues: {for (final e in (asMap(p['categoryQueues']) ?? const <String, dynamic>{}).entries) e.key: _ids(e.value)},
    );

/// `v348CompareOrder` → v287 reconcile → `v138TouchOrderPlan`.
void _touchOrder(Map<String, dynamic> state, ({List<String> titles, List<String> assignments, Map<String, List<String>> queues}) prev, int now,
    String Function() uid) {
  final p = asMap(state['orderPlan'])!;
  final next = _orderSnapshot(p);
  final titles = prev.titles.toSet(), nowTitles = next.titles.toSet();
  final names = {for (final i in asList(readOnlyPart(state, 'library'))) jsStr(asMap(i)?['id']): jsStr(asMap(i)?['title'])};
  final addedIds = next.titles.where((x) => !titles.contains(x)).toList();
  if (addedIds.isNotEmpty) {
    v348Award(state, 'orderAddTitleXP', addedIds.length, now, uid,
        description: addedIds.map((t) => names[t]?.isNotEmpty == true ? names[t]! : t).take(8).join(', '));
  }
  final oldCommon = prev.titles.where(nowTitles.contains).toList(), newCommon = next.titles.where(titles.contains).toList();
  if (oldCommon.length > 1 && oldCommon.join('\u0000') != newCommon.join('\u0000')) {
    v348Award(state, 'orderReorderTitleXP', 1, now, uid, description: 'Reordered Personal Order title sequence');
  }
  final assigned = prev.assignments.toSet();
  final newly = next.assignments.where((x) => !assigned.contains(x)).toList();
  if (newly.isNotEmpty) {
    final cols = {for (final c in asList(state['collections'])) jsStr(asMap(c)?['id']): jsStr(asMap(c)?['title'])};
    final byId = {for (final a in asList(p['collectionAssignments'])) jsStr(asMap(a)?['id']): asMap(a)};
    v348Award(state, 'orderAddCollectionXP', newly.length, now, uid,
        description: newly.map((id) => cols[jsStr(byId[id]?['collectionId'])] ?? id).take(8).join(', '));
  } else {
    for (final key in {...prev.queues.keys, ...next.queues.keys}) {
      final old = prev.queues[key] ?? const <String>[], cur = next.queues[key] ?? const <String>[];
      final oldCols = old.where((x) => x.startsWith('c:') && cur.contains(x)).toList();
      final newCols = cur.where((x) => x.startsWith('c:') && old.contains(x)).toList();
      final moved = oldCols.any((t) => old.indexOf(t) != cur.indexOf(t));
      if ((oldCols.length > 1 && oldCols.join('\u0000') != newCols.join('\u0000')) || moved) {
        v348Award(state, 'orderReorderCollectionXP', 1, now, uid, description: 'Moved Collection queue position');
        break;
      }
    }
  }
  Recommender(state, now: now).reconcileAllQueues();
  p['modifiedAt'] = now;
}

/// Runs a Personal Order change the way the website saves one.
void orderEdit(Map<String, dynamic> state, int now, String Function() uid, void Function(Map<String, dynamic> plan) change) {
  final p = ensureOrderPlan(state);
  final prev = _orderSnapshot(p);
  final before = jsonEncode(p);
  change(p);
  if (jsonEncode(p) == before) return;
  _touchOrder(state, prev, now, uid);
}

void orderAddTitles(Map<String, dynamic> p, Map<String, dynamic> state, List<String> ids) {
  final list = _ids(p['titleIds']);
  final have = list.toSet();
  final valid = asList(readOnlyPart(state, 'library')).map((i) => jsStr(asMap(i)?['id'])).toSet();
  for (final id in ids) {
    if (valid.contains(id) && have.add(id)) list.add(id);
  }
  p['titleIds'] = list;
}

void orderRemoveTitle(Map<String, dynamic> p, String id) => p['titleIds'] = _ids(p['titleIds']).where((x) => x != id).toList();

/// `v142OrderSnapshotFrom`.
Map<String, dynamic> orderSnapshot(Map<String, dynamic> p, int now) => {
      'titleIds': _ids(p['titleIds']),
      'viewMode': p['viewMode'] == 'category' ? 'category' : 'all',
      'categoryMode': p['categoryMode'] == 'custom' ? 'custom' : 'default',
      'categoryOrder': _ids(p['categoryOrder']),
      'hiddenCategories': _ids(p['hiddenCategories']),
      'savedAt': now,
    };

/// `v142NormalizeSavedOrderSnapshot`.
Map<String, dynamic>? normalizeOrderSnapshot(Object? raw, Map<String, dynamic> state, int now) {
  final m = asMap(raw);
  if (m == null) return null;
  final libIds = {for (final i in asList(readOnlyPart(state, 'library'))) jsStr(asMap(i)?['id'])}..remove('');
  final cats = [for (final c in asList(readOnlyPart(state, 'categories'))) jsStr(asMap(c)?['id'])]..removeWhere((x) => x.isEmpty);
  final catIds = cats.toSet();
  List<String> unique(Object? v, Set<String> allowed) {
    final out = <String>[];
    for (final x in asList(v)) {
      final id = jsStr(x);
      if (id.isNotEmpty && !out.contains(id) && allowed.contains(id)) out.add(id);
    }
    return out;
  }

  final titleIds = unique(m['titleIds'], libIds);
  if (titleIds.isEmpty) return null;
  final order = unique(m['categoryOrder'], catIds);
  for (final c in cats) {
    if (!order.contains(c)) order.add(c);
  }
  final saved = jsNum(m['savedAt']);
  return {
    'titleIds': titleIds,
    'viewMode': m['viewMode'] == 'category' ? 'category' : 'all',
    'categoryMode': m['categoryMode'] == 'custom' ? 'custom' : 'default',
    'categoryOrder': order,
    'hiddenCategories': unique(m['hiddenCategories'], catIds),
    'savedAt': saved > 0 ? jsOut(saved) : now,
  };
}

/// `v142ConfirmClearOrder` (keeps one recovery copy; no XP, like the website).
void orderClear(Map<String, dynamic> state, int now) {
  final p = ensureOrderPlan(state);
  if (_ids(p['titleIds']).isEmpty) return;
  p['lastClearedOrder'] = orderSnapshot(p, now);
  p['titleIds'] = <String>[];
  p['modifiedAt'] = now;
}

/// `v142RestoreLastOrder`. Returns how many titles came back.
int orderRestoreLast(Map<String, dynamic> state, int now) {
  final p = ensureOrderPlan(state);
  final last = normalizeOrderSnapshot(p['lastClearedOrder'], state, now);
  if (last == null) {
    p['lastClearedOrder'] = null;
    return 0;
  }
  p['titleIds'] = [...last['titleIds'] as List];
  p['viewMode'] = last['viewMode'];
  p['categoryMode'] = last['categoryMode'];
  p['categoryOrder'] = [...last['categoryOrder'] as List];
  p['hiddenCategories'] = [...last['hiddenCategories'] as List];
  p['lastClearedOrder'] = null;
  p['modifiedAt'] = now;
  return (p['titleIds'] as List).length;
}

/// `v142OrderExportPayload`.
Map<String, dynamic> orderExport(Map<String, dynamic> state, DateTime now) {
  final p = ensureOrderPlan(state);
  final byId = {for (final i in asList(readOnlyPart(state, 'library'))) jsStr(asMap(i)?['id']): asMap(i)};
  final cats = {for (final c in asList(readOnlyPart(state, 'categories'))) jsStr(asMap(c)?['id']): jsStr(asMap(c)?['name'])};
  final ids = _ids(p['titleIds']);
  // 8.1.1: the website's v287/v288 additions (Collections assigned to task
  // categories, their queues and the queue view), so an Order moved between
  // the app and the website keeps them.
  final assignments = [for (final a in asList(p['collectionAssignments'])) if (asMap(a) != null) jsonClone(a)];
  final assignedCollections = {for (final a in assignments) jsStr(asMap(a)?['collectionId'])};
  return {
    'format': 'MediaFlowOrder',
    'formatVersion': 5,
    'mediaFlowVersion': websiteRelease,
    'exportedAt': now.toUtc().toIso8601String(),
    'orderPlan': {
      'titleIds': [...{...ids}],
      'viewMode': p['viewMode'],
      'categoryMode': p['categoryMode'],
      'categoryOrder': _ids(p['categoryOrder']),
      'hiddenCategories': _ids(p['hiddenCategories']),
      'collectionAssignments': assignments,
      'categoryQueues': jsonClone(asMap(p['categoryQueues']) ?? const <String, dynamic>{}),
      if (asMap(p['v288QueueView']) != null) 'v288QueueView': jsonClone(p['v288QueueView']),
    },
    'collections': [
      for (final c in asList(readOnlyPart(state, 'collections')).map(asMap).whereType<Map<String, dynamic>>())
        if (assignedCollections.contains(jsStr(c['id'])))
          {'id': jsStr(c['id']), 'title': jsStr(c['title']), 'description': jsStr(c['description'])},
    ],
    'exportAudit': {
      'release': websiteRelease,
      'includes': ['collectionAssignments', 'categoryQueues', 'collectionReferences'],
    },
    'titles': [
      for (final id in ids)
        if (byId[id] != null)
          {
            'id': id,
            'title': cleanTitle(byId[id]!['title']),
            'categoryId': jsStr(byId[id]!['categoryId']),
            'categoryName': cats[jsStr(byId[id]!['categoryId'])] ?? '',
            'externalIds': {...?asMap(byId[id]!['externalIds'])},
          },
    ],
    'categories': [for (final e in cats.entries) if (e.key.isNotEmpty) {'id': e.key, 'name': e.value}],
  };
}

/// `v142ImportOrder`: matches the file's titles to this Library (id, then
/// External IDs, then title + category). Returns counts or an error.
({int imported, int skipped, String? error}) orderImport(Map<String, dynamic> state, Object? data, int now) {
  final d = asMap(data);
  final rawPlan = asMap(d?['orderPlan']) ?? (d?['titleIds'] is List ? d : null);
  if (rawPlan == null || rawPlan['titleIds'] is! List) return (imported: 0, skipped: 0, error: 'This is not a MediaFlow Order export.');
  final importedCats = asList(d?['categories']).map(asMap).whereType<Map<String, dynamic>>().toList();
  final lib = asList(readOnlyPart(state, 'library')).map(asMap).whereType<Map<String, dynamic>>().toList();
  final cats = asList(readOnlyPart(state, 'categories')).map(asMap).whereType<Map<String, dynamic>>().toList();
  final byId = {for (final i in lib) jsStr(i['id']): i};
  String key(Object? t) => cleanTitle(t).trim().toLowerCase();
  String mapCat(Object? raw) {
    final id = jsStr(raw);
    if (id.isNotEmpty && cats.any((c) => jsStr(c['id']) == id)) return id;
    final src = importedCats.where((c) => jsStr(c['id']) == id).firstOrNull;
    final name = jsStr(src?['name']).trim().toLowerCase();
    if (name.isEmpty) return '';
    return jsStr(cats.where((c) => jsStr(c['name']).trim().toLowerCase() == name).firstOrNull?['id']);
  }

  final desc = {
    for (final t in asList(d?['titles']).map(asMap).whereType<Map<String, dynamic>>())
      if (t['id'] != null) jsStr(t['id']): t,
  };
  Map<String, dynamic>? find(Map<String, dynamic> t) {
    final direct = byId[jsStr(t['id'])];
    if (direct != null) return direct;
    final ext = (asMap(t['externalIds']) ?? const {}).entries.where((e) => e.value != null && jsStr(e.value).isNotEmpty).toList();
    if (ext.isNotEmpty) {
      for (final i in lib) {
        final ids = asMap(i['externalIds']);
        if (ids != null && ext.any((e) => ids[e.key] != null && jsStr(ids[e.key]) == jsStr(e.value))) return i;
      }
    }
    final k = key(t['title']);
    if (k.isEmpty) return null;
    final all = lib.where((i) => key(i['title']) == k).toList();
    if (all.isEmpty) return null;
    final mc = mapCat(t['categoryId']);
    if (mc.isNotEmpty) {
      final hit = all.where((i) => jsStr(i['categoryId']) == mc).firstOrNull;
      if (hit != null) return hit;
    }
    final cn = jsStr(t['categoryName']).trim().toLowerCase();
    if (cn.isNotEmpty) {
      final hit = all.where((i) => jsStr(cats.where((c) => jsStr(c['id']) == jsStr(i['categoryId'])).firstOrNull?['name']).trim().toLowerCase() == cn).firstOrNull;
      if (hit != null) return hit;
    }
    return all.length == 1 ? all.first : null;
  }

  final resolved = <String>[];
  var skipped = 0;
  for (final raw in asList(rawPlan['titleIds'])) {
    final id = jsStr(raw);
    var item = byId[id];
    if (item == null && desc[id] != null) item = find(desc[id]!);
    if (item == null || jsStr(item['id']).isEmpty) {
      skipped++;
      continue;
    }
    final iid = jsStr(item['id']);
    if (!resolved.contains(iid)) resolved.add(iid);
  }
  if (resolved.isEmpty) return (imported: 0, skipped: skipped, error: 'None of the exported titles could be matched to your current Library.');
  final p = ensureOrderPlan(state);
  if (_ids(p['titleIds']).isNotEmpty) p['lastClearedOrder'] = orderSnapshot(p, now);
  List<String> mapList(Object? v) {
    final out = <String>[];
    for (final x in asList(v)) {
      final m = mapCat(x);
      if (m.isNotEmpty && !out.contains(m)) out.add(m);
    }
    return out;
  }

  final order = mapList(rawPlan['categoryOrder']);
  for (final c in cats) {
    final id = jsStr(c['id']);
    if (!order.contains(id)) order.add(id);
  }
  p['titleIds'] = resolved;
  p['viewMode'] = rawPlan['viewMode'] == 'category' ? 'category' : 'all';
  p['categoryMode'] = rawPlan['categoryMode'] == 'custom' ? 'custom' : 'default';
  p['categoryOrder'] = order;
  p['hiddenCategories'] = mapList(rawPlan['hiddenCategories']);
  p['modifiedAt'] = now;
  // 8.1.1: website v287 — Collection assignments and category queues come
  // along: Collections by id or by title, categories by id or by name, titles
  // in queues by the same matching as above.
  final rawAssignments = asList(rawPlan['collectionAssignments']).map(asMap).whereType<Map<String, dynamic>>().toList();
  if (rawAssignments.isNotEmpty) {
    final cols = asList(readOnlyPart(state, 'collections')).map(asMap).whereType<Map<String, dynamic>>().toList();
    final colDesc = asList(d?['collections']).map(asMap).whereType<Map<String, dynamic>>().toList();
    String mapCollection(Object? raw) {
      final id = jsStr(raw);
      if (id.isNotEmpty && cols.any((c) => jsStr(c['id']) == id)) return id;
      final src = colDesc.where((c) => jsStr(c['id']) == id).firstOrNull;
      final title = jsStr(src?['title']).trim().toLowerCase();
      if (title.isEmpty) return '';
      return jsStr(cols.where((c) => jsStr(c['title']).trim().toLowerCase() == title).firstOrNull?['id']);
    }

    final assignmentMap = <String, String>{};
    final next = <Map<String, dynamic>>[];
    for (final raw in rawAssignments) {
      final col = mapCollection(raw['collectionId']), cat = mapCat(raw['categoryId']);
      if (col.isEmpty || cat.isEmpty) continue;
      if (next.any((a) => a['collectionId'] == col && a['categoryId'] == cat)) continue;
      final rid = jsStr(raw['id']);
      final id = rid.isNotEmpty && !next.any((a) => a['id'] == rid) ? rid : 'oca_${mediaFlowUid()}';
      next.add({...raw, 'id': id, 'collectionId': col, 'categoryId': cat});
      assignmentMap[rid] = id;
    }
    p['collectionAssignments'] = next;
    final queues = <String, dynamic>{};
    for (final e in (asMap(rawPlan['categoryQueues']) ?? const <String, dynamic>{}).entries) {
      final cid = mapCat(e.key);
      if (cid.isEmpty) continue;
      final mapped = <String>[];
      for (final raw in asList(e.value)) {
        final token = jsStr(raw);
        if (token.startsWith('t:')) {
          final old = token.substring(2);
          final item = byId[old] ?? (desc[old] != null ? find(desc[old]!) : null);
          final tid = jsStr(item?['id']);
          if (tid.isNotEmpty && !mapped.contains('t:$tid')) mapped.add('t:$tid');
        } else if (token.startsWith('c:')) {
          final aid = assignmentMap[token.substring(2)];
          if (aid != null && !mapped.contains('c:$aid')) mapped.add('c:$aid');
        }
      }
      queues[cid] = mapped;
    }
    p['categoryQueues'] = queues;
    ensureOrderPlan(state); // normalize like the website
  }
  final view = asMap(rawPlan['v288QueueView']);
  if (view != null) asMap(state['orderPlan'])?['v288QueueView'] = jsonClone(view);
  return (imported: resolved.length, skipped: skipped, error: null);
}

/// The website version the app matches (the last part of the app's version).
int get websiteRelease => int.tryParse(kAppVersionLabel.split('.').last) ?? 575;

/// `v138MoveTitle` / `v138MoveTitleInCategory` / `v157SetOrderTitlePosition`.
void orderMoveTitle(Map<String, dynamic> p, Map<String, dynamic> state, String id, {int delta = 0, int? toPosition, String? categoryId}) {
  final ids = _ids(p['titleIds']);
  if (categoryId == null) {
    final i = ids.indexOf(id);
    if (i < 0) return;
    final j = (toPosition ?? i + delta).clamp(0, ids.length - 1);
    if (i == j) return;
    if (toPosition == null) {
      final t = ids[i];
      ids[i] = ids[j];
      ids[j] = t;
    } else {
      ids.insert(j, ids.removeAt(i));
    }
    p['titleIds'] = ids;
    return;
  }
  final catOf = {for (final i in asList(readOnlyPart(state, 'library'))) jsStr(asMap(i)?['id']): jsStr(asMap(i)?['categoryId'])};
  final positions = [for (var k = 0; k < ids.length; k++) if (catOf[ids[k]] == categoryId) k];
  final subset = [for (final k in positions) ids[k]];
  final i = subset.indexOf(id);
  if (i < 0) return;
  final j = (toPosition ?? i + delta).clamp(0, subset.length - 1);
  if (i == j) return;
  if (toPosition == null) {
    final t = subset[i];
    subset[i] = subset[j];
    subset[j] = t;
  } else {
    subset.insert(j, subset.removeAt(i));
  }
  for (var k = 0; k < positions.length; k++) {
    ids[positions[k]] = subset[k];
  }
  p['titleIds'] = ids;
}

void orderSetCategoryMode(Map<String, dynamic> p, Map<String, dynamic> state, String mode) {
  p['categoryMode'] = mode == 'custom' ? 'custom' : 'default';
  if (mode == 'custom') {
    final current = asList(state['categories']).map((c) => jsStr(asMap(c)?['id'])).toList();
    final order = [for (final id in _ids(p['categoryOrder'])) if (current.contains(id)) id];
    for (final id in current) {
      if (!order.contains(id)) order.add(id);
    }
    p['categoryOrder'] = order;
  }
}

void orderToggleCategory(Map<String, dynamic> p, String id) {
  final hidden = _ids(p['hiddenCategories']);
  hidden.contains(id) ? hidden.remove(id) : hidden.add(id);
  p['hiddenCategories'] = hidden;
}

List<String> orderCategoryDisplay(Map<String, dynamic> p, Map<String, dynamic> state) {
  final cats = asList(state['categories']).map((c) => jsStr(asMap(c)?['id'])).toList();
  if (p['categoryMode'] != 'custom') return cats;
  final ids = [for (final id in _ids(p['categoryOrder'])) if (cats.contains(id)) id];
  for (final c in cats) {
    if (!ids.contains(c)) ids.add(c);
  }
  return ids;
}

void orderMoveCategory(Map<String, dynamic> p, Map<String, dynamic> state, String id, int delta) {
  if (p['categoryMode'] != 'custom') return;
  final ids = orderCategoryDisplay(p, state);
  final i = ids.indexOf(id), j = i + delta;
  if (i < 0 || j < 0 || j >= ids.length) return;
  final t = ids[i];
  ids[i] = ids[j];
  ids[j] = t;
  p['categoryOrder'] = ids;
}

/// `v287AddCollectionAssignment`. Returns an error message or null.
String? orderAssignCollection(Map<String, dynamic> p, String collectionId, String categoryId, int now, String Function() uid) {
  final list = asList(p['collectionAssignments']).map(asMap).whereType<Map<String, dynamic>>().toList();
  if (list.any((a) => jsStr(a['collectionId']) == collectionId && jsStr(a['categoryId']) == categoryId)) {
    return 'That Collection is already assigned to this task category.';
  }
  p['collectionAssignments'] = [
    ...list,
    {'id': 'oca_${uid()}', 'collectionId': collectionId, 'categoryId': categoryId, 'categoryRule': 'match', 'completedRule': 'skip', 'traversedTitleIds': <String>[], 'createdAt': now, 'modifiedAt': now},
  ];
  return null;
}

void orderSetAssignmentRule(Map<String, dynamic> p, String id, String key, String value, int now) {
  for (final a in asList(p['collectionAssignments']).map(asMap).whereType<Map<String, dynamic>>()) {
    if (jsStr(a['id']) != id) continue;
    if (key == 'categoryRule') a['categoryRule'] = value == 'force' ? 'force' : 'match';
    if (key == 'completedRule') a['completedRule'] = value == 'include' ? 'include' : 'skip';
    if (key == 'reset') a['traversedTitleIds'] = <String>[];
    a['modifiedAt'] = now;
  }
}

void orderRemoveAssignment(Map<String, dynamic> p, String id) {
  final a = asList(p['collectionAssignments']).map(asMap).where((x) => jsStr(x?['id']) == id).firstOrNull;
  if (a == null) return;
  p['collectionAssignments'] = [for (final x in asList(p['collectionAssignments'])) if (jsStr(asMap(x)?['id']) != id) x];
  final queues = asMap(p['categoryQueues']);
  final cid = jsStr(a['categoryId']);
  if (queues != null && queues[cid] is List) queues[cid] = [for (final t in _ids(queues[cid])) if (t != 'c:$id') t];
}

/// `v287MoveAssignment` / `v287SetAssignmentPosition` (moves a token in its category queue).
void orderMoveQueueToken(Map<String, dynamic> state, Map<String, dynamic> p, String categoryId, String token, {int delta = 0, int? toIndex}) {
  final q = Recommender(state, now: 0).reconcileQueue(categoryId).toList();
  final i = q.indexOf(token);
  if (i < 0) return;
  final j = (toIndex ?? i + delta).clamp(0, q.length - 1);
  if (i == j) return;
  q.insert(j, q.removeAt(i));
  final queues = asMap(p['categoryQueues']) ?? <String, dynamic>{};
  queues[categoryId] = q;
  p['categoryQueues'] = queues;
  if (token.startsWith('c:')) {
    for (final a in asList(p['collectionAssignments']).map(asMap).whereType<Map<String, dynamic>>()) {
      if ('c:${jsStr(a['id'])}' == token) a['modifiedAt'] = DateTime.now().millisecondsSinceEpoch;
    }
  }
}
