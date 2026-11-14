// Old System (website v153 + v173 Date View): your original category
// conversion system, separate from MediaFlow's scheduler. Saved in the
// account as `oldSystem`, exactly as the website writes it:
//   {enabledCategoryIds, rules: [{id, fromCategoryId, toCategoryId,
//    fromAmount, toAmount, createdAt}], balances: {categoryId: n},
//    transactions: [{id, timestamp, type, categoryId, amount, label,
//    deltas: [{categoryId, delta}]}], mode, modifiedAt, dateFrom, dateTo}
// System: chosen categories, rules "consume A → subtract from B", balances
// you consume from by hand (with undo). View / Date View: a read-only replay
// of the same rules over real History (all of it, or a date range). Stats:
// exact all-time consumption per category. Never touches History, Library,
// recommendations or progress. Proven against the website's own code
// (test/old_system_golden_test.dart).

import 'dart:math' as math;

import '../state/models.dart' show unitLabel;
import '../util/js.dart';
import 'ratings_engine.dart' show mergeSortBy;

const kOldSystemModes = ['system', 'view', 'date', 'stats'];

final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

double _n(Object? v) {
  final n = jsNumOrNull(v);
  return n == null || !n.isFinite ? double.nan : n;
}

/// `v153NormalizeOldSystem` (+ v173's date fields).
Map<String, dynamic> normalizeOldSystem(Object? raw, List<String> categoryIds, int now, String Function() uid) {
  final src = asMap(raw) ?? const <String, dynamic>{};
  final existing = categoryIds.toSet();
  final enabled = <String>[];
  for (final id in asList(src['enabledCategoryIds']).map(jsStr)) {
    if (existing.contains(id) && !enabled.contains(id)) enabled.add(id);
  }
  final balances = <String, dynamic>{};
  (asMap(src['balances']) ?? const {}).forEach((id, value) {
    final n = _n(value);
    if (n.isFinite) balances[id] = jsOut(n);
  });
  final rules = <Map<String, dynamic>>[];
  for (final r in asList(src['rules']).map(asMap).whereType<Map<String, dynamic>>()) {
    double amount(Object? v) {
      final n = _n(v);
      return math.max(0.000001, n.isFinite && n != 0 ? n : 1.0);
    }

    final rule = <String, dynamic>{
      'id': jsTruthy(r['id']) ? jsStr(r['id']) : uid(),
      'fromCategoryId': jsTruthy(r['fromCategoryId']) ? jsStr(r['fromCategoryId']) : '',
      'toCategoryId': jsTruthy(r['toCategoryId']) ? jsStr(r['toCategoryId']) : '',
      'fromAmount': jsOut(amount(r['fromAmount'])),
      'toAmount': jsOut(amount(r['toAmount'])),
      'createdAt': jsOut(_n(r['createdAt']).isFinite && _n(r['createdAt']) != 0 ? _n(r['createdAt']) : now.toDouble()),
    };
    if (jsStr(rule['fromCategoryId']).isNotEmpty && jsStr(rule['toCategoryId']).isNotEmpty && rule['fromCategoryId'] != rule['toCategoryId']) {
      rules.add(rule);
    }
  }
  final transactions = <Map<String, dynamic>>[];
  for (final t in asList(src['transactions']).map(asMap).whereType<Map<String, dynamic>>()) {
    final ts = _n(t['timestamp']);
    final amount = _n(t['amount']);
    transactions.add({
      'id': jsTruthy(t['id']) ? jsStr(t['id']) : uid(),
      'timestamp': jsOut(ts.isFinite && ts != 0 ? ts : now.toDouble()),
      'type': jsTruthy(t['type']) ? jsStr(t['type']) : 'consume',
      'categoryId': jsTruthy(t['categoryId']) ? jsStr(t['categoryId']) : '',
      'amount': jsOut(amount.isFinite ? amount : 0),
      'label': jsTruthy(t['label']) ? jsStr(t['label']) : '',
      'deltas': t['deltas'] is List
          ? [
              for (final d in asList(t['deltas']).map(asMap).whereType<Map<String, dynamic>>())
                if (jsTruthy(d['categoryId']) && _n(d['delta']).isFinite) {'categoryId': jsStr(d['categoryId']), 'delta': jsOut(_n(d['delta']))},
            ]
          : <Map<String, dynamic>>[],
    });
  }
  final modified = _n(src['modifiedAt']);
  String validDate(Object? v) {
    final s = jsStr(v).trim();
    return _date.hasMatch(s) ? s : '';
  }

  return {
    'enabledCategoryIds': enabled,
    'rules': rules,
    'balances': balances,
    'transactions': transactions,
    'mode': kOldSystemModes.contains(jsStr(src['mode'])) ? jsStr(src['mode']) : 'system',
    'modifiedAt': jsOut(modified.isFinite ? modified : 0),
    'dateFrom': validDate(src['dateFrom']),
    'dateTo': validDate(src['dateTo']),
  };
}

