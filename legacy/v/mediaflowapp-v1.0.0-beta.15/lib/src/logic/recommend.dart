// MediaFlow Recommends: the website's task engine (MediaFlow v554), ported.
//
//   generateTask = computeScores → weightedPick → suggestedAmount → pickLibraryTitle
//   wrapped by v180 (exact-title recommendation history) and v287 (Personal Order
//   source annotation). Optional settings honoured: v186 scheduler scope, v480
//   category classes, v287 Personal Order queues + Collections, mf464 rating influence.
//
// Session actions (start / "Give me something else" / skip / end / title reroll)
// change only currentTask, sessionActive, respectState and — for skip — History,
// exactly like the website. Verified with test/recommendation_golden_test.dart.

import 'dart:math' as math;

import '../state/models.dart';
import '../util/js.dart';
import 'leveling.dart';
import 'library_hooks.dart';

typedef RandomSource = double Function();

final math.Random _rng = math.Random();
double defaultRandom() => _rng.nextDouble();

/// Stable sort (JavaScript's Array.prototype.sort is stable; Dart's is not).
void stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (v: list[i], i: i)];
  indexed.sort((a, b) {
    final c = compare(a.v, b.v);
    return c != 0 ? c : a.i - b.i;
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].v;
  }
}

int _cmpNum(double a, double b) => a < b ? -1 : (a > b ? 1 : 0);

const Map<String, num> _schedulerDefaults = {
  'neglectRate': 6,
  'neglectCap': 42,
  'repetitionPenalty': 12,
  'consecutivePenalty': 26,
  'saturationWeight': 20,
  'seasonalBonus': 15,
  'randomness': 0.28,
  'seasonalFreshCount': 0,
};

/// A scored category (`computeScores` row).
class ScoredCategory {
  ScoredCategory(this.cat, this.score, this.reasons);
  final Map<String, dynamic> cat;
  double score;
  final List<({String t, double w})> reasons;
  String get id => jsStr(cat['id']);
}

class Recommender {
  Recommender(this.state, {required this.now, RandomSource? random, String Function()? uid})
      : random = random ?? defaultRandom,
        uid = uid ?? (() => mediaFlowUid(now));

  final Map<String, dynamic> state;
  final int now;
  final RandomSource random;
  final String Function() uid;

  Map<String, dynamic> get settings => asMap(state['settings']) ?? const {};
  List<Map<String, dynamic>> get categories =>
      asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().toList();
  List<Map<String, dynamic>> get library =>
      asList(state['library']).map(asMap).whereType<Map<String, dynamic>>().toList();
  List<Map<String, dynamic>> get sessions =>
      asList(state['sessions']).map(asMap).whereType<Map<String, dynamic>>().toList();

  double _st(String key) {
    final v = jsNumFromKey(settings, key);
    return v ?? _schedulerDefaults[key]!.toDouble();
  }

  bool get exactTitles => jsTruthy(settings['exactTitleRecommendations']);
  bool get personalOrder => jsTruthy(settings['prioritizePersonalOrder']);

  Map<String, dynamic>? category(String id) {
    for (final c in categories) {
      if (jsStr(c['id']) == id) return c;
    }
    return null;
  }

  /// `getCategory`: a missing category falls back to the first one.
  Map<String, dynamic> getCategory(String id) =>
      category(id) ?? (categories.isNotEmpty ? categories.first : <String, dynamic>{'id': id, 'unit': 'episodes'});

  // ---- v186 scheduler scope ------------------------------------------------

  List<Map<String, dynamic>> schedulerCategories() {
    final cats = categories;
    final cc = asMap(settings['v186ControlCenter']);
    final scope = asMap(cc?['scheduler']);
    if (scope == null || scope['mode'] != 'custom') {
      return cats.where((c) => c['enabled'] != false).toList();
    }
    final valid = cats.map((c) => jsStr(c['id'])).where((x) => x.isNotEmpty).toSet();
    final Set<String> ids;
    if (scope['categoryIds'] is List) {
      ids = asList(scope['categoryIds']).map(jsStr).where(valid.contains).toSet();
    } else {
      ids = cats.where((c) => c['enabled'] != false).map((c) => jsStr(c['id'])).toSet();
    }
    return cats.where((c) => ids.contains(jsStr(c['id']))).toList();
  }

  // ---- history helpers -----------------------------------------------------

  List<Map<String, dynamic>> consumptionSessions() => sessions
      .where((s) => s['status'] != 'skipped' && (jsNum(s['minutes']) > 0 || jsNum(s['actualAmount']) > 0))
      .toList();

  Map<String, dynamic>? lastSessionFor(String catId) {
    Map<String, dynamic>? best;
    for (final s in sessions) {
      if (jsStr(s['categoryId']) == catId && (best == null || jsNum(s['timestamp']) > jsNum(best['timestamp']))) {
        best = s;
      }
    }
    return best;
  }

  double daysSince(Object? ts) {
    final t = jsNum(ts);
    if (!jsTruthy(ts) || t == 0) return double.infinity;
    return (now - t) / 86400000;
  }

  List<({double timestamp, Set<String> categoryIds})>? _events;

  /// `schedulerLogicalEvents`: one entry per logging action, newest first.
  List<({double timestamp, Set<String> categoryIds})> logicalEvents() {
    if (_events != null) return _events!;
    final rows = consumptionSessions();
    stableSort<Map<String, dynamic>>(rows, (a, b) => _cmpNum(jsNum(b['timestamp']), jsNum(a['timestamp'])));
    final groups = <String, ({double timestamp, Set<String> categoryIds})>{};
    final order = <String>[];
    var anon = 0;
    for (final s in rows) {
      final key = jsTruthy(s['sessionGroupId'])
          ? 'group:${jsStr(s['sessionGroupId'])}'
          : 'session:${jsTruthy(s['id']) ? jsStr(s['id']) : 'anon${anon++}'}';
      var g = groups[key];
      if (g == null) {
        g = (timestamp: jsNum(s['timestamp']), categoryIds: <String>{});
        groups[key] = g;
        order.add(key);
      }
      final ts = jsNum(s['timestamp']);
      if (ts > g.timestamp) {
        g = (timestamp: ts, categoryIds: g.categoryIds);
        groups[key] = g;
      }
      if (jsTruthy(s['categoryId'])) g.categoryIds.add(jsStr(s['categoryId']));
    }
    final list = [for (final k in order) groups[k]!];
    stableSort<({double timestamp, Set<String> categoryIds})>(list, (a, b) => _cmpNum(b.timestamp, a.timestamp));
    return _events = list;
  }

