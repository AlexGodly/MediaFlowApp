// Personal Order: one title sequence (All titles or By category), add titles,
// move / position / remove, clear; category display order and visibility;
// Collection queues per task category (assign, rules, move, reset, remove);
// and the "Prioritize Personal Order" recommendation switch.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account_controller.dart';
import '../logic/collections_logic.dart';
import '../logic/recommend.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'collections_screen.dart' show pickLibraryTitles, CollectionCover;
import 'theme.dart';
import 'title_screen.dart';
import 'widgets.dart';

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  AccountController get account => widget.account;

  Future<void> _order(String label, void Function(Map<String, dynamic> plan, Map<String, dynamic> state, int now, String Function() uid) f) =>
      account.edit((s, now) {
        var k = 0;
        String uid() => mediaFlowUid(now + k++);
        orderEdit(s, now, uid, (p) => f(p, s, now, uid));
      }, label: label);

  Future<int?> _askPosition(int current, int max) async {
    final c = TextEditingController(text: '$current');
    final v = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Move to position'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Position (1–$max)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, int.tryParse(c.text)), child: const Text('Move')),
        ],
      ),
    );
    c.dispose();
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: account,
      builder: (context, _) {
        final view = account.view;
        if (view == null) return const SizedBox.shrink();
        final state = view.state;
        final p = asMap(state['orderPlan']) ?? const <String, dynamic>{};
        final byId = {for (final t in view.library) t.id: t};
        final titleIds = [for (final x in asList(p['titleIds'])) if (byId.containsKey(jsStr(x))) jsStr(x)];
        final prioritize = jsTruthy(asMap(state['settings'])?['prioritizePersonalOrder']);
        final byCategory = p['viewMode'] == 'category';
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Personal Order'),
              actions: [SyncIndicator(account: account)],
              bottom: const TabBar(tabs: [Tab(text: 'Titles'), Tab(text: 'Collection queues')]),
            ),
            floatingActionButton: FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                final ids = await pickLibraryTitles(context, view, exclude: titleIds.toSet(), title: 'Add titles to Order');
                if (ids == null || ids.isEmpty) return;
                await _order('Add to Personal Order', (plan, s, now, uid) => orderAddTitles(plan, s, ids));
                if (context.mounted) _toast(context, 'Titles added to Order ✓');
              },
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('Add titles'),
            ),
            body: TabBarView(children: [
              ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Prioritize Personal Order'),
                  subtitle: const Text('MediaFlow Recommends picks the next title of your Order (and assigned Collections) in each category.'),
                  value: prioritize,
                  onChanged: (v) => account.setSetting(['prioritizePersonalOrder'], v),
                ),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SegmentedButton<String>(
                    segments: const [ButtonSegment(value: 'all', label: Text('All titles')), ButtonSegment(value: 'category', label: Text('By category'))],
                    selected: {byCategory ? 'category' : 'all'},
                    onSelectionChanged: (s) => _order('Order view', (plan, st, now, uid) => plan['viewMode'] = s.first),
                  ),
                  if (titleIds.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('Clear your Order?'),
                            content: const Text('Every title is removed from your Order. Nothing is deleted from the Library. Undo is available.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Clear')),
                            ],
                          ),
                        );
                        if (ok == true) await _order('Clear Order', (plan, s, now, uid) => orderClear(plan));
                      },
                      child: const Text('Clear Order', style: TextStyle(color: MF.bad)),
                    ),
                ]),
                const SizedBox(height: 8),
                if (titleIds.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Your Order is empty. Add the titles you plan to watch or read next, in order.',
                        textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
                  )
                else if (!byCategory)
                  for (var i = 0; i < titleIds.length; i++) _row(view, byId[titleIds[i]]!, i, titleIds.length, null)
                else
                  ..._byCategory(view, p, titleIds, byId),
              ]),
              _QueuesTab(account: account, view: view, order: _order),
            ]),
          ),
        );
      },
    );
  }

  List<Widget> _byCategory(AccountView view, Map<String, dynamic> p, List<String> titleIds, Map<String, LibraryTitle> byId) {
    final hidden = asList(p['hiddenCategories']).map(jsStr).toSet();
    final out = <Widget>[
      Row(children: [
        const Text('Category order', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        CompactDropdown<String>(
          value: p['categoryMode'] == 'custom' ? 'custom' : 'default',
          items: const [('default', 'Like Settings'), ('custom', 'Custom')],
          onChanged: (v) => _order('Order categories', (plan, s, now, uid) => orderSetCategoryMode(plan, s, v)),
        ),
      ]),
    ];
    for (final cid in orderCategoryDisplay(p, view.state)) {
      final cat = view.category(cid);
      final ids = titleIds.where((id) => byId[id]!.categoryId == cid).toList();
      final isHidden = hidden.contains(cid);
      out.add(Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Row(children: [
          CategoryBadge(cat, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text('${cat.name} · ${ids.length}', style: TextStyle(fontWeight: FontWeight.w900, color: MF.accent))),
          if (p['categoryMode'] == 'custom') ...[
            IconButton(icon: const Icon(Icons.arrow_upward_rounded, size: 18), onPressed: () => _order('Order categories', (plan, s, now, uid) => orderMoveCategory(plan, s, cid, -1))),
            IconButton(icon: const Icon(Icons.arrow_downward_rounded, size: 18), onPressed: () => _order('Order categories', (plan, s, now, uid) => orderMoveCategory(plan, s, cid, 1))),
          ],
          IconButton(
            tooltip: isHidden ? 'Show category' : 'Hide category',
            icon: Icon(isHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 18),
            onPressed: () => _order('Order categories', (plan, s, now, uid) => orderToggleCategory(plan, cid)),
          ),
        ]),
      ));
      if (!isHidden) {
        for (var i = 0; i < ids.length; i++) {
          out.add(_row(view, byId[ids[i]]!, i, ids.length, cid));
        }
      }
    }
    return out;
  }

  Widget _row(AccountView view, LibraryTitle t, int i, int count, String? categoryId) {
    final cat = view.category(t.categoryId);
    void move({int delta = 0, int? to}) =>
        _order('Reorder Personal Order', (plan, s, now, uid) => orderMoveTitle(plan, s, t.id, delta: delta, toPosition: to, categoryId: categoryId));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 32, child: Text('${i + 1}', style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w800))),
        Cover(title: t, category: cat, width: 36),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => openTitle(context, account, t.id),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${cat.name} · ${progressText(t, cat)} · ${statusLabel(t.status)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: MF.textDim, fontSize: 12)),
            ]),
          ),
        ),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_upward_rounded, size: 18), onPressed: i == 0 ? null : () => move(delta: -1)),
        IconButton(
            visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_downward_rounded, size: 18), onPressed: i >= count - 1 ? null : () => move(delta: 1)),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'pos') {
              final pos = await _askPosition(i + 1, count);
              if (pos != null) move(to: pos - 1);
            } else if (v == 'top') {
              move(to: 0);
            } else if (v == 'bottom') {
              move(to: count - 1);
            } else if (v == 'remove') {
              await _order('Remove from Personal Order', (plan, s, now, uid) => orderRemoveTitle(plan, t.id));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'pos', child: Text('Move to position…')),
            PopupMenuItem(value: 'top', child: Text('Move to top')),
            PopupMenuItem(value: 'bottom', child: Text('Move to bottom')),
            PopupMenuItem(value: 'remove', child: Text('Remove from Order')),
          ],
        ),
      ]),
    );
  }
}