/// One Old System edit on the account (each returns a message to show, or
/// null). They normalize first and stamp `modifiedAt`, like the website.
class OldSystemOps {
  OldSystemOps(this.state, this.now, this.uid);
  final Map<String, dynamic> state;
  final int now;
  final String Function() uid;

  List<Map<String, dynamic>> get _cats => asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>().where((c) => jsTruthy(c['id'])).toList();
  List<String> get _catIds => [for (final c in _cats) jsStr(c['id'])];

  // Normalized once and then kept: the website's v153EnsureOldSystem swaps in
  // a fresh copy on every call, which made Consume lose its rule costs and
  // transaction (see generate_old_system_goldens.mjs).
  Map<String, dynamic>? _os;
  Map<String, dynamic> get os => _os ??= (state['oldSystem'] = normalizeOldSystem(state['oldSystem'], _catIds, now, uid));

  void _touch() {
    final o = normalizeOldSystem(state['oldSystem'], _catIds, now, uid)..['modifiedAt'] = now;
    state['oldSystem'] = _os = o;
  }

  String _name(String id) {
    final c = _cats.where((c) => jsStr(c['id']) == id).firstOrNull;
    return c == null ? '(removed category)' : jsStr(c['name']);
  }

  String _unit(String id) => jsStr(_cats.where((c) => jsStr(c['id']) == id).firstOrNull?['unit']);

  List<Map<String, dynamic>> activeRules() {
    final o = os;
    final enabled = (o['enabledCategoryIds'] as List).cast<String>().toSet();
    return [
      for (final r in (o['rules'] as List).cast<Map<String, dynamic>>())
        if (enabled.contains(r['fromCategoryId']) && enabled.contains(r['toCategoryId']) && r['fromCategoryId'] != r['toCategoryId']) r,
    ];
  }

  String? setMode(String mode) {
    final o = os;
    if (!kOldSystemModes.contains(mode)) return null;
    o['mode'] = mode;
    o['modifiedAt'] = now;
    return null;
  }

  String? toggleCategory(String id) {
    final o = os;
    if (id.isEmpty || !_catIds.contains(id)) return null;
    final set = (o['enabledCategoryIds'] as List).cast<String>().toSet();
    if (!set.remove(id)) set.add(id);
    o['enabledCategoryIds'] = [for (final cid in _catIds) if (set.contains(cid)) cid];
    final balances = o['balances'] as Map<String, dynamic>;
    if (!balances.containsKey(id)) balances[id] = 0;
    _touch();
    return null;
  }

  String? addRule() {
    final o = os;
    final ids = (o['enabledCategoryIds'] as List).cast<String>();
    if (ids.length < 2) return 'Add at least two categories first.';
    (o['rules'] as List).add({'id': uid(), 'fromCategoryId': ids[0], 'toCategoryId': ids[1], 'fromAmount': 1, 'toAmount': 1, 'createdAt': now});
    _touch();
    return null;
  }

  String? updateRule(String id, String key, Object? value) {
    final o = os;
    final r = (o['rules'] as List).cast<Map<String, dynamic>>().where((x) => jsStr(x['id']) == id).firstOrNull;
    if (r == null) return null;
    if (key == 'fromAmount' || key == 'toAmount') {
      final n = _n(value);
      if (!(n > 0)) return 'Conversion amount must be greater than 0.';
      r[key] = jsOut(n);
    } else if (key == 'fromCategoryId' || key == 'toCategoryId') {
      final cid = jsStr(value);
      if (!(o['enabledCategoryIds'] as List).contains(cid)) return null;
      final other = key == 'fromCategoryId' ? jsStr(r['toCategoryId']) : jsStr(r['fromCategoryId']);
      if (cid == other) return 'A category cannot subtract from itself.';
      r[key] = cid;
    } else {
      return null;
    }
    _touch();
    return null;
  }