  // ---- balance / scores ----------------------------------------------------

  ({double consumptionRatio, double daysIdle}) categoryBalance(Map<String, dynamic> cat) {
    final enabled = schedulerCategories();
    double w(Object? v) {
      final n = jsNum(v);
      final x = n == 0 || n.isNaN ? 1.0 : n;
      return x < 0.25 ? 0.25 : x;
    }

    var weightTotal = enabled.fold<double>(0, (a, c) => a + w(c['weight']));
    if (weightTotal == 0) weightTotal = 1;
    final desiredShare = w(cat['weight']) / weightTotal;
    final all = consumptionSessions();
    const windows = [(days: 3, weight: .35, min: 60), (days: 7, weight: .25, min: 120), (days: 30, weight: .20, min: 240), (days: -1, weight: .20, min: 1)];
    var ratioSum = 0.0, usedWeight = 0.0;
    final id = jsStr(cat['id']);
    for (final win in windows) {
      final rows = win.days < 0 ? all : all.where((x) => jsNum(x['timestamp']) >= now - win.days * 86400000).toList();
      var total = 0.0, mine = 0.0;
      for (final x in rows) {
        final m = jsNum(x['minutes']);
        final v = m < 0 ? 0.0 : m;
        total += v;
        if (jsStr(x['categoryId']) == id) mine += v;
      }
      final actualShare = total > 0 ? mine / total : 0.0;
      final ratio = desiredShare > 0 ? actualShare / desiredShare : 1.0;
      if (total >= win.min) {
        ratioSum += math.min(6.0, ratio) * win.weight;
        usedWeight += win.weight;
      }
    }
    final consumptionRatio = usedWeight > 0 ? ratioSum / usedWeight : 1.0;
    final last = lastSessionFor(id);
    return (consumptionRatio: consumptionRatio, daysIdle: daysSince(last?['timestamp']));
  }

  List<ScoredCategory> computeScores(List<String> excludeIds) {
    final scope = schedulerCategories();
    var pool = scope.where((c) => !excludeIds.contains(jsStr(c['id']))).toList();
    if (pool.isEmpty) pool = scope;
    final events = logicalEvents();
    final recent = events.take(6).toList();
    final neglectCap = _st('neglectCap'), neglectRate = _st('neglectRate');
    final randomness = _st('randomness');
    final fresh = _st('seasonalFreshCount');
    return pool.map((cat) {
      final id = jsStr(cat['id']);
      final last = lastSessionFor(id);
      final dSince = daysSince(last?['timestamp']);
      final neglectBonus = last != null ? math.min(neglectCap, dSince * neglectRate) : neglectCap;
      final occurrences = recent.where((e) => e.categoryIds.contains(id)).length;
      final repetitionPenalty = occurrences * _st('repetitionPenalty');
      var streakLen = 0;
      for (final e in events) {
        if (e.categoryIds.contains(id)) {
          streakLen++;
        } else {
          break;
        }
      }
      final consecutivePenalty = streakLen * _st('consecutivePenalty');
      final ratio = categoryBalance(cat).consumptionRatio;
      final over = math.max(0.0, ratio - 1), under = math.max(0.0, 1 - ratio);
      final saturationPenalty = math.min(70.0, over * _st('saturationWeight') * 2.2);
      final balanceBonus = math.min(28.0, under * neglectCap * .55);
      final seasonal = jsTruthy(cat['seasonal']);
      final seasonalBonus = seasonal ? _st('seasonalBonus') + fresh * 4 : 0.0;
      final weightScore = jsNum(cat['weight']) * 8;
      final raw = weightScore + neglectBonus + balanceBonus + seasonalBonus - repetitionPenalty - consecutivePenalty - saturationPenalty;
      final floored = math.max(raw, 1.5);
      final jitter = floored * (random() * randomness * 2 - randomness);
      final score = math.max(floored + jitter, 0.5);

      final reasons = <({String t, double w})>[];
      if (last == null) {
        reasons.add((t: 'Never consumed yet', w: neglectCap));
      } else if (dSince >= 1) {
        reasons.add((t: 'Neglected for ${dSince.isFinite ? dSince.floor() : 'Infinity'}d', w: neglectBonus));
      }
      if (ratio >= 1.35) {
        reasons.add((t: 'Overrepresented across your consumption history — cooling off', w: -saturationPenalty));
      } else if (ratio <= .70 && last != null) {
        reasons.add((t: 'Underrepresented in your overall consumption — catching up', w: balanceBonus));
      }
      if (seasonal && fresh > 0) {
        reasons.add((t: '${jsOut(fresh)} seasonal title(s) have fresh episodes', w: seasonalBonus));
      } else if (seasonal) {
        reasons.add((t: 'Time-sensitive — airing now', w: seasonalBonus));
      }
      if (repetitionPenalty + consecutivePenalty > 4) {
        reasons.add((t: 'Appeared often in recent tasks', w: -(repetitionPenalty + consecutivePenalty)));
      }
      stableSort<({String t, double w})>(reasons, (a, b) => _cmpNum(b.w.abs(), a.w.abs()));
      return ScoredCategory(cat, score, reasons.take(3).toList());
    }).toList();
  }

  ScoredCategory? _basePick(List<ScoredCategory> scored) {
    if (scored.isEmpty) return null;
    final total = scored.fold<double>(0, (s, x) => s + x.score);
    var r = random() * total;
    for (final x in scored) {
      r -= x.score;
      if (r <= 0) return x;
    }
    return scored.last;
  }