class _QueuesTab extends StatelessWidget {
  const _QueuesTab({required this.account, required this.view, required this.order});
  final AccountController account;
  final AccountView view;
  final Future<void> Function(String label, void Function(Map<String, dynamic> plan, Map<String, dynamic> state, int now, String Function() uid) f) order;

  Future<void> _assign(BuildContext context) async {
    final cols = collectionsOf(view.state);
    if (cols.isEmpty) {
      _toast(context, 'Create a Collection first.');
      return;
    }
    String? col = jsStr(cols.first['id']);
    String? cat = view.categories.isEmpty ? null : view.categories.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Add a Collection to a queue'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: col,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Collection'),
              items: [for (final c in cols) DropdownMenuItem(value: jsStr(c['id']), child: Text(jsStr(c['title'])))],
              onChanged: (v) => set(() => col = v),
            ),
            DropdownButtonFormField<String>(
              initialValue: cat,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Task category'),
              items: [for (final c in view.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => set(() => cat = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (ok != true || col == null || cat == null) return;
    String? error;
    await order('Assign Collection', (plan, s, now, uid) => error = orderAssignCollection(plan, col!, cat!, now, uid));
    if (context.mounted) _toast(context, error ?? 'Collection added to ${view.category(cat!).name} queue ✓');
  }

  @override
  Widget build(BuildContext context) {
    final state = view.state;
    final p = asMap(state['orderPlan']) ?? const <String, dynamic>{};
    final assignments = {for (final a in asList(p['collectionAssignments']).map(asMap).whereType<Map<String, dynamic>>()) jsStr(a['id']): a};
    final cols = {for (final c in collectionsOf(state)) jsStr(c['id']): c};
    final byId = {for (final t in view.library) t.id: t};
    // Read-only: the queue as the recommender sees it (reconciled on a copy).
    final copy = {...state, 'orderPlan': Map<String, dynamic>.from(p)..['categoryQueues'] = Map<String, dynamic>.from(asMap(p['categoryQueues']) ?? const {})};
    final r = Recommender(copy, now: 0);
    final cats = view.categories.where((c) => assignments.values.any((a) => jsStr(a['categoryId']) == c.id) || asList(p['titleIds']).any((id) => byId[jsStr(id)]?.categoryId == c.id)).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
      Text('Each task category can mix ordered titles with Collections. MediaFlow Recommends walks the queue from the top.',
          style: TextStyle(color: MF.textDim)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(onPressed: () => _assign(context), icon: const Icon(Icons.add_rounded), label: const Text('Add Collection to a queue')),
      ),
      if (cats.isEmpty)
        Padding(padding: EdgeInsets.all(24), child: Text('No queues yet.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim))),
      for (final cat in cats) ...[
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Row(children: [
            CategoryBadge(cat, size: 24),
            const SizedBox(width: 8),
            Text(cat.name, style: TextStyle(fontWeight: FontWeight.w900, color: MF.accent)),
          ]),
        ),
        for (final (i, token) in r.reconcileQueue(cat.id).indexed) _token(context, cat, token, i, r.reconcileQueue(cat.id).length, assignments, cols, byId),
      ],
    ]);
  }

  Widget _token(BuildContext context, Category cat, String token, int i, int count, Map<String, Map<String, dynamic>> assignments,
      Map<String, Map<String, dynamic>> cols, Map<String, LibraryTitle> byId) {
    void move(int delta) => order('Reorder queue', (plan, s, now, uid) => orderMoveQueueToken(s, plan, cat.id, token, delta: delta));
    final arrows = [
      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_upward_rounded, size: 18), onPressed: i == 0 ? null : () => move(-1)),
      IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_downward_rounded, size: 18), onPressed: i >= count - 1 ? null : () => move(1)),
    ];
    if (token.startsWith('t:')) {
      final t = byId[token.substring(2)];
      if (t == null) return const SizedBox.shrink();
      return Row(children: [
        SizedBox(width: 28, child: Text('${i + 1}', style: TextStyle(color: MF.textDim))),
        Cover(title: t, category: cat, width: 30),
        const SizedBox(width: 8),
        Expanded(child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ...arrows,
      ]);
    }
    final a = assignments[token.substring(2)];
    final c = a == null ? null : cols[jsStr(a['collectionId'])];
    if (a == null || c == null) return const SizedBox.shrink();
    final aid = jsStr(a['id']);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(width: 28, child: Text('${i + 1}', style: TextStyle(color: MF.textDim))),
          CollectionCover(view: view, collection: c, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Collection · ${jsStr(c['title'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${collectionTitleIds(c).length} titles · ${asList(a['traversedTitleIds']).length} passed', style: TextStyle(color: MF.textDim, fontSize: 12)),
            ]),
          ),
          ...arrows,
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'reset') order('Reset Collection queue', (plan, s, now, uid) => orderSetAssignmentRule(plan, aid, 'reset', '', now));
              if (v == 'remove') order('Remove Collection from queue', (plan, s, now, uid) => orderRemoveAssignment(plan, aid));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reset', child: Text('Reset queue progress')),
              PopupMenuItem(value: 'remove', child: Text('Remove from Personal Order')),
            ],
          ),
        ]),
        Wrap(spacing: 8, runSpacing: 4, children: [
          CompactDropdown<String>(
            value: jsStr(a['categoryRule']) == 'force' ? 'force' : 'match',
            items: const [('match', 'Only titles in this category'), ('force', 'Every title in the Collection')],
            onChanged: (v) => order('Collection queue rule', (plan, s, now, uid) => orderSetAssignmentRule(plan, aid, 'categoryRule', v, now)),
            maxWidth: 260,
          ),
          CompactDropdown<String>(
            value: jsStr(a['completedRule']) == 'include' ? 'include' : 'skip',
            items: const [('skip', 'Skip completed titles'), ('include', 'Include completed titles')],
            onChanged: (v) => order('Collection queue rule', (plan, s, now, uid) => orderSetAssignmentRule(plan, aid, 'completedRule', v, now)),
            maxWidth: 260,
          ),
        ]),
      ]),
    );
  }
}
