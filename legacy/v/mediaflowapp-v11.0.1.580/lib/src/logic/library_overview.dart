// Library Overview (website v53LibraryOverview + v183LibraryOverviewEstimate,
// categories from v508Panels.libraryOverview). Display only: estimates for
// unknown totals are never saved. test/library_overview_test.dart checks it
// against the website's own functions.

import 'dart:math' as math;

import '../util/js.dart';
import 'extras.dart' show visiblePanelCategories;

class OverviewRow {
  OverviewRow(this.category);
  final Map<String, dynamic> category;
  int items = 0;
  double done = 0, knownDone = 0, knownTotal = 0;
  bool unknown = false;

  /// The total shown (estimated when [estimated]) and the bar's percentage.
  double total = 0;
  int pct = 0;
  bool estimated = false;

  String get id => jsStr(category['id']);

  /// "done / total (pct%)", "done / ≈total (~pct%)" or "0 / -".
  String get label {
    String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : '$v';
    if (items == 0) return '0 / -';
    return estimated ? '${n(done)} / ≈${n(total)} (~$pct%)' : '${n(done)} / ${n(total)} ($pct%)';
  }
}

class LibraryOverview {
  LibraryOverview(this.rows, this.overallPct, this.totalDone, this.totalAll);
  final List<OverviewRow> rows;
  final int overallPct;
  final double totalDone, totalAll;
}

/// The overview for [categories] (default: the categories Settings → Library
/// Overview shows, in its order).
LibraryOverview libraryOverview(Map<String, dynamic> state, {List<Map<String, dynamic>>? categories}) {
  final cats = categories ?? visiblePanelCategories(state, 'libraryOverview');
  final byCat = <String, OverviewRow>{};
  final knownSum = <String, double>{}, knownCount = <String, int>{}, unknownCount = <String, int>{};
  double totalDone = 0, totalAll = 0;
  for (final raw in asList(state['library'])) {
    final i = asMap(raw);
    if (i == null) continue;
    final cid = jsStr(i['categoryId']);
    final x = byCat.putIfAbsent(cid, () => OverviewRow(const {}));
    final progress = math.max(0.0, jsNum(i['progress']).toDouble());
    final total = jsNum(i['total']).toDouble();
    x.items++;
    x.done += progress;
    if (total > 0) {
      x.knownDone += math.min(progress, total);
      x.knownTotal += total;
      totalDone += math.min(progress, total);
      totalAll += total;
      knownSum[cid] = (knownSum[cid] ?? 0) + total;
      knownCount[cid] = (knownCount[cid] ?? 0) + 1;
    } else {
      x.unknown = true;
      unknownCount[cid] = (unknownCount[cid] ?? 0) + 1;
    }
  }
  final rows = <OverviewRow>[];
  for (final cat in cats) {
    final id = jsStr(cat['id']);
    final x = byCat[id];
    final r = OverviewRow(cat);
    if (x != null) {
      r
        ..items = x.items
        ..done = x.done
        ..knownDone = x.knownDone
        ..knownTotal = x.knownTotal
        ..unknown = x.unknown;
    }
    // v183LibraryOverviewEstimate
    if (r.items == 0) {
      r.total = 0;
      r.pct = 0;
    } else if (!r.unknown && r.knownTotal > 0) {
      r.total = r.knownTotal;
      r.pct = math.min(100, (r.knownDone / r.knownTotal * 100).round());
    } else {
      final kc = knownCount[id] ?? 0;
      final knownAvg = kc > 0 ? knownSum[id]! / kc : 0.0;
      final observed = math.max(0.0, r.done);
      final baseline = math.max(1.0, jsNum(cat['target']) == 0 ? 1.0 : jsNum(cat['target']).toDouble());
      final perUnknown = knownAvg > 0 ? knownAvg : [baseline * 4, observed / math.max(1, r.items) * 1.35, 12.0].reduce(math.max);
      final estimatedTotal = [
        (r.knownTotal + (unknownCount[id] ?? 0) * perUnknown).ceilToDouble(),
        (observed * 1.12).ceilToDouble(),
        observed == 0 ? 1.0 : observed,
      ].reduce(math.max);
      r.total = estimatedTotal;
      r.pct = math.min(99, (observed / estimatedTotal * 100).round());
      r.estimated = true;
    }
    rows.add(r);
  }
  return LibraryOverview(rows, totalAll > 0 ? (totalDone / totalAll * 100).round() : 0, totalDone, totalAll);
}