  /// `weightedPick` with v480 category classes.
  ScoredCategory? weightedPick(List<ScoredCategory> scored) {
    final prefs = _v480Prefs();
    if (!prefs.enabled || prefs.classes.isEmpty || scored.isEmpty || !scored.every((x) => x.score.isFinite)) {
      return _basePick(scored);
    }
    final groups = _v480Groups(scored, prefs);
    if (groups.isEmpty) return null;
    final choices = <ScoredCategory>[];
    final byChoice = <ScoredCategory, _V480Group>{};
    for (final g in groups) {
      final info = _v480ClassScore(g, prefs, groups);
      final choice = ScoredCategory(const {}, info.score, [for (final t in info.reasons) (t: t, w: 0.0)]);
      choices.add(choice);
      byChoice[choice] = g;
    }
    final selected = _basePick(choices);
    if (selected == null) return _basePick(scored);
    final group = byChoice[selected]!;
    final picked = _basePick(group.rows);
    if (picked == null) return null;
    if (group.kind != 'class') return picked;
    return ScoredCategory(picked.cat, picked.score, [...selected.reasons, ...picked.reasons].take(3).toList());
  }

  ({int low, int high, double multiplier, String direction, double balanceRatio}) suggestedAmount(
      Map<String, dynamic> cat) {
    final targetRaw = jsNum(cat['target']);
    final t = math.max(1.0, targetRaw == 0 || targetRaw.isNaN ? 1.0 : targetRaw);
    final balance = categoryBalance(cat);
    final ratio = balance.consumptionRatio, idle = balance.daysIdle;
    var mult = 1.0;
    if (ratio >= 2.5) {
      mult *= .50;
    } else if (ratio >= 1.8) {
      mult *= .62;
    } else if (ratio >= 1.35) {
      mult *= .78;
    } else if (ratio <= .45) {
      mult *= 1.35;
    } else if (ratio <= .70) {
      mult *= 1.18;
    }
    if (idle.isFinite) {
      if (idle >= 60) {
        mult *= 1.65;
      } else if (idle >= 30) {
        mult *= 1.50;
      } else if (idle >= 14) {
        mult *= 1.32;
      } else if (idle >= 7) {
        mult *= 1.18;
      }
    } else {
      mult *= 1.5;
    }
    mult = mult.clamp(.45, 2.0).toDouble();
    final center = math.max(1, jsRound(t * mult).toInt());
    int low, high;
    if (center <= 2) {
      low = center;
      high = center;
    } else {
      low = math.max(1, jsRound(center * .85).toInt());
      high = math.max(low, jsRound(center * 1.15).toInt());
    }
    var direction = mult < .9 ? 'reduced' : (mult > 1.1 ? 'increased' : 'normal');
    // v480: class-level amount adaptation.
    final prefs = _v480Prefs();
    if (prefs.enabled && prefs.adaptAmount) {
      final group = _v480Membership(prefs)[jsStr(cat['id'])];
      if (group != null) {
        final members = group.categoryIds.toSet();
        final rows = consumptionSessions();
        double minutes(Map<String, dynamic> x) => math.max(0.0, jsNum(x['minutes']));
        final total = rows.fold<double>(0, (s, x) => s + minutes(x));
        if (total > 0) {
          final spent = rows.fold<double>(0, (s, x) => s + (members.contains(jsStr(x['categoryId'])) ? minutes(x) : 0));
          final eligible = _v480Groups(computeScores(const []), prefs);
          var weights = eligible.fold<double>(0, (s, x) => s + x.weight);
          if (weights == 0) weights = 1;
          final share = group.weight / weights;
          final r = share > 0 ? (spent / total) / share : 1.0;
          final adjust = r >= 1.5 ? .8 : (r <= .6 ? 1.15 : 1.0);
          if (adjust != 1) {
            low = math.max(1, jsRound(low * adjust).toInt());
            high = math.max(low, jsRound(high * adjust).toInt());
            mult = mult * adjust;
            direction = adjust < 1 ? 'reduced' : 'increased';
          }
        }
      }
    }
    return (low: low, high: high, multiplier: mult, direction: direction, balanceRatio: ratio);
  }

  // ---- exact titles ----------------------------------------------------------

  /// `scoreLibraryTitle` (+ mf464 rating influence).
  double scoreLibraryTitle(Map<String, dynamic> item, Map<String, dynamic> cat) {
    if (jsStr(item['categoryId']) != jsStr(cat['id'])) return double.negativeInfinity;
    final status = item['status'];
    if (status == 'completed' || status == 'dropped') return double.negativeInfinity;
    final total = jsNumOrNull(item['total']) ?? double.nan;
    final progress = jsNum(item['progress']);
    final completion = total > 0 ? math.min(1.0, progress / total) : 0.0;
    final remaining = total > 0 ? math.max(0.0, total - progress) : 10.0;
    const priorities = {'high': 18, 'medium': 8, 'low': 0};
    final priorityBonus = (priorities[item['priority']] ?? 0).toDouble();
    final activeBonus = status == 'active' ? 12.0 : (status == 'planned' ? 5.0 : 0.0);
    final unfinishedBonus = total > 0 ? math.min(20.0, remaining * 2) : 6.0;
    final seasonalBonus = jsTruthy(cat['seasonal']) ? 10.0 : 0.0;
    final jitter = random() * 8;
    final base = priorityBonus + activeBonus + unfinishedBonus + seasonalBonus - completion * 10 + jitter;
    return base + _ratingBonus(item);
  }

  List<Map<String, dynamic>> _sortedByScore(List<Map<String, dynamic>> pool, Map<String, dynamic> cat,
      [Map<String, int>? rank]) {
    final scores = <Map<String, dynamic>, double>{for (final i in pool) i: scoreLibraryTitle(i, cat)};
    final out = List<Map<String, dynamic>>.of(pool);
    stableSort<Map<String, dynamic>>(out, (a, b) {
      if (rank != null) {
        final ar = rank[jsStr(a['id'])] ?? 9007199254740991, br = rank[jsStr(b['id'])] ?? 9007199254740991;
        if (ar != br) return ar - br;
      }
      final d = scores[b]! - scores[a]!;
      return d.isNaN ? 0 : (d < 0 ? -1 : (d > 0 ? 1 : 0));
    });
    return out;
  }

