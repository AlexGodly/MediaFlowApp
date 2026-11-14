// 9.0.0: Personal Order view models, computed once per account change and
// filter, so the screen only lays out the rows on screen (31k-title accounts
// froze: every rebuild re-filtered the Order and the Collection queues
// re-scanned the whole Library for every row).

import '../state/models.dart';
import '../util/js.dart';
import 'collections_logic.dart';
import 'recommend.dart';
import 'title_names.dart' show nameMatches;

/// The Order as shown: the saved sequence, each title's place in it and the
/// titles left after search, filters and sorting (never changes the Order).
class OrderTitlesModel {
  OrderTitlesModel._(this.byId, this.titleIds, this.posOf, this.shown);

  final Map<String, LibraryTitle> byId;
  final List<String> titleIds;
  final Map<String, int> posOf;
  final List<String> shown;

  bool get filtered => shown.length != titleIds.length;

  /// Ordered titles grouped by category, in Order sequence.
  late final Map<String, List<String>> byCategory = () {
    final out = <String, List<String>>{};
    for (final id in titleIds) {
      (out[byId[id]!.categoryId] ??= []).add(id);
    }
    return out;
  }();

  static OrderTitlesModel build(
    Map<String, dynamic> orderPlan,
    Map<String, LibraryTitle> byId, {
    String category = 'all',
    String status = 'all',
    String sort = 'order',
    String query = '',
  }) {
    final seen = <String>{};
    final titleIds = <String>[
      for (final x in asList(orderPlan['titleIds']))
        if (byId.containsKey(jsStr(x)) && seen.add(jsStr(x))) jsStr(x),
    ];
    final posOf = <String, int>{for (var i = 0; i < titleIds.length; i++) titleIds[i]: i};
    final q = query.trim().toLowerCase();
    List<String> shown;
    if (category == 'all' && status == 'all' && q.isEmpty) {
      shown = titleIds;
    } else {
      shown = [
        for (final id in titleIds)
          if ((category == 'all' || byId[id]!.categoryId == category) &&
              (status == 'all' || byId[id]!.status == status) &&
              (q.isEmpty || nameMatches(byId[id]!.raw, q)))
            id,
      ];
    }
    if (sort != 'order') {
      int cmp(String a, String b) {
        final x = byId[a]!, y = byId[b]!;
        final r = switch (sort) {
          'title' => x.title.toLowerCase().compareTo(y.title.toLowerCase()),
          'progress' => y.progress.compareTo(x.progress),
          'added' => jsNum(y.raw['createdAt']).compareTo(jsNum(x.raw['createdAt'])),
          'rating' => (y.rating ?? 0).compareTo(x.rating ?? 0),
          _ => 0,
        };
        return r != 0 ? r : posOf[a]! - posOf[b]!;
      }

      shown = [...shown]..sort(cmp);
    }
    return OrderTitlesModel._(byId, titleIds, posOf, shown);
  }
}

/// One task category's queue: ordered titles mixed with assigned Collections
/// (`t:<titleId>` / `c:<assignmentId>`), as MediaFlow Recommends walks it.
class OrderQueue {
  OrderQueue(this.categoryId, this.tokens);
  final String categoryId;
  final List<String> tokens;

  /// A title token's place among the category's titles only (title moves
  /// keep using the title sequence, like the website).
  late final Map<String, int> titleIndex = () {
    final out = <String, int>{};
    for (final t in tokens) {
      if (t.startsWith('t:')) out[t.substring(2)] = out.length;
    }
    return out;
  }();
}

/// Every category's queue, read-only (reconciled on a copy of the plan), in
/// category display order. Categories with nothing queued are left out unless
/// [includeEmpty].
List<OrderQueue> orderQueues(Map<String, dynamic> state, {bool includeEmpty = false}) {
  final p = asMap(state['orderPlan']) ?? const <String, dynamic>{};
  final copy = {
    ...state,
    'orderPlan': Map<String, dynamic>.from(p)..['categoryQueues'] = Map<String, dynamic>.from(asMap(p['categoryQueues']) ?? const {}),
  };
  final r = Recommender(copy, now: 0);
  final out = <OrderQueue>[];
  for (final cid in orderCategoryDisplay(p, state)) {
    if (cid.isEmpty) continue;
    final tokens = List<String>.unmodifiable(r.reconcileQueue(cid));
    if (tokens.isEmpty && !includeEmpty) continue;
    out.add(OrderQueue(cid, tokens));
  }
  return out;
}