  String? removeRule(String id) {
    final o = os;
    o['rules'] = [for (final r in (o['rules'] as List).cast<Map<String, dynamic>>()) if (jsStr(r['id']) != id) r];
    _touch();
    return null;
  }

  String? setBalance(String id, Object? value) {
    final o = os;
    if (!(o['enabledCategoryIds'] as List).contains(id)) return null;
    final v = _n(value);
    if (!v.isFinite) return 'Enter a valid balance.';
    final balances = o['balances'] as Map<String, dynamic>;
    final before = _orZero(balances[id]);
    final delta = v - before;
    if (delta.abs() < 0.0000001) return null;
    balances[id] = jsOut(v);
    (o['transactions'] as List).add({
      'id': uid(),
      'timestamp': now,
      'type': 'adjustment',
      'categoryId': id,
      'amount': jsOut(v),
      'label': 'Set ${_name(id)} balance to ${fmtOldSystemQty(v)}',
      'deltas': [
        {'categoryId': id, 'delta': jsOut(delta)},
      ],
    });
    _touch();
    return null;
  }

  /// Adds [qty] to a category and subtracts every rule's cost.
  String? consume(String id, Object? amount) {
    final o = os;
    final qty = _n(amount);
    if (!(o['enabledCategoryIds'] as List).contains(id)) return 'Choose an Old System category.';
    if (!(qty > 0)) return 'Consumption amount must be greater than 0.';
    final balances = o['balances'] as Map<String, dynamic>;
    final deltas = <Map<String, dynamic>>[];
    balances[id] = jsOut(_orZero(balances[id]) + qty);
    deltas.add({'categoryId': id, 'delta': jsOut(qty)});
    for (final r in activeRules().where((r) => r['toCategoryId'] == id)) {
      final fromId = jsStr(r['fromCategoryId']);
      final cost = qty * _orOne(r['fromAmount']) / _orOne(r['toAmount']);
      balances[fromId] = jsOut(_orZero(balances[fromId]) - cost);
      deltas.add({'categoryId': fromId, 'delta': jsOut(-cost)});
    }
    (o['transactions'] as List).add({
      'id': uid(),
      'timestamp': now,
      'type': 'consume',
      'categoryId': id,
      'amount': jsOut(qty),
      'label': 'Consumed ${fmtOldSystemQty(qty)} ${unitLabel(_unit(id), qty)} of ${_name(id)}',
      'deltas': deltas,
    });
    _touch();
    return null;
  }

  String? undo() {
    final o = os;
    final list = o['transactions'] as List;
    if (list.isEmpty) return 'Nothing to undo.';
    final t = asMap(list.removeLast())!;
    final balances = o['balances'] as Map<String, dynamic>;
    for (final d in asList(t['deltas']).map(asMap).whereType<Map<String, dynamic>>()) {
      final id = jsStr(d['categoryId']);
      balances[id] = jsOut(_orZero(balances[id]) - _orZero(d['delta']));
    }
    _touch();
    return null;
  }

  String? setDate(String key, String value) {
    if (key != 'dateFrom' && key != 'dateTo') return null;
    final o = os;
    final s = value.trim();
    o[key] = _date.hasMatch(s) ? s : '';
    _touch();
    return null;
  }

  String? clearDates() {
    final o = os;
    o['dateFrom'] = '';
    o['dateTo'] = '';
    _touch();
    return null;
  }
}

double _orZero(Object? v) {
  final n = _n(v);
  return n.isFinite ? n : 0;
}

double _orOne(Object? v) {
  final n = _n(v);
  return n.isFinite && n != 0 ? n : 1;
}