  List<Map<String, dynamic>> _openTitles(Map<String, dynamic> cat) => library
      .where((i) => jsStr(i['categoryId']) == jsStr(cat['id']) && i['status'] != 'completed' && i['status'] != 'dropped')
      .toList();

  Map<String, dynamic>? pickLibraryTitle(Map<String, dynamic> cat) {
    // v287: Personal Order queue first.
    if (personalOrder && jsTruthy(cat['id'])) {
      final queue = recommendationSequence(jsStr(cat['id']));
      if (queue.isNotEmpty) return queue.first;
    }
    final pool = _openTitles(cat);
    if (pool.isEmpty) return null;
    final order = asMap(state['orderPlan']);
    if (personalOrder && order?['titleIds'] is List) {
      final byId = {for (final i in pool) if (jsTruthy(i['id'])) jsStr(i['id']): i};
      for (final id in asList(order!['titleIds'])) {
        final hit = byId[jsStr(id)];
        if (hit != null) return hit;
      }
    }
    final sorted = _sortedByScore(pool, cat);
    return sorted.isEmpty ? null : sorted.first;
  }

  /// `v180RecommendationCandidates`: the next titles for "another title".
  List<Map<String, dynamic>> titleCandidates(Map<String, dynamic> task) {
    final cat = getCategory(jsStr(task['categoryId']));
    final seen = ensureHistory(task).map((x) => jsStr(x['libraryId'])).where((x) => x.isNotEmpty).toSet();
    if (personalOrder) {
      final queue = recommendationSequence(jsStr(task['categoryId'])).where((i) => !seen.contains(jsStr(i['id']))).toList();
      if (queue.isNotEmpty) return queue;
    }
    var pool = _openTitles(cat);
    if (pool.isEmpty) return const [];
    pool = pool.where((i) => !seen.contains(jsStr(i['id']))).toList();
    if (pool.isEmpty) return const [];
    final order = asMap(state['orderPlan']);
    if (personalOrder && order?['titleIds'] is List) {
      final ids = asList(order!['titleIds']);
      final rank = <String, int>{};
      for (var i = 0; i < ids.length; i++) {
        rank[jsStr(ids[i])] = i; // Map semantics: the last index wins, like new Map(entries)
      }
      return _sortedByScore(pool, cat, rank);
    }
    return _sortedByScore(pool, cat);
  }

  Map<String, dynamic>? findLibraryItem(String libraryId, String title) {
    if (libraryId.isNotEmpty) {
      for (final i in library) {
        if (jsStr(i['id']) == libraryId) return i;
      }
    }
    final q = cleanTitle(title).toLowerCase();
    if (q.isEmpty) return null;
    for (final i in library) {
      if (cleanTitle(i['title']).toLowerCase() == q) return i;
    }
    return null;
  }

  Map<String, dynamic> historyEntry(Map<String, dynamic>? item, int index, {String? id, String? title}) => {
        'libraryId': item != null ? jsStr(item['id']) : (id ?? ''),
        'title': cleanTitle(item != null ? item['title'] : (title ?? '')),
        'shownAt': now,
        'index': index < 0 ? 0 : index,
      };

  /// `v180EnsureRecommendationHistory` (mutates [task]).
  List<Map<String, dynamic>> ensureHistory(Map<String, dynamic> task) {
    if (!exactTitles) return const [];
    if (task['v180RecommendationHistory'] is! List) task['v180RecommendationHistory'] = <dynamic>[];
    var history = asList(task['v180RecommendationHistory']);
    if (history.isEmpty && (jsTruthy(task['libraryId']) || jsTruthy(task['title']))) {
      final item = findLibraryItem(jsStr(task['libraryId']), jsStr(task['title']));
      history = [historyEntry(item, 0, id: jsStr(task['libraryId']), title: jsStr(task['title']))];
    }
    final normalized = <Map<String, dynamic>>[];
    for (final raw in history) {
      final x = asMap(raw);
      if (x == null) continue;
      final shown = jsNum(x['shownAt']);
      normalized.add({
        'libraryId': jsStr(x['libraryId']),
        'title': cleanTitle(x['title']),
        'shownAt': jsOut(shown > 0 ? shown : 0),
        'index': normalized.length,
      });
    }
    task['v180RecommendationHistory'] = normalized;
    task['v180TitleRerolls'] = math.max(0, normalized.length - 1);
    return normalized;
  }

  /// `generateTask` with the v180 and v287 wrappers.
  Map<String, dynamic>? generateTask(List<String> excludeIds) {
    final scored = computeScores(excludeIds);
    if (scored.isEmpty) return null;
    final pick = weightedPick(scored);
    if (pick == null) return null;
    final cat = pick.cat;
    final amount = suggestedAmount(cat);
    final title = exactTitles ? pickLibraryTitle(cat) : null;
    final amountReason = amount.direction == 'reduced'
        ? 'Session size reduced because this category is overrepresented in your consumption'
        : amount.direction == 'increased'
            ? 'Session size increased to gradually catch this category up'
            : 'Session size is near its normal target';
    final mid = jsRound((amount.low + amount.high) / 2);
    final task = <String, dynamic>{
      'id': uid(),
      'categoryId': cat['id'],
      'libraryId': title != null ? title['id'] : null,
      'title': title != null ? cleanTitle(title['title']) : null,
      'low': amount.low,
      'high': amount.high,
      'targetMid': mid != 0 ? jsOut(mid) : cat['target'],
      'unit': cat['unit'],
      'createdAt': now,
      'reasons': [...pick.reasons.map((r) => r.t), amountReason].take(4).toList(),
      'amountMultiplier': jsOut(amount.multiplier),
      'balanceRatio': jsOut(amount.balanceRatio),
    };
    if (exactTitles && (jsTruthy(task['libraryId']) || jsTruthy(task['title']))) {
      task['v180RecommendationHistory'] = <dynamic>[];
      task['v180TitleRerolls'] = 0;
      ensureHistory(task);
    }
    annotateOrderSource(task);
    return task;
  }

