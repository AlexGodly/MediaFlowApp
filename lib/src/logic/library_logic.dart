// Library actions, ported from the website: the title editor (saveLibraryModal
// with its v44 edit XP, v348 multipliers, v425 cover-change XP, completion
// timeline, v174 recommended-title sync, Library History entry and the
// persistLibrary reward hooks), deleting titles, quick status changes, the
// batch actions, Fix completed progress, and Rate Your Library (v123).

import 'dart:math' as math;

import '../state/lazy_copy.dart';
import '../util/js.dart';
import 'activity.dart';
import 'leveling.dart';
import 'library_hooks.dart';
import 'title_names.dart';

List<Map<String, dynamic>> libraryOf(Map<String, dynamic> state) =>
    asList(state['library']).map(asMap).whereType<Map<String, dynamic>>().toList();

Map<String, dynamic>? findTitle(Map<String, dynamic> state, String id) =>
    libraryOf(state).where((i) => jsStr(i['id']) == id).firstOrNull;

Map<String, dynamic> _ledger(Map<String, dynamic> state) => ledgerOf(state);

/// `v348RaiseNewRewards` for one ledger map after a base award.
double _raise(Map<String, dynamic> state, String key, Map<String, dynamic> before, int now, String Function() uid) {
  final l = Leveling(state);
  if (!l.enabled) return 0;
  final ledger = _ledger(state);
  for (final k in const ['v348ActionEvents', 'v348LibraryAdditionBonus', 'v348LibraryCompletionBonus', 'v348EventMeta']) {
    mapIn(ledger, k);
  }
  final after = mapIn(ledger, key);
  final mult = awardMultiplier(l, asList(readOnlyPart(state, 'sessions')), now);
  var total = 0.0;
  for (final e in after.entries.toList()) {
    final added = math.max(0.0, jsNum(e.value) - jsNum(before[e.key]));
    if (added <= 0) continue;
    final xp = math.max(0.0, jsRound(added * mult));
    final inc = xp - added;
    if (inc > 0) after[e.key] = jsOut(jsNum(e.value) + inc);
    mapIn(ledger, 'v348EventMeta')['$key:${e.key}:$now:${uid()}'] = {
      'kind': key,
      'baseXP': jsOut(added),
      'multiplier': jsOut(mult),
      'xp': jsOut(xp),
      'timestamp': now,
      'source': const {'libraryEdits': 'Library · edited title', 'manualCovers': 'Library · manual cover', 'ratings': 'Rating reward', 'libraryAdditions': 'Library · new title'}[key] ?? key,
      'subjectId': e.key,
    };
    total += xp;
  }
  return total;
}

/// `v44AwardEditXP` (+ v348).
double awardEditXP(Map<String, dynamic> state, String id, int now, String Function() uid) {
  final l = Leveling(state);
  if (id.isEmpty || !l.enabled) return 0;
  final map = mapIn(_ledger(state), 'libraryEdits');
  final before = Map<String, dynamic>.from(map);
  final xp = math.max(0.0, jsRound(l.reward('libraryEditXP')));
  map[id] = jsOut(jsNum(map[id]) + xp);
  return _raise(state, 'libraryEdits', before, now, uid) == 0 ? xp : jsNum(map[id]) - jsNum(before[id]);
}

/// `v348Award(kind, amount, details)`.
double v348Award(Map<String, dynamic> state, String kind, int amount, int now, String Function() uid,
    {String description = '', String subjectId = ''}) {
  final l = Leveling(state);
  if (!l.enabled) return 0;
  final quantity = math.max(0, amount);
  if (quantity == 0) return 0;
  final rate = l.reward(kind);
  final mult = awardMultiplier(l, asList(readOnlyPart(state, 'sessions')), now);
  final xp = math.max(0.0, jsRound(quantity * rate * mult));
  if (xp == 0) return 0;
  final ledger = _ledger(state);
  final key = '$kind:${uid()}';
  mapIn(ledger, 'v348ActionEvents')[key] = jsOut(xp);
  for (final k in const ['v348LibraryAdditionBonus', 'v348LibraryCompletionBonus']) {
    mapIn(ledger, k);
  }
  mapIn(ledger, 'v348EventMeta')[key] = {
    'kind': kind,
    'baseXP': jsOut(quantity * rate),
    'multiplier': jsOut(mult),
    'xp': jsOut(xp),
    'timestamp': now,
    'source': kind == 'coverChangeXP' ? 'Library · cover updated' : _v348Label(kind),
    'details': description.length > 300 ? description.substring(0, 300) : description,
    'subjectId': subjectId,
    'quantity': quantity,
  };
  return xp;
}

