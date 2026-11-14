// Titles logged by parts (website v577, 427-v577-parts.js).
//
// Edit title → "How this title is logged": Normal (default; seasons fill in
// order) or By parts: the title is a set of parts (game modes, chapters,
// anything), each with its own kind, name, counter, unit and time per unit.
// The parts live in the title's season rows, so nothing else breaks:
//   item.mf577LogMode     'parts' (absent = Normal)
//   item.mf577LastPartId  the part logged last (the default next time)
//   item.seasons[]        id, name, progress, total, plus optional
//                         mf577Kind, mf577Unit, mf577SecondsPerUnit
// A part's time per unit falls back to the title's own (mf565), then the
// category's. The title's number is the sum of its parts; it has no total
// (completed only by hand). A log says which parts moved: [{id, qty}]; History
// keeps title.mf577Parts = [{id, name, kind, unit, from, to, qty}].

import '../util/js.dart';
import 'log_engine.dart' show normalizeSeasons;
import '../state/models.dart' show unitLabel;
import 'title_units.dart';

bool isByParts(Map<String, dynamic>? item) => item != null && item['mf577LogMode'] == 'parts';

/// The parts of a by-parts title (normalized season rows), else empty.
List<Map<String, dynamic>> titleParts(Map<String, dynamic>? item) {
  if (!isByParts(item)) return const [];
  final src = jsStr(item!['seasonSource']).isEmpty ? 'manual' : jsStr(item['seasonSource']);
  return normalizeSeasons(item['seasons'], src);
}

Map<String, dynamic>? titlePart(Map<String, dynamic>? item, String id) {
  for (final p in titleParts(item)) {
    if (jsStr(p['id']) == id) return p;
  }
  return null;
}

String partKind(Map<String, dynamic>? part) {
  final k = jsStr(part?['mf577Kind']).trim();
  return k.length > 30 ? k.substring(0, 30) : k;
}

/// "Mode · Competitive".
String partName(Map<String, dynamic>? part) {
  final k = partKind(part);
  final n = jsStr(part?['name']).isEmpty ? 'Part' : jsStr(part?['name']);
  return k.isEmpty ? n : '$k · $n';
}

/// `mf577PartUnitKey`.
String partUnit(Map<String, dynamic>? part, Map<String, dynamic>? item, Map<String, dynamic>? cat) {
  final own = jsStr(part?['mf577Unit']).trim();
  if (own.isNotEmpty) return own.length > 40 ? own.substring(0, 40) : own;
  return titleUnit(item, cat);
}

/// `mf577PartSeconds`: the part's own, then the title's own, then the category's.
int partSeconds(Map<String, dynamic>? part, Map<String, dynamic>? item, Map<String, dynamic>? cat) {
  final own = jsNum(part?['mf577SecondsPerUnit']).floor();
  if (own > 0) return own;
  return titleSecondsPerUnit(item, cat);
}

/// `mf577PartFactor`: category units per one of this part's units.
double partFactor(Map<String, dynamic>? part, Map<String, dynamic>? item, Map<String, dynamic>? cat) {
  final own = jsNum(part?['mf577SecondsPerUnit']).floor();
  final base = categorySecondsPerUnit(cat);
  if (own > 0 && base > 0) return own / base;
  return unitFactor(item, cat);
}

/// The part logged last, or the first.
Map<String, dynamic>? defaultPart(Map<String, dynamic>? item) {
  final parts = titleParts(item);
  final last = jsStr(item?['mf577LastPartId']);
  for (final p in parts) {
    if (jsStr(p['id']) == last) return p;
  }
  return parts.isEmpty ? null : parts.first;
}

/// One part's move in a log.
class PartMove {
  const PartMove(this.id, this.qty);
  final String id;
  final double qty;
  Map<String, dynamic> toJson() => {'id': id, 'qty': jsOut(qty)};
  static PartMove fromJson(Map<String, dynamic> j) => PartMove(jsStr(j['id']), jsNum(j['qty']));
}

/// `mf577Clean`: known parts only, once each, whole units.
List<PartMove> cleanMoves(Map<String, dynamic>? item, Iterable<PartMove> list) {
  final known = {for (final p in titleParts(item)) jsStr(p['id'])};
  final seen = <String>{};
  return [
    for (final m in list)
      if (known.contains(m.id) && seen.add(m.id)) PartMove(m.id, m.qty < 0 ? 0 : m.qty.floorToDouble()),
  ];
}

double movesQty(Iterable<PartMove> list) => list.fold(0.0, (a, m) => a + (m.qty > 0 ? m.qty : 0));

/// `mf577Minutes`.
double partsMinutes(Map<String, dynamic>? item, Map<String, dynamic>? cat, Iterable<PartMove> list) {
  var n = 0.0;
  for (final m in list) {
    final p = titlePart(item, m.id);
    if (p == null) continue;
    n += jsRound((m.qty > 0 ? m.qty : 0) * partSeconds(p, item, cat) / 60);
  }
  return n;
}

/// `mf577CatAmount`.
double partsCategoryAmount(Map<String, dynamic>? item, Map<String, dynamic>? cat, Iterable<PartMove> list) {
  var n = 0.0;
  for (final m in list) {
    final p = titlePart(item, m.id);
    if (p == null) continue;
    final q = m.qty > 0 ? m.qty : 0.0;
    final f = partFactor(p, item, cat);
    n += f == 1 ? q : jsRound(q * f * 100) / 100;
  }
  return n;
}