  // ---- v287 Personal Order -------------------------------------------------

  Map<String, dynamic> get _orderPlan {
    final p = asMap(state['orderPlan']);
    if (p != null) return p;
    return state['orderPlan'] = <String, dynamic>{};
  }

  List<Map<String, dynamic>> _assignments() {
    final validCats = categories.map((c) => jsStr(c['id'])).where((x) => x.isNotEmpty).toSet();
    final out = <Map<String, dynamic>>[];
    final pairs = <String>{};
    for (final raw in asList(_orderPlan['collectionAssignments'])) {
      final a = asMap(raw);
      if (a == null) continue;
      final cid = jsStr(a['categoryId']), col = jsStr(a['collectionId']);
      if (cid.isEmpty || col.isEmpty || (validCats.isNotEmpty && !validCats.contains(cid))) continue;
      if (!pairs.add('$cid\u0000$col')) continue;
      out.add(a);
    }
    return out;
  }

  Map<String, dynamic>? _libraryItem(String id) {
    for (final i in library) {
      if (jsStr(i['id']) == id) return i;
    }
    return null;
  }

  static bool _isCompleted(Map<String, dynamic> item) {
    if (jsStr(item['status']).toLowerCase() == 'completed') return true;
    final total = jsNumOrNull(item['total']) ?? double.nan;
    return total.isFinite && total > 0 && jsNum(item['progress']) >= total;
  }

  static bool _isDropped(Map<String, dynamic> item) => jsStr(item['status']).toLowerCase() == 'dropped';

  /// `v287ReconcileCategoryQueue` (stores the queue like the website does).
  List<String> reconcileQueue(String cid) {
    if (cid.isEmpty) return const [];
    final p = _orderPlan;
    final titleTokens = <String>[];
    for (final id in asList(p['titleIds'])) {
      final item = _libraryItem(jsStr(id));
      if (item != null && jsStr(item['categoryId']) == cid) titleTokens.add('t:${jsStr(id)}');
    }
    final assigned = _assignments().where((a) => jsStr(a['categoryId']) == cid).toList();
    stableSort<Map<String, dynamic>>(assigned, (a, b) {
      final d = jsNum(a['createdAt']) - jsNum(b['createdAt']);
      if (d != 0) return d < 0 ? -1 : 1;
      return jsStr(a['id']).compareTo(jsStr(b['id']));
    });
    final collectionTokens = [for (final a in assigned) 'c:${jsStr(a['id'])}'];
    final allowed = {...titleTokens, ...collectionTokens};
    final queues = asMap(p['categoryQueues']) ?? <String, dynamic>{};
    final raw = asList(queues[cid]);
    var queue = <String>[];
    final seen = <String>{};
    for (final t in raw) {
      final token = jsStr(t);
      if (allowed.contains(token) && seen.add(token)) queue.add(token);
    }
    if (queue.isEmpty) {
      queue = [...titleTokens, ...collectionTokens];
    } else {
      final existing = titleTokens.where(seen.contains).toList();
      var ti = 0;
      queue = [for (final t in queue) t.startsWith('t:') ? (ti < existing.length ? existing[ti++] : t) : t];
      final queued = queue.toSet();
      for (final t in [...titleTokens, ...collectionTokens]) {
        if (queued.add(t)) queue.add(t);
      }
    }
    final stored = Map<String, dynamic>.from(queues);
    stored[cid] = queue;
    p['categoryQueues'] = stored;
    return queue;
  }

  void reconcileAllQueues() {
    final p = _orderPlan;
    final cats = <String>{
      ...categories.map((c) => jsStr(c['id'])).where((x) => x.isNotEmpty),
      ...(asMap(p['categoryQueues'])?.keys ?? const <String>[]),
      ..._assignments().map((a) => jsStr(a['categoryId'])).where((x) => x.isNotEmpty),
    };
    for (final cid in cats) {
      reconcileQueue(cid);
    }
  }

  List<({Map<String, dynamic> item, String sourceType, String assignmentId})> recommendationEntries(String cid) {
    if (cid.isEmpty) return const [];
    final out = <({Map<String, dynamic> item, String sourceType, String assignmentId})>[];
    final seen = <String>{};
    final collections = asList(state['collections']).map(asMap).whereType<Map<String, dynamic>>().toList();
    for (final token in reconcileQueue(cid)) {
      if (token.startsWith('t:')) {
        final item = _libraryItem(token.substring(2));
        if (item == null || jsStr(item['categoryId']) != cid || _isDropped(item) || _isCompleted(item)) continue;
        final id = jsStr(item['id']);
        if (id.isNotEmpty && seen.add(id)) out.add((item: item, sourceType: 'title', assignmentId: ''));
        continue;
      }
      if (token.startsWith('c:')) {
        final aid = token.substring(2);
        final a = _assignments().where((x) => jsStr(x['id']) == aid).firstOrNull;
        if (a == null || jsStr(a['categoryId']) != cid) continue;
        final c = collections.where((x) => jsStr(x['id']) == jsStr(a['collectionId'])).firstOrNull;
        if (c == null) continue;
        final traversed = asList(a['traversedTitleIds']).map(jsStr).toSet();
        final orderIds = asList(c['order']).isNotEmpty ? asList(c['order']) : asList(c['titleIds']);
        final ids = <String>[];
        for (final raw in orderIds) {
          final id = jsStr(raw);
          if (id.isNotEmpty && !ids.contains(id)) ids.add(id);
        }
        for (final id in ids) {
          final item = _libraryItem(id);
          if (item == null || _isDropped(item) || traversed.contains(jsStr(item['id']))) continue;
          if (jsStr(a['categoryRule']) != 'force' && jsStr(item['categoryId']) != jsStr(a['categoryId'])) continue;
          if (jsStr(a['completedRule']) != 'include' && _isCompleted(item)) continue;
          if (seen.add(jsStr(item['id']))) out.add((item: item, sourceType: 'collection', assignmentId: jsStr(a['id'])));
        }
      }
    }
    return out;
  }