String _v348Label(String kind) => const {
      'collectionAddTitleXP': 'Collection · added titles',
      'collectionReorderTitleXP': 'Collection · reordered titles',
      'orderAddTitleXP': 'Personal Order · added titles',
      'orderAddCollectionXP': 'Personal Order · assigned Collection',
      'orderReorderTitleXP': 'Personal Order · reordered titles',
      'orderReorderCollectionXP': 'Personal Order · reordered Collections',
      'batchLogXP': 'Batch Log bonus',
    }[kind] ??
    kind;

/// `mf425Credit`: one XP event per real cover change.
double coverCredit(Map<String, dynamic> state, Map<String, dynamic> item, String before, String after, String source, int now,
    String Function() uid) {
  if (jsStr(item['id']).isEmpty || after.isEmpty || before == after) return 0;
  final settings = asMap(state['settings']);
  final lev = asMap(settings?['leveling']);
  if (lev?['enabled'] == false) return 0;
  final s = settings ?? <String, dynamic>{};
  state['settings'] = s;
  final leveling = asMap(s['leveling']) ?? <String, dynamic>{};
  s['leveling'] = leveling;
  if (!leveling.containsKey('coverChangeXP') || jsNumOrNull(leveling['coverChangeXP']) == null || !jsNum(leveling['coverChangeXP']).isFinite) {
    final manual = jsNum(leveling['manualCoverXP']);
    leveling['coverChangeXP'] = jsOut(math.max(1.0, manual == 0 || manual.isNaN ? 15.0 : manual));
  }
  if (jsRound(jsNum(leveling['coverChangeXP'])) <= 0) return 0;
  return v348Award(state, 'coverChangeXP', 1, now, uid,
      description: '$source · cover changed for ${cleanTitle(item['title'])}', subjectId: jsStr(item['id']));
}

/// The editor version of `awardLibraryAdditionXP` (+ v348).
double awardAddition(Map<String, dynamic> state, String id, int now, String Function() uid) {
  final l = Leveling(state);
  final ledger = _ledger(state);
  final additions = mapIn(ledger, 'libraryAdditions');
  final before = Map<String, dynamic>.from(additions);
  if (jsTruthy(additions[id])) return 0;
  final base = math.max(0.0, jsRound(l.reward('libraryAdditionXP')));
  additions[id] = jsOut(base);
  _raise(state, 'libraryAdditions', before, now, uid);
  if (l.enabled) {
    final bonus = mapIn(ledger, 'v348LibraryAdditionBonus');
    if (!bonus.containsKey(id) && !before.containsKey(id) && additions.containsKey(id)) {
      final mult = awardMultiplier(l, asList(readOnlyPart(state, 'sessions')), now);
      final xp = jsRound(base * mult);
      bonus[id] = jsOut(math.max(0.0, xp - base));
      mapIn(ledger, 'v348EventMeta')['library-add:$id'] = {
        'kind': 'libraryAdditions', 'baseXP': jsOut(base), 'multiplier': jsOut(mult), 'xp': jsOut(xp),
        'timestamp': now, 'source': 'Library · new title', 'subjectId': id,
      };
    }
  }
  return base;
}

