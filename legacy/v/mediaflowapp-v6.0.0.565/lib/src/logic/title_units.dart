// A title's own unit (website v565, 411-v565-titles.js).
//
// Library item fields:
//   mf565Unit            text unit for this title ('' = the category's unit), e.g. 'matches'
//   mf565SecondsPerUnit  runtime of one of this title's units in seconds (0 = the category's)
// Amounts that belong to the CATEGORY (a session's target/actual amount, tasks,
// XP, balance) are converted with the runtimes: 3 matches of 20 min = 1 session
// of 60 min. Without its own runtime a title's unit counts 1 for 1. The title's
// own progress and the per-title qty in a log stay in the title's unit.

import '../util/js.dart';

/// `mf565CatSeconds`: one category unit in seconds.
int categorySecondsPerUnit(Map<String, dynamic>? cat) {
  final s = jsNumOrNull(cat?['secondsPerUnit']);
  if (s != null && s.isFinite && s > 0) return s.floor();
  final m = jsNum(cat?['minutesPerUnit']) * 60;
  return m > 0 ? m.round() : 0;
}

/// `mf565OwnUnit`: the title's own unit, or '' when it uses its category's.
String ownUnit(Map<String, dynamic>? item) {
  final u = jsStr(item?['mf565Unit']).trim();
  return u.length > 40 ? u.substring(0, 40) : u;
}

/// `mf565UnitKey`: the unit this title is logged in.
String titleUnit(Map<String, dynamic>? item, Map<String, dynamic>? cat) {
  final own = ownUnit(item);
  if (own.isNotEmpty) return own;
  final u = jsStr(cat?['unit']);
  return u.isEmpty ? 'episodes' : u;
}

/// `mf565UnitFactor`: category units per one of this title's units.
double unitFactor(Map<String, dynamic>? item, Map<String, dynamic>? cat) {
  if (item == null || ownUnit(item).isEmpty) return 1;
  final own = jsNum(item['mf565SecondsPerUnit']).floor();
  final base = categorySecondsPerUnit(cat);
  return own > 0 && base > 0 ? own / base : 1;
}

/// `mf565ToCategoryAmount`: an amount of this title's units in category units.
double toCategoryAmount(Map<String, dynamic>? item, Map<String, dynamic>? cat, Object? qty) {
  final n = jsNum(qty) > 0 ? jsNum(qty) : 0.0;
  final f = unitFactor(item, cat);
  return f == 1 ? n : (n * f * 100).round() / 100;
}

/// `mf565TitleSeconds`: one of this title's units in seconds.
int titleSecondsPerUnit(Map<String, dynamic>? item, Map<String, dynamic>? cat) {
  final own = jsNum(item?['mf565SecondsPerUnit']).floor();
  return ownUnit(item).isNotEmpty && own > 0 ? own : categorySecondsPerUnit(cat);
}