  List<Map<String, dynamic>> recommendationSequence(String cid) => [for (final e in recommendationEntries(cid)) e.item];

  Map<String, dynamic>? orderSourceForTask(Map<String, dynamic>? task) {
    if (task == null || !jsTruthy(task['categoryId']) || !jsTruthy(task['libraryId'])) return null;
    final lib = jsStr(task['libraryId']);
    for (final e in recommendationEntries(jsStr(task['categoryId']))) {
      if (jsStr(e.item['id']) == lib) {
        return {'type': e.sourceType, 'assignmentId': e.assignmentId, 'libraryId': lib, 'categoryId': jsStr(task['categoryId'])};
      }
    }
    return null;
  }

  void annotateOrderSource(Map<String, dynamic>? task) {
    if (task == null) return;
    final source = orderSourceForTask(task);
    if (source != null) {
      task['v287OrderSource'] = source;
    } else {
      task.remove('v287OrderSource');
    }
  }

  // ---- mf464 rating influence --------------------------------------------------

  static const _ratingSources = [
    ('imdb', 10), ('trakt', 10), ('rottentomatoes_critics', 100), ('rottentomatoes_audience', 100),
    ('mal', 10), ('anilist', 100), ('kitsu', 100), ('tmdb', 10), ('simkl', 10), ('anidb', 10),
    ('tvmaze', 10), ('metacritic', 100), ('letterboxd', 5), ('goodreads', 5), ('storygraph', 5),
    ('hardcover', 5), ('igdb', 100), ('opencritic', 100), ('steam', 100), ('backloggd', 5),
    ('vndb', 10), ('mangaupdates', 10), ('rateyourmusic', 5), ('discogs', 5), ('ifdb', 5),
  ];

  double _ratingBonus(Map<String, dynamic> item) {
    const influences = {'off': 0, 'light': 4, 'balanced': 8};
    final influence = (influences[jsStr(settings['v464RatingInfluence'])] ?? 0).toDouble();
    if (influence == 0) return 0;
    final env = asMap(item['universalMetadata']);
    if (env == null) return 0;
    final ratings = asMap(env['externalRatings']) ?? const {};
    final provenance = asMap(env['provenance']) ?? const {};
    var totalWeight = 0.0, weighted = 0.0, votes = 0.0;
    var verifiedCount = 0;
    for (final (key, defaultScale) in _ratingSources) {
      final entry = asMap(ratings[key]);
      if (entry == null || entry['score'] == null || jsStr(entry['score']).trim().isEmpty) continue;
      final score = jsNumOrNull(entry['score']);
      final scale = jsNumOrNull(entry['scale'] ?? defaultScale);
      if (score == null || scale == null || !score.isFinite || !scale.isFinite || scale <= 0 || scale > 100000 ||
          score < 0 || score > scale) {
        continue;
      }
      final voteRaw = entry['votes'];
      double? v;
      if (voteRaw != null && jsStr(voteRaw).trim().isNotEmpty) {
        final n = jsNumOrNull(voteRaw);
        if (n != null && n >= 0 && n == n.truncateToDouble() && n <= 9007199254740991) v = n;
      }
      final proof = asMap(provenance['rating.$key']) ?? const {};
      final manual = proof['source'] == 'manual' || entry['source'] == 'manual';
      final verified = !manual && proof['verified'] == true && proof['source'] is String &&
          (proof['source'] as String).trim().isNotEmpty && (!jsTruthy(entry['source']) || entry['source'] == proof['source']);
      if (!verified) continue;
      final weight = v == null ? 1.0 : math.max(0.6, math.min(2.5, 0.8 + (math.log(v + 1) / math.ln10) * 0.33));
      verifiedCount++;
      totalWeight += weight;
      weighted += score / scale * 100 * weight;
      votes += v ?? 0;
    }
    if (verifiedCount == 0 || totalWeight <= 0) return 0;
    final average = weighted / totalWeight;
    final confidence = math.min(1.0,
        0.35 + math.min(0.3, verifiedCount * 0.12) + math.min(0.35, (math.log(votes + 1) / math.ln10) * 0.09));
    final centered = math.max(-1.0, math.min(1.0, (average - 50) / 50));
    return centered * influence * confidence;
  }

  // ---- v480 category classes ------------------------------------------------------

  _V480Prefs _v480Prefs() {
    final s = asMap(settings['v480CategoryClasses']) ?? const {};
    final valid = categories.map((c) => jsStr(c['id'])).toSet();
    final used = <String>{};
    final classes = <_V480Class>[];
    for (final raw in asList(s['classes']).take(200)) {
      final e = asMap(raw);
      if (e == null) continue;
      final id = jsStr(e['id']).trim();
      final cid = id.length > 100 ? id.substring(0, 100) : id;
      if (cid.isEmpty || classes.any((c) => c.id == cid)) continue;
      final ids = <String>[];
      for (final v in asList(e['categoryIds'])) {
        final key = jsStr(v);
        if (valid.contains(key) && used.add(key)) ids.add(key);
      }
      final name = jsStr(e['name']).isEmpty ? 'Untitled Class' : jsStr(e['name']).trim();
      final weight = jsNum(e['weight']);
      classes.add(_V480Class(cid, name.isEmpty ? 'Untitled Class' : name,
          (weight == 0 || weight.isNaN ? 1.0 : weight).clamp(1, 5).toDouble(), e['enabled'] != false, ids));
    }
    const strengths = ['gentle', 'balanced', 'strong'];
    return _V480Prefs(
      enabled: s['enabled'] == true,
      strength: strengths.contains(s['strength']) ? s['strength'] as String : 'balanced',
      avoidRepeat: s['avoidRepeat'] != false,
      rewardNeglect: s['rewardNeglect'] != false,
      freshInfluence: s['freshInfluence'] != false,
      adaptAmount: s['adaptAmount'] == true,
      classes: classes,
    );
  }