/// Values from the title editor.
class TitleFields {
  TitleFields({
    required this.title,
    required this.categoryId,
    this.progress = 0,
    this.total,
    this.status = 'planned',
    this.priority = 'medium',
    this.estimatedMinutes,
    this.tags = const [],
    this.rating,
    this.coverUrl = '',
    this.coverAuto = false,
    this.repeatFull = 0,
    this.repeatExtra = 0,
    this.startedAt,
    this.startEdited = false,
    this.completedAt,
    this.seasons,
    this.extras,
  });

  final String title, categoryId, status, priority, coverUrl;
  final double progress;
  final double? total, estimatedMinutes, rating;
  final List<String> tags;
  final bool coverAuto, startEdited;
  final int repeatFull, repeatExtra;
  final int? startedAt, completedAt;

  /// When set, the title's seasons (v252 editor rows: name, progress, total).
  final List<Map<String, dynamic>>? seasons;

  /// v565: the editor's unit, runtime and names (null: not shown, nothing changes).
  final TitleExtras? extras;

  static TitleFields of(Map<String, dynamic> item) {
    final total = jsNumOrNull(item['total']);
    final manual = math.max(0, jsNum(item['manualRepeatAmount']).floor());
    final t = total != null && total > 0 ? total.toInt() : 0;
    return TitleFields(
      title: cleanTitle(item['title']),
      categoryId: jsStr(item['categoryId']),
      progress: jsNum(item['progress']),
      total: item['total'] == null ? null : total,
      status: jsStr(item['status']).isEmpty ? 'planned' : jsStr(item['status']),
      priority: jsStr(item['priority']).isEmpty ? 'medium' : jsStr(item['priority']),
      estimatedMinutes: item['estimatedMinutes'] == null ? null : jsNum(item['estimatedMinutes']),
      tags: asList(item['tags']).map(jsStr).toList(),
      rating: jsNum(item['rating']) > 0 ? jsNum(item['rating']) : null,
      coverUrl: jsStr(item['coverUrl']),
      coverAuto: item['coverSource'] == 'auto',
      repeatFull: t > 0 ? manual ~/ t : 0,
      repeatExtra: t > 0 ? manual % t : manual,
      startedAt: jsNum(item['startedAt']) > 0 ? jsNum(item['startedAt']).toInt() : null,
      completedAt: jsNum(item['completedAt']) > 0 ? jsNum(item['completedAt']).toInt() : null,
    );
  }
}

int _dayKey(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return d.year * 10000 + d.month * 100 + d.day;
}