/// `mf577SetIn`: [value] is the part's reached number (progress) or its amount.
List<PartMove> setPart(Map<String, dynamic>? item, List<PartMove> list, String id, double value, {required bool reached}) {
  final p = titlePart(item, id);
  if (p == null) return list;
  final v = value < 0 ? 0.0 : value.floorToDouble();
  final from = jsNum(p['progress']), total = jsNum(p['total']) > 0 ? jsNum(p['total']) : 0.0;
  final qty = reached ? ((total > 0 && v > total ? total : v) - from).clamp(0, double.infinity).toDouble() : v;
  final out = cleanMoves(item, list);
  final i = out.indexWhere((m) => m.id == id);
  if (i >= 0) {
    out[i] = PartMove(id, qty);
  } else {
    out.add(PartMove(id, qty));
  }
  return out;
}

/// `mf577ToggleIn`: adds a part (1 unit) or removes it (never the last one).
List<PartMove> togglePart(Map<String, dynamic>? item, List<PartMove> list, String id) {
  final out = cleanMoves(item, list);
  final i = out.indexWhere((m) => m.id == id);
  if (i >= 0) {
    if (out.length > 1) out.removeAt(i);
  } else if (titlePart(item, id) != null) {
    out.add(PartMove(id, 1));
  }
  return out;
}

/// `mf577Restore`: the parts back to [before], then each move added (capped at
/// the part's total); the title becomes the sum, with no total.
void applyPartMoves(Map<String, dynamic> item, Map<String, double> before, List<List<PartMove>> moves, int now) {
  final parts = titleParts(item);
  for (final p in parts) {
    final b = before[jsStr(p['id'])];
    if (b != null) p['progress'] = jsOut(b);
  }
  for (final list in moves) {
    for (final m in list) {
      final p = parts.where((x) => jsStr(x['id']) == m.id).firstOrNull;
      if (p == null) continue;
      final t = jsNum(p['total']) > 0 ? jsNum(p['total']) : 0.0;
      final next = jsNum(p['progress']) + (m.qty > 0 ? m.qty : 0);
      p['progress'] = jsOut(t > 0 && next > t ? t : next);
    }
  }
  item['seasons'] = parts;
}

/// The progress of each part, by id.
Map<String, double> partsSnapshot(Map<String, dynamic>? item) => {for (final p in titleParts(item)) jsStr(p['id']): jsNum(p['progress'])};

/// `mf577Meta`: what History keeps for each moved part.
List<Map<String, dynamic>> partsHistory(Map<String, dynamic> item, Map<String, dynamic>? cat, Map<String, double> before, List<PartMove> list,
    {required bool repeat}) {
  return [
    for (final m in list)
      () {
        final p = titlePart(item, m.id);
        final from = before[m.id] ?? jsNum(p?['progress']);
        final t = jsNum(p?['total']) > 0 ? jsNum(p?['total']) : 0.0;
        return <String, dynamic>{
          'id': m.id,
          'name': jsStr(p?['name']).isEmpty ? 'Part' : jsStr(p?['name']),
          'kind': partKind(p),
          'unit': partUnit(p, item, cat),
          'qty': jsOut(m.qty),
          if (!repeat) 'from': jsOut(from),
          if (!repeat) 'to': jsOut(t > 0 && from + m.qty > t ? t : from + m.qty),
        };
      }(),
  ];
}

/// `mf577HistoryText`: "Mode · Competitive · Match 41 → 44 (+3)".
String partsHistoryText(Object? rows, String Function(String unit, double n) unitLabel) {
  final list = asList(rows).map(asMap).whereType<Map<String, dynamic>>().toList();
  return list.map((p) {
    final kind = jsStr(p['kind']);
    final name = '${kind.isEmpty ? '' : '$kind · '}${jsStr(p['name']).isEmpty ? 'Part' : jsStr(p['name'])}';
    final u = unitLabel(jsStr(p['unit']).isEmpty ? 'units' : jsStr(p['unit']), 1);
    final cap = u.isEmpty ? u : u[0].toUpperCase() + u.substring(1);
    return p['to'] != null
        ? '$name · $cap ${fmtN(jsNum(p['from']))} → ${fmtN(jsNum(p['to']))} (+${fmtN(jsNum(p['qty']))})'
        : '$name +${fmtN(jsNum(p['qty']))}';
  }).join(' · ');
}

/// Website v579 `mf579NextPartText`: "Mode · Live · Match 5 of 10" for a
/// recommended by-parts title (its default part's next unit), else ''.
String nextPartText(Map<String, dynamic>? item, Map<String, dynamic>? cat) {
  if (!isByParts(item)) return '';
  final part = defaultPart(item);
  if (part == null) return '';
  final u = unitLabel(partUnit(part, item, cat), 1);
  final cap = u.isEmpty ? u : u[0].toUpperCase() + u.substring(1);
  final next = jsNum(part['progress']) + 1, total = jsNum(part['total']) > 0 ? jsNum(part['total']) : 0.0;
  return '${partName(part)} · $cap ${fmtN(total > 0 && next > total ? total : next)}${total > 0 ? ' of ${fmtN(total)}' : ''}';
}

String fmtN(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// `mf577ParseTime`: "20" = 20 minutes; "mm:ss"; "h:mm:ss". Seconds, or 0.
int parsePartTime(String text) {
  final s = text.trim();
  if (s.isEmpty) return 0;
  final n = double.tryParse(s.replaceAll(',', '.'));
  if (n != null) return (n * 60).round();
  final m = RegExp(r'^(\d+):(\d{1,2})(?::(\d{1,2}))?$').firstMatch(s);
  if (m == null) return 0;
  return m[3] != null
      ? int.parse(m[1]!) * 3600 + int.parse(m[2]!) * 60 + int.parse(m[3]!)
      : int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

/// `mf577TimeText`.
String partTimeText(int secs) {
  if (secs <= 0) return '';
  final h = secs ~/ 3600, m = secs % 3600 ~/ 60, s = secs % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