  Map<String, _V480Class> _v480Membership(_V480Prefs prefs) {
    final lookup = <String, _V480Class>{};
    for (final g in prefs.classes) {
      if (!g.enabled) continue;
      for (final id in g.categoryIds) {
        lookup[id] = g;
      }
    }
    return lookup;
  }

  List<_V480Group> _v480Groups(List<ScoredCategory> scored, _V480Prefs prefs) {
    final byCategory = _v480Membership(prefs);
    final groups = <String, _V480Group>{};
    for (final row in scored) {
      final id = row.id;
      if (id.isEmpty || row.cat['enabled'] == false) continue;
      final group = byCategory[id];
      final key = group != null ? 'class:${group.id}' : 'single:$id';
      final found = groups.putIfAbsent(
          key,
          () => _V480Group(group != null ? 'class' : 'single', group,
              group != null ? group.categoryIds.toSet() : {id}, group?.weight ?? 1));
      found.rows.add(row);
    }
    return groups.values.toList();
  }

  ({double score, List<String> reasons}) _v480ClassScore(_V480Group g, _V480Prefs prefs, List<_V480Group> all) {
    if (g.kind == 'single') return (score: math.max(.5, g.rows.first.score), reasons: const []);
    final rows = consumptionSessions();
    var totalWeights = all.fold<double>(0, (s, x) => s + x.weight);
    if (totalWeights == 0) totalWeights = 1;
    final desired = math.max(.01, g.weight / totalWeights);
    const windows = [(days: 3, w: .35, min: 60), (days: 7, w: .25, min: 120), (days: 30, w: .20, min: 240), (days: -1, w: .20, min: 1)];
    var weightedRatio = 0.0, usedWeight = 0.0;
    for (final win in windows) {
      final cut = win.days < 0 ? 0 : now - win.days * 86400000;
      final list = win.days < 0 ? rows : rows.where((x) => jsNum(x['timestamp']) >= cut).toList();
      final total = list.fold<double>(0, (s, x) => s + math.max(0.0, jsNum(x['minutes'])));
      if (total < win.min) continue;
      final mine = list.fold<double>(0, (s, x) => s + (g.members.contains(jsStr(x['categoryId'])) ? math.max(0.0, jsNum(x['minutes'])) : 0));
      weightedRatio += math.min(6.0, mine / total / desired) * win.w;
      usedWeight += win.w;
    }
    final ratio = usedWeight > 0 ? weightedRatio / usedWeight : 1.0;
    final relevant = rows.where((s) => g.members.contains(jsStr(s['categoryId'])));
    final lastTime = relevant.fold<double>(0, (t, x) => math.max(t, jsNum(x['timestamp'])));
    final daysIdle = lastTime > 0 ? math.max(0.0, (now - lastTime) / 86400000) : double.infinity;
    const factors = {'gentle': .5, 'balanced': 1.0, 'strong': 1.65};
    final factor = factors[prefs.strength] ?? 1.0;
    final cap = math.max(0.0, _st('neglectCap'));
    final neglect = prefs.rewardNeglect
        ? (lastTime == 0 ? cap : math.min(cap, daysIdle * math.max(0.0, _st('neglectRate'))))
        : 0.0;
    final events = logicalEvents();
    final seen = events.take(6).where((e) => g.members.any(e.categoryIds.contains)).length;
    var consecutive = 0;
    for (final e in events) {
      if (g.members.any(e.categoryIds.contains)) {
        consecutive++;
      } else {
        break;
      }
    }
    final repeat = prefs.avoidRepeat ? seen * _st('repetitionPenalty') + consecutive * _st('consecutivePenalty') : 0.0;
    final saturation = math.min(70.0, math.max(0.0, ratio - 1) * _st('saturationWeight') * 2.2);
    final balance = math.min(28.0, math.max(0.0, 1 - ratio) * _st('neglectCap') * .55);
    final freshBonus = prefs.freshInfluence && g.rows.any((r) => jsTruthy(r.cat['seasonal']))
        ? _st('seasonalBonus') + _st('seasonalFreshCount') * 4
        : 0.0;
    final raw = g.weight * 8 + (neglect + balance + freshBonus - repeat - saturation) * factor;
    final baseline = math.max(1.5, raw);
    final randomness = _st('randomness').clamp(0, 1).toDouble();
    final score = math.max(.5, baseline * (1 + (random() * 2 - 1) * randomness));
    final why = <String>[];
    final name = g.group!.name;
    if (ratio > 1.25) {
      why.add('Class $name is overrepresented in recent consumption');
    } else if (ratio < .75) {
      why.add('Class $name is underrepresented in recent consumption');
    } else if (lastTime == 0) {
      why.add('Class $name has not been consumed yet');
    }
    if (seen > 0 && prefs.avoidRepeat) why.add('Recent $name sessions influence class rotation');
    return (score: score, reasons: why);
  }
}

class _V480Class {
  _V480Class(this.id, this.name, this.weight, this.enabled, this.categoryIds);
  final String id;
  final String name;
  final double weight;
  final bool enabled;
  final List<String> categoryIds;
}

class _V480Prefs {
  _V480Prefs({
    required this.enabled,
    required this.strength,
    required this.avoidRepeat,
    required this.rewardNeglect,
    required this.freshInfluence,
    required this.adaptAmount,
    required this.classes,
  });
  final bool enabled;
  final String strength;
  final bool avoidRepeat;
  final bool rewardNeglect;
  final bool freshInfluence;
  final bool adaptAmount;
  final List<_V480Class> classes;
}

class _V480Group {
  _V480Group(this.kind, this.group, this.members, this.weight);
  final String kind;
  final _V480Class? group;
  final Set<String> members;
  final double weight;
  final List<ScoredCategory> rows = [];
}