/// `v153FmtQty`: up to three decimals, thousands separators.
String fmtOldSystemQty(num v) {
  final n = v.isFinite ? v : 0;
  if (n.abs() < 0.0000001) return '0';
  final rounded = (n * 1000).round() / 1000;
  final neg = rounded < 0;
  final abs = rounded.abs();
  final whole = abs.floor();
  var frac = ((abs - whole) * 1000).round();
  var intPart = whole;
  if (frac >= 1000) {
    intPart += 1;
    frac -= 1000;
  }
  final digits = '$intPart'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final f = frac == 0 ? '' : '.${frac.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
  return '${neg ? '-' : ''}$digits$f';
}

/// History replayed through the Old System (`v153BuildHistoryCache`,
/// `v173BuildOldSystemCacheForRows`): per category, the real totals, records
/// and minutes, and the simulated balance / amount spent by rules.
class OldSystemReplay {
  final Map<String, double> rawTotals = {}, minuteTotals = {}, simulatedBalances = {}, simulatedSpent = {};
  final Map<String, int> sessionCounts = {};
  int activityRows = 0;
}

String oldSystemDayKey(Map<String, dynamic> s) {
  final direct = jsStr(s['date']);
  final d10 = direct.length >= 10 ? direct.substring(0, 10) : direct;
  if (_date.hasMatch(d10)) return d10;
  final ts = jsNum(s['timestamp']).toInt();
  if (ts == 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

OldSystemReplay replayOldSystem(Map<String, dynamic> state, {bool dateRange = false}) {
  final cats = [for (final c in asList(state['categories']).map(asMap).whereType<Map<String, dynamic>>()) if (jsTruthy(c['id'])) jsStr(c['id'])];
  final existing = cats.toSet();
  final o = normalizeOldSystem(state['oldSystem'], cats, 0, () => '');
  final enabled = (o['enabledCategoryIds'] as List).cast<String>();
  final enabledSet = enabled.toSet();
  final rules = [
    for (final r in (o['rules'] as List).cast<Map<String, dynamic>>())
      if (enabledSet.contains(r['fromCategoryId']) && enabledSet.contains(r['toCategoryId']) && r['fromCategoryId'] != r['toCategoryId']) r,
  ];
  final from = jsStr(o['dateFrom']), to = jsStr(o['dateTo']);
  final rows = <Map<String, dynamic>>[
    for (final s in asList(state['sessions']).map(asMap).whereType<Map<String, dynamic>>())
      if (s['status'] != 'skipped' && jsNum(s['actualAmount']) > 0 && jsTruthy(s['categoryId']) && existing.contains(jsStr(s['categoryId']))) s,
  ];
  mergeSortBy(rows, (a, b) => jsNum(a['timestamp']).compareTo(jsNum(b['timestamp'])));
  final out = OldSystemReplay();
  for (final id in enabled) {
    out.simulatedBalances[id] = 0;
  }
  for (final s in rows) {
    if (dateRange) {
      final day = oldSystemDayKey(s);
      if (day.isEmpty || (from.isNotEmpty && day.compareTo(from) < 0) || (to.isNotEmpty && day.compareTo(to) > 0)) continue;
    }
    out.activityRows++;
    final id = jsStr(s['categoryId']);
    final amount = math.max(0.0, jsNum(s['actualAmount']).toDouble());
    final minutes = math.max(0.0, jsNum(s['minutes']).toDouble());
    out.rawTotals[id] = (out.rawTotals[id] ?? 0) + amount;
    out.sessionCounts[id] = (out.sessionCounts[id] ?? 0) + 1;
    out.minuteTotals[id] = (out.minuteTotals[id] ?? 0) + minutes;
    if (!enabledSet.contains(id)) continue;
    out.simulatedBalances[id] = (out.simulatedBalances[id] ?? 0) + amount;
    for (final r in rules) {
      if (r['toCategoryId'] != id) continue;
      final cost = amount * _orOne(r['fromAmount']) / _orOne(r['toAmount']);
      final fromId = jsStr(r['fromCategoryId']);
      out.simulatedBalances[fromId] = (out.simulatedBalances[fromId] ?? 0) - cost;
      out.simulatedSpent[fromId] = (out.simulatedSpent[fromId] ?? 0) + cost;
    }
  }
  return out;
}