/// `App.saveLibraryModal` (the editor and its wrappers). Returns an error
/// message, or null when saved; [saved] receives the title id and XP earned.
String? saveTitle(Map<String, dynamic> state, String? id, TitleFields f, int now, String Function() uid,
    {void Function(String id, double xp)? saved}) {
  final old = id == null ? null : findTitle(state, id);
  final status = f.status;
  // The editor's date fields hold days: saving re-reads them as local noon (v135ParseDateInput).
  int? noon(int? ms) {
    if (ms == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(d.year, d.month, d.day, 12).millisecondsSinceEpoch;
  }
  final startedAt = noon(f.startedAt);
  String? startedAtSource;
  if (startedAt != null) {
    if (f.startEdited) {
      startedAtSource = 'manual';
    } else if (old != null && jsNum(old['startedAt']) > 0 && _dayKey(jsNum(old['startedAt']).toInt()) == _dayKey(startedAt)) {
      startedAtSource = jsStr(old['startedAtSource']).isEmpty ? null : jsStr(old['startedAtSource']);
    } else {
      startedAtSource = 'manual';
    }
  }
  int? completedAt;
  if (status == 'completed') completedAt = f.completedAt != null ? noon(f.completedAt) : (jsNum(old?['completedAt']) > 0 ? jsNum(old!['completedAt']).toInt() : now);
  if (startedAt != null && completedAt != null && completedAt < startedAt) return 'Finish date cannot be before Start date.';

  final before = coreSnapshot(state);
  final tracker = LibraryTracker(state);
  final cover = f.coverUrl.trim();
  final total = f.total == null ? null : math.max(0.0, f.total!);
  final repeat = () {
    final t = total ?? 0;
    final full = math.max(0, f.repeatFull);
    var extra = math.max(0, f.repeatExtra);
    if (t > 0) extra = math.min(extra, math.max(0, t.toInt() - 1));
    return t > 0 ? full * t.toInt() + extra : extra;
  }();
  final rating = f.rating == null ? null : f.rating!.clamp(0, 10).toDouble();
  final data = <String, dynamic>{
    ...?old,
    'id': id ?? uid(),
    'title': cleanTitle(f.title).isEmpty ? 'Untitled' : cleanTitle(f.title),
    'categoryId': f.categoryId,
    'progress': jsOut(math.max(0.0, f.progress)),
    'total': total == null ? null : jsOut(total),
    'status': status,
    'priority': f.priority,
    'estimatedMinutes': f.estimatedMinutes == null ? null : jsOut(f.estimatedMinutes!),
    'tags': f.tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
    'rating': rating == null || rating == 0 ? null : jsOut(rating),
    'coverUrl': cover,
    'coverSource': cover.isEmpty ? '' : (f.coverAuto ? 'auto' : 'manual'),
    'manualRepeatAmount': repeat,
    'startedAt': startedAt,
    'startedAtSource': startedAt == null ? null : startedAtSource,
    'createdAt': id != null ? (old?['createdAt'] ?? now) : now,
    'completedAt': status == 'completed' ? (completedAt ?? now) : null,
    'modifiedAt': now,
  };
  {
    // v178 / v377: the editor saves its (empty) rich-metadata and id fields when a title lacks them.
    const empty = <String, Object?>{
      'year': null, 'mediaFormat': '', 'durationMinutes': null, 'releaseDate': '', 'seasonLabel': '', 'ageRating': '',
      'communityScore': null, 'mediaSource': '', 'demographic': '', 'synopsis': '',
    };
    for (final e in empty.entries) {
      data.putIfAbsent(e.key, () => e.value);
    }
    for (final k in const ['studios', 'producers', 'genres', 'themes']) {
      data.putIfAbsent(k, () => <dynamic>[]);
    }
    data.putIfAbsent('richMetadataManual', () => <String, dynamic>{});
    data.putIfAbsent('externalIds', () => <String, dynamic>{});
  }
  if (f.seasons != null) {
    data['seasons'] = [
      for (var i = 0; i < f.seasons!.length; i++)
        {
          ...f.seasons![i],
          'id': jsStr(f.seasons![i]['id']).isEmpty ? 'season_${uid()}' : f.seasons![i]['id'],
          'name': jsStr(f.seasons![i]['name']).isEmpty ? 'Season ${i + 1}' : jsStr(f.seasons![i]['name']),
          'progress': jsOut(math.max(0.0, jsNum(f.seasons![i]['progress']))),
          'total': f.seasons![i]['total'] == null ? null : jsOut(math.max(0.0, jsNum(f.seasons![i]['total']))),
        },
    ];
  }
  // Keep the completion timeline in step with the Finish date.
  final timeline = [
    for (final x in asList(state['completionTimeline']))
      if (jsStr(asMap(x)?['libraryId']) != jsStr(data['id'])) x,
  ];
  if (data['status'] == 'completed') {
    timeline.add({'libraryId': data['id'], 'title': data['title'], 'categoryId': data['categoryId'], 'completedAt': data['completedAt']});
  }
  state['completionTimeline'] = timeline;

  final lib = List<dynamic>.of(asList(state['library']));
  final idx = lib.indexWhere((i) => jsStr(asMap(i)?['id']) == id);
  var earned = 0.0;
  if (idx >= 0) {
    lib[idx] = data;
    state['library'] = lib;
    earned += awardEditXP(state, jsStr(data['id']), now, uid);
    if (data['coverSource'] == 'manual' && cover.isNotEmpty && cover != jsStr(old?['coverUrl'])) {
      earned += coverCredit(state, data, '', cover, 'manual', now, uid);
    }
  } else {
    lib.add(data);
    state['library'] = lib;
    earned += awardAddition(state, jsStr(data['id']), now, uid);
    if (data['coverSource'] == 'manual' && cover.isNotEmpty) {
      earned += coverCredit(state, data, '', cover, 'manual', now, uid);
    }
  }
  // v174: the open recommendation shows the edited title.
  final task = asMap(state['currentTask']);
  if (id != null && task != null && jsStr(task['libraryId']) == id) task['title'] = data['title'];
  recordActivity(state, before: before, id: uid(), timestamp: now, action: id != null ? 'Edit title' : 'Add title', detail: jsStr(data['title']));
  // mf425: a cover found by search (auto) is still a real cover change.
  if (data['coverSource'] == 'auto' && cover.isNotEmpty && cover != jsStr(old?['coverUrl'])) {
    earned += coverCredit(state, data, jsStr(old?['coverUrl']), cover, 'title editor', now, uid);
  }
  earned += tracker.save(state, Leveling(state), now, uid);
  // v565 (mf565WriteEditor): unit, runtime and names are written after the save.
  f.extras?.writeTo(data, asList(old?['mf565Names']), now);
  saved?.call(jsStr(data['id']), earned);
  return null;
}

/// `App.confirmDeleteLibrary` / `mfBatchDelete`.
int deleteTitles(Map<String, dynamic> state, Set<String> ids, int now, String Function() uid) {
  final lib = libraryOf(state);
  final doomed = lib.where((i) => ids.contains(jsStr(i['id']))).toList();
  if (doomed.isEmpty) return 0;
  final before = coreSnapshot(state);
  final tracker = ids.length == 1 ? LibraryTracker(state) : null;
  state['library'] = [for (final i in asList(state['library'])) if (!ids.contains(jsStr(asMap(i)?['id']))) i];
  recordActivity(state,
      before: before,
      id: uid(),
      timestamp: now,
      action: ids.length == 1 ? 'Delete title' : 'Batch delete',
      detail: ids.length == 1 ? cleanTitle(doomed.first['title']) : '${doomed.length} titles');
  tracker?.save(state, Leveling(state), now, uid);
  return doomed.length;
}

/// `App.setLibraryStatus` (+ v120 edit XP).
void setStatus(Map<String, dynamic> state, String id, String value, int now, String Function() uid) {
  final item = findTitle(state, id);
  if (item == null || !const ['planned', 'active', 'paused', 'completed', 'dropped'].contains(value)) return;
  final tracker = LibraryTracker(state);
  if (jsStr(item['status']).isEmpty ? value != 'planned' : jsStr(item['status']) != value) awardEditXP(state, id, now, uid);
  item['status'] = value;
  final timeline = List<dynamic>.of(asList(state['completionTimeline']));
  if (value == 'completed') {
    if (!jsTruthy(item['completedAt'])) item['completedAt'] = now;
    if (!timeline.any((x) => jsStr(asMap(x)?['libraryId']) == id)) {
      timeline.add({'libraryId': item['id'], 'title': cleanTitle(item['title']), 'categoryId': item['categoryId'], 'completedAt': item['completedAt']});
    }
  } else {
    item['completedAt'] = null;
    timeline.removeWhere((x) => jsStr(asMap(x)?['libraryId']) == id);
  }
  state['completionTimeline'] = timeline;
  tracker.save(state, Leveling(state), now, uid);
}

/// `App.setPriorityChoice`.
void setPriority(Map<String, dynamic> state, String id, String value, int now, String Function() uid) {
  final item = findTitle(state, id);
  if (item == null || !const ['low', 'medium', 'high'].contains(value)) return;
  final tracker = LibraryTracker(state);
  item['priority'] = value;
  tracker.save(state, Leveling(state), now, uid);
}

/// The batch actions (`mfBatchStatus` / `mfBatchPriority` / `mfBatchCategory`).
int batchEdit(Map<String, dynamic> state, Set<String> ids, String kind, String value, int now, String Function() uid,
    {String categoryName = ''}) {
  final items = libraryOf(state).where((i) => ids.contains(jsStr(i['id']))).toList();
  if (items.isEmpty) return 0;
  final before = coreSnapshot(state);
  for (final i in items) {
    if (kind == 'status') {
      i['status'] = value;
      if (value == 'completed') {
        if (!jsTruthy(i['completedAt'])) i['completedAt'] = now;
      } else {
        i['completedAt'] = null;
      }
    } else if (kind == 'priority') {
      i['priority'] = value;
    } else if (kind == 'category') {
      i['categoryId'] = value;
    }
  }
  final n = items.length;
  final (action, detail) = switch (kind) {
    'status' => ('Batch status', '$n titles → $value'),
    'priority' => ('Batch priority', '$n titles → $value'),
    _ => ('Batch move', '$n titles → $categoryName'),
  };
  recordActivity(state, before: before, id: uid(), timestamp: now, action: action, detail: detail);
  return n;
}

/// `v69KnownTotal`: the title total, or the sum of its season totals.
double knownTotal(Map<String, dynamic> item) {
  final t = jsNum(item['total']);
  if (t > 0) return t;
  final seasons = asList(item['seasons']).map(asMap).whereType<Map<String, dynamic>>().toList();
  if (seasons.isNotEmpty && seasons.every((s) => jsNum(s['total']) > 0)) {
    return seasons.fold<double>(0, (a, s) => a + jsNum(s['total']));
  }
  return 0;
}

/// `v69RepairCompleted` (+ persistLibrary).
int repairCompleted(Map<String, dynamic> state, Set<String>? ids, int now, String Function() uid) {
  final tracker = LibraryTracker(state);
  var changed = 0;
  for (final item in libraryOf(state)) {
    if (ids != null && !ids.contains(jsStr(item['id']))) continue;
    final total = knownTotal(item);
    if (item['status'] == 'completed' && total > 0 && jsNum(item['progress']) != total) {
      item['progress'] = jsOut(total);
      if (!jsTruthy(item['completedAt'])) item['completedAt'] = now;
      changed++;
    }
  }
  if (changed > 0) tracker.save(state, Leveling(state), now, uid);
  return changed;
}

/// `v123ConfirmRating` (Rate Your Library). Returns the XP awarded.
double rateTitle(Map<String, dynamic> state, String id, double rating, int now, String Function() uid) {
  final item = findTitle(state, id);
  if (item == null || !(rating > 0) || rating > 10) return 0;
  final r = (rating * 10).round() / 10;
  final before = coreSnapshot(state);
  item['rating'] = jsOut(r);
  final ratings = mapIn(_ledger(state), 'ratings');
  final snap = Map<String, dynamic>.from(ratings);
  var xp = 0.0;
  if (!ratings.containsKey(id)) {
    final l = Leveling(state);
    xp = l.enabled ? math.max(0.0, jsRound(l.reward('ratingXP'))) : 0;
    ratings[id] = jsOut(xp); // stored even when 0
    _raise(state, 'ratings', snap, now, uid);
    xp = jsNum(ratings[id]);
  }
  recordActivity(state, before: before, id: uid(), timestamp: now, action: 'Rate title', detail: '${cleanTitle(item['title'])} · ${jsOut(r)}/10');
  return xp;
}

/// Sets a cover from the Missing Covers queue (mf425 credit, persistLibrary).
double setCover(Map<String, dynamic> state, String id, String url, int now, String Function() uid, {bool auto = false}) {
  final item = findTitle(state, id);
  if (item == null) return 0;
  final before = jsStr(item['coverUrl']);
  final next = url.trim();
  if (next == before) return 0;
  final tracker = LibraryTracker(state);
  item['coverUrl'] = next;
  item['coverSource'] = next.isEmpty ? '' : (auto ? 'auto' : 'manual');
  item['modifiedAt'] = now;
  final xp = next.isEmpty ? 0.0 : coverCredit(state, item, before, next, 'missing covers', now, uid);
  tracker.save(state, Leveling(state), now, uid);
  return xp;
}