// ---- System Respect state (v165) ----------------------------------------------

/// `v165NormalizeRespectState`.
Map<String, dynamic> normalizeRespectState(Object? raw) {
  final src = asMap(raw) ?? const {};
  int i(String k) {
    final n = jsNum(src[k]);
    return n.isFinite && n > 0 ? n.floor() : 0;
  }

  num t(String k) {
    final n = jsNum(src[k]);
    return n.isFinite && n > 0 ? jsOut(n) : 0;
  }

  return {
    'version': 165,
    'noSkipStreak': i('noSkipStreak'),
    'noRerollStreak': i('noRerollStreak'),
    'bestNoSkipStreak': i('bestNoSkipStreak'),
    'bestNoRerollStreak': i('bestNoRerollStreak'),
    'currentRerolls': i('currentRerolls'),
    'totalSkips': i('totalSkips'),
    'totalRerolls': i('totalRerolls'),
    'lastRewardAt': t('lastRewardAt'),
    'modifiedAt': t('modifiedAt'),
  };
}

Map<String, dynamic> ensureRespectState(Map<String, dynamic> state) {
  final st = normalizeRespectState(state['respectState']);
  state['respectState'] = st;
  return st;
}

// ---- Session actions -------------------------------------------------------------

/// What a session action did, so it can be replayed on a newer cloud copy.
class TaskActionResult {
  TaskActionResult({required this.changed, this.task, this.skipSession});
  final bool changed;
  final Map<String, dynamic>? task;
  final Map<String, dynamic>? skipSession;
}

/// `startSession`: activates the session; makes a task if there is none.
TaskActionResult startSession(Map<String, dynamic> state, Recommender r, {Map<String, dynamic>? presetTask}) {
  state['sessionActive'] = true;
  if (asMap(state['currentTask']) == null) {
    state['currentTask'] = presetTask ?? r.generateTask(const []);
  }
  return TaskActionResult(changed: true, task: asMap(state['currentTask']));
}

/// `rotateTask` ("Give me something else"): breaks the first-pick streak.
TaskActionResult rotateTask(Map<String, dynamic> state, Recommender r, {Map<String, dynamic>? presetTask}) {
  final current = asMap(state['currentTask']);
  if (current == null) return TaskActionResult(changed: false);
  final st = ensureRespectState(state);
  st['modifiedAt'] = r.now;
  st['currentRerolls'] = jsNum(st['currentRerolls']).toInt() + 1;
  st['totalRerolls'] = jsNum(st['totalRerolls']).toInt() + 1;
  st['noRerollStreak'] = 0;
  state['currentTask'] = presetTask ?? r.generateTask([jsStr(current['categoryId'])]);
  return TaskActionResult(changed: true, task: asMap(state['currentTask']));
}

/// `skipTask`: records a skipped log and moves to another category.
TaskActionResult skipTask(Map<String, dynamic> state, Recommender r, Leveling l,
    {Map<String, dynamic>? presetTask, String? skipSessionId}) {
  final current = asMap(state['currentTask']);
  if (current == null) return TaskActionResult(changed: false);
  final st = ensureRespectState(state);
  st['modifiedAt'] = r.now;
  st['totalSkips'] = jsNum(st['totalSkips']).toInt() + 1;
  st['currentRerolls'] = 0;
  st['noSkipStreak'] = 0;
  st['noRerollStreak'] = 0;
  final cat = r.getCategory(jsStr(current['categoryId']));
  final sessions = listIn(state, 'sessions');
  final session = <String, dynamic>{
    'id': skipSessionId ?? r.uid(),
    'timestamp': r.now,
    'date': isoDateUtc(r.now),
    'categoryId': cat['id'],
    'targetAmount': current['targetMid'],
    'actualAmount': 0,
    'minutes': 0,
    'note': '',
    'status': 'skipped',
    'unit': cat['unit'],
    'xp': 0,
    'healthStatus': categoryStatusOf(cat, sessions, r.now),
  };
  sessions.add(session);
  annotateStreakXP(state, l);
  state['currentTask'] = presetTask ?? r.generateTask([jsStr(cat['id'])]);
  return TaskActionResult(changed: true, task: asMap(state['currentTask']), skipSession: session);
}

/// `endSession`.
TaskActionResult endSession(Map<String, dynamic> state, Recommender r) {
  final st = ensureRespectState(state);
  if (jsNum(st['currentRerolls']) > 0) {
    st['currentRerolls'] = 0;
    st['modifiedAt'] = r.now;
  }
  state['sessionActive'] = false;
  state['currentTask'] = null;
  return TaskActionResult(changed: true);
}

/// `v180RerollRecommendedTitle`: the next title in the same category task. Does
/// not touch the respect streaks.
TaskActionResult rerollTitle(Map<String, dynamic> state, Recommender r, {Map<String, dynamic>? presetEntry}) {
  final task = asMap(state['currentTask']);
  if (task == null || !r.exactTitles) return TaskActionResult(changed: false);
  final history = r.ensureHistory(task);
  Map<String, dynamic>? entry = presetEntry;
  if (entry == null) {
    final candidates = r.titleCandidates(task);
    if (candidates.isEmpty) return TaskActionResult(changed: false);
    entry = r.historyEntry(candidates.first, history.length);
  } else {
    entry = Map<String, dynamic>.from(entry)..['index'] = history.length;
  }
  history.add(entry);
  task['v180RecommendationHistory'] = history;
  task['libraryId'] = entry['libraryId'];
  final item = r.findLibraryItem(jsStr(entry['libraryId']), '');
  task['title'] = cleanTitle(item != null ? item['title'] : entry['title']);
  task['v180TitleRerolls'] = history.length - 1;
  task['v180RecommendationUpdatedAt'] = r.now;
  r.annotateOrderSource(task);
  return TaskActionResult(changed: true, task: task);
}

/// `categoryStatus` on a raw category map.
String categoryStatusOf(Map<String, dynamic> cat, List<dynamic> sessions, int now) =>
    categoryStatus(Category(cat), sessions, now);
