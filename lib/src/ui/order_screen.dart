// Personal Order: one title sequence (All titles or By category), add titles,
// move / position / remove, clear; category display order and visibility;
// Collection queues per task category (assign, rules, move, reset, remove);
// and the "Prioritize Personal Order" recommendation switch.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../logic/choice_layout.dart' show filterCategories, setCategories;
import '../logic/collections_logic.dart';
import '../logic/order_view.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'collections_screen.dart' show pickLibraryTitles, CollectionCover;
import '../platform/file_io.dart';
import 'floating_dock.dart' show recoveryShortcuts;
import 'recovery_screen.dart' show openRecovery;
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

  // Display only: search, filters, sort and the title view never change the Order.
  final _search = TextEditingController();
  String _cat = 'all', _status = 'all', _sort = 'order';
  String _tabCat = ''; // Tabs layout: the category shown
  String _query = ''; // the search, applied after a short pause while typing
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted && _query != text.trim().toLowerCase()) setState(() => _query = text.trim().toLowerCase());
    });
  }

  /// 9.0.0: the Order as shown, computed once per account change and filter.
  OrderTitlesModel _model(AccountView view) {
    final p = asMap(view.state['orderPlan']) ?? const <String, dynamic>{};
    final byId = memoFor(view, 'orderLibraryTitles', () => {for (final t in view.library) t.id: t});
    return memoFor(view, 'orderModel|$_cat|$_status|$_sort|$_query',
        () => OrderTitlesModel.build(p, byId, category: _cat, status: _status, sort: _sort, query: _query));
  }

  String get _titleView => AppPrefs.instance.get<String>('orderTitleView', 'list');
  int get _columns => AppPrefs.instance.get<int>('orderColumns', 2).clamp(1, 4);

  Future<void> _export(AccountView view) async {
    final ids = asList(asMap(view.state['orderPlan'])?['titleIds']);
    if (ids.isEmpty) return _toast(context, 'Your Order is empty.');
    final data = orderExport(Map<String, dynamic>.of(view.state), DateTime.now());
    final d = DateTime.now();
    final path = await saveTextFile(
        'MediaFlow_Order_${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.json',
        const JsonEncoder.withIndent('  ').convert(data));
    if (mounted && path != null) _toast(context, '${(data['titles'] as List).length} ordered titles exported ✓');
  }

  Future<void> _import() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Import an Order'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(hintText: 'Paste the contents of a MediaFlow_Order_….json export', border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final f = await pickTextFile();
              if (f != null) c.text = f.text;
            },
            child: const Text('Open file…'),
          ),
          TextButton(
            onPressed: () async {
              final clip = await Clipboard.getData('text/plain');
              if (clip?.text != null) c.text = clip!.text!;
            },
            child: const Text('Paste'),
          ),
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Import')),
        ],
      ),
    );
    c.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    Object? data;
    try {
      data = jsonDecode(text);
    } catch (_) {
      return _toast(context, 'That is not a MediaFlow Order export.');
    }
    ({int imported, int skipped, String? error})? r;
    await account.edit((s, now) => r = orderImport(s, data, now), label: 'Import Personal Order');
    if (!mounted || r == null) return;
    _toast(context, r!.error ?? 'Order imported: ${r!.imported} title${r!.imported == 1 ? '' : 's'}${r!.skipped > 0 ? ' · ${r!.skipped} unmatched skipped' : ''} ✓');
  }

  Future<void> _clear(int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Clear Personal Order?'),
        content: Text("You're about to remove $count title${count == 1 ? '' : 's'} from your Personal Order.\n\n"
            'Your Library will not be changed. Titles, progress, History, XP and scheduler data stay untouched. '
            'MediaFlow keeps one recovery copy so you can restore this exact Order afterward.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: MF.bad), onPressed: () => Navigator.pop(d, true), child: const Text('Clear Order')),
        ],
      ),
    );
    if (ok != true) return;
    await account.edit((s, now) => orderClear(s, now), label: 'Clear Order');
    if (mounted) _toast(context, 'Order cleared · Restore Last Order is available');
  }

  Future<void> _restoreLast() async {
    var n = 0;
    await account.edit((s, now) => n = orderRestoreLast(s, now), label: 'Restore last Order');
    if (mounted) _toast(context, n == 0 ? 'No cleared Order is available to restore.' : '$n ordered title${n == 1 ? '' : 's'} restored ✓');
  }

  /// `orderPlan.v288QueueView` (website v288/v289/v345/v364), unknown fields kept.
  static Map<String, dynamic> _queueView(Map<String, dynamic> p) {
    final x = asMap(p['v288QueueView']) ?? const <String, dynamic>{};
    return {
      ...x,
      'sectionOrder': x['sectionOrder'] == 'collections-first' ? 'collections-first' : 'regular-first',
      'showRegularQueues': x['showRegularQueues'] != false,
      'showCollectionQueues': x['showCollectionQueues'] != false,
      'showCollectionsInRegularQueues': x['showCollectionsInRegularQueues'] == true,
      'layoutMode': x['layoutMode'] == 'tabs' ? 'tabs' : 'lists',
      'collectionsBrowseMode': x['collectionsBrowseMode'] == 'tabs' ? 'tabs' : 'lists',
    };
  }

  Future<void> _setQueueView(String key, Object value) =>
      _order('Personal Order view', (plan, s, now, uid) => plan['v288QueueView'] = {..._queueView(plan), key: value});

  /// Website v363 "Lists per row".
  int _listColumns(AccountView view) {
    final n = jsNum(asMap(asMap(view.state['settings'])?['v363PersonalOrder'])?['listColumns']).toInt();
    return n >= 1 && n <= 4 ? n : 2;
  }

  Future<void> _queueTools(AccountView view) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => LiveBuilder(
        listenable: account,
        builder: (c, _) {
          final qv = _queueView(asMap(account.view?.state['orderPlan']) ?? const {});
          return SafeArea(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
              const Text('Queue tools', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Text('Display options for Personal Order, saved with your Order on every device.', style: TextStyle(color: MF.textDim, fontSize: 12)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show title queues'),
                value: qv['showRegularQueues'] == true,
                onChanged: (v) => _setQueueView('showRegularQueues', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show Collection queues'),
                value: qv['showCollectionQueues'] == true,
                onChanged: (v) => _setQueueView('showCollectionQueues', v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show assigned Collections inside title queues'),
                value: qv['showCollectionsInRegularQueues'] == true,
                onChanged: (v) => _setQueueView('showCollectionsInRegularQueues', v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Section order'),
                trailing: CompactDropdown<String>(
                  value: jsStr(qv['sectionOrder']),
                  items: const [('regular-first', 'Titles first'), ('collections-first', 'Collections first')],
                  onChanged: (v) => _setQueueView('sectionOrder', v),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Category layout'),
                trailing: CompactDropdown<String>(
                  value: jsStr(qv['layoutMode']),
                  items: const [('lists', 'Lists'), ('tabs', 'Tabs')],
                  onChanged: (v) => _setQueueView('layoutMode', v),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lists per row'),
                subtitle: const Text('On wide screens, By category · Lists'),
                trailing: CompactDropdown<int>(
                  value: _listColumns(account.view ?? view),
                  items: const [(1, '1'), (2, '2'), (3, '3'), (4, '4')],
                  onChanged: (v) => account.setSetting(['v363PersonalOrder', 'listColumns'], v),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: Listenable.merge([account, AppPrefs.instance]),
      builder: (context, _) {
        final view = account.view;
        if (view == null) return const SizedBox.shrink();
        final state = view.state;
        final p = asMap(state['orderPlan']) ?? const <String, dynamic>{};
        final model = _model(view);
        final byId = model.byId;
        final titleIds = model.titleIds;
        final prioritize = jsTruthy(asMap(state['settings'])?['prioritizePersonalOrder']);
        final byCategory = p['viewMode'] == 'category';
        final qv = _queueView(p);
        final canRestore = asList(asMap(p['lastClearedOrder'])?['titleIds']).isNotEmpty;
        final shown = model.shown;
        final posOf = model.posOf;
        final mixed = qv['showCollectionsInRegularQueues'] == true;
        final filtered = shown.length != titleIds.length || _sort != 'order';
        final grid = _titleView == 'covers' || _titleView == 'covers-title' || _titleView == 'cards';
        final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Prioritize Personal Order'),
            subtitle: const Text('MediaFlow Recommends picks the next title of your Order (and assigned Collections) in each category.'),
            value: prioritize,
            onChanged: (v) => account.setSetting(['prioritizePersonalOrder'], v),
          ),
          _AddBar(
            onAddTitles: () => _addTitles(view, titleIds),
            onAddCollection: () => _addCollection(context, account, view, _order, showInTitles: true),
            trailing: FilterChip(
              // 10.0.0: a plain icon in the label (as an avatar it was drawn
              // on a dark circle); ✓ when on.
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                if (!mixed) ...[Icon(Icons.collections_bookmark_outlined, size: 16, color: MF.accent), const SizedBox(width: 6)],
                const Text('Collections in this list'),
              ]),
              selected: mixed,
              onSelected: (v) => _setQueueView('showCollectionsInRegularQueues', v),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'all', label: Text('All titles')), ButtonSegment(value: 'category', label: Text('By category'))],
              selected: {byCategory ? 'category' : 'all'},
              onSelectionChanged: (s) => _order('Order view', (plan, st, now, uid) => plan['viewMode'] = s.first),
            ),
            if (byCategory)
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'lists', label: Text('Lists')), ButtonSegment(value: 'tabs', label: Text('Tabs'))],
                selected: {jsStr(qv['layoutMode'])},
                onSelectionChanged: (s) => _setQueueView('layoutMode', s.first),
              ),
            if (byCategory && qv['layoutMode'] != 'tabs')
              CompactDropdown<int>(
                value: _listColumns(view),
                items: const [(1, '1 list per row'), (2, '2 lists per row'), (3, '3 lists per row'), (4, '4 lists per row')],
                onChanged: (v) => account.setSetting(['v363PersonalOrder', 'listColumns'], v),
              ),
            PopupMenuButton<String>(
              tooltip: 'Order tools',
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (v) => switch (v) {
                'export' => _export(view),
                'import' => _import(),
                'clear' => _clear(titleIds.length),
                'restore' => _restoreLast(),
                'tools' => _queueTools(view),
                'recover' => openRecovery(context, account, ids: titleIds, label: 'Personal Order'),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'tools', child: Text('Queue tools…')),
                if (titleIds.isNotEmpty && recoveryShortcuts(asMap(state['settings']))['order'] == true)
                  const PopupMenuItem(value: 'recover', child: Text('Recover covers & details…')),
                const PopupMenuItem(value: 'export', child: Text('Export Order')),
                const PopupMenuItem(value: 'import', child: Text('Import Order…')),
                if (titleIds.isNotEmpty) const PopupMenuItem(value: 'clear', child: Text('Clear Order…', style: TextStyle(color: MF.bad))),
                if (canRestore) const PopupMenuItem(value: 'restore', child: Text('Restore last Order')),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            decoration: const InputDecoration(hintText: 'Search your Order', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            onChanged: _onSearch,
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              CompactDropdown<String>(
                value: _cat,
                items: [('all', 'All categories'), for (final c in filterCategories(view, keep: [_cat])) (c.id, c.name)],
                onChanged: (v) => setState(() => _cat = v),
              ),
              const SizedBox(width: 6),
              CompactDropdown<String>(
                value: _status,
                items: const [('all', 'Any status'), ('planned', 'Planned'), ('active', 'Active'), ('paused', 'Paused'), ('completed', 'Completed'), ('dropped', 'Dropped')],
                onChanged: (v) => setState(() => _status = v),
              ),
              const SizedBox(width: 6),
              CompactDropdown<String>(
                value: _sort,
                items: const [('order', 'Your order'), ('title', 'Title'), ('progress', 'Progress'), ('added', 'Recently added'), ('rating', 'Rating')],
                onChanged: (v) => setState(() => _sort = v),
              ),
              const SizedBox(width: 6),
              CompactDropdown<String>(
                value: _titleView,
                items: const [('list', 'List'), ('compact', 'Compact'), ('cards', 'Cards'), ('covers', 'Covers'), ('covers-title', 'Covers + title')],
                onChanged: (v) => AppPrefs.instance.set('orderTitleView', v),
              ),
              if (grid) ...[
                const SizedBox(width: 6),
                CompactDropdown<int>(
                  value: _columns,
                  items: const [(1, '1 column'), (2, '2 columns'), (3, '3 columns'), (4, '4 columns')],
                  onChanged: (v) => AppPrefs.instance.set('orderColumns', v),
                ),
              ],
            ]),
          ),
          if (filtered)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Showing ${shown.length} of ${titleIds.length}. Search, filters and sorting only change what you see, never your Order.',
                  style: TextStyle(color: MF.textDim, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          // 9.0.0: Collections in the titles list (All titles view; By
          // category places them inside each category's list instead).
          if (mixed && !byCategory) ..._allTitlesCollections(view),
          if (titleIds.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Your Order is empty. Add the titles you plan to watch or read next, in order.',
                  textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
            ),
        ]);
        Widget titles;
        if (byCategory && !filtered) {
          // v565: only the rows on screen are built (a big Order lagged).
          final blocks = _byCategory(view, p, model, qv);
          final tabs = qv['layoutMode'] == 'tabs';
          final width = MediaQuery.sizeOf(context).width;
          final perRow = tabs || width < 760 ? 1 : _listColumns(view).clamp(1, width >= 1300 ? 4 : (width >= 1000 ? 3 : 2));
          final items = <Widget Function()>[() => header, () => _categoryOrderRow(p)];
          if (tabs) {
            final ids = [for (final b in blocks) b.cid];
            final selected = ids.contains(_tabCat) ? _tabCat : (ids.isEmpty ? '' : ids.first);
            items.add(() => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    for (final b in blocks)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('${view.category(b.cid).name} · ${b.count}'),
                          selected: b.cid == selected,
                          onSelected: (_) => setState(() => _tabCat = b.cid),
                        ),
                      ),
                  ]),
                ));
            for (final b in blocks.where((b) => b.cid == selected)) {
              items.add(b.header);
              items.addAll(b.rows);
            }
          } else if (perRow <= 1) {
            for (final b in blocks) {
              items.add(b.header);
              items.addAll(b.rows);
            }
          } else {
            // Lists per row: categories side by side, one row of lists per item.
            for (var i = 0; i < blocks.length; i += perRow) {
              final group = blocks.sublist(i, (i + perRow).clamp(0, blocks.length));
              items.add(() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var j = 0; j < perRow; j++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: j < perRow - 1 ? 12 : 0),
                          child: j < group.length
                              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  group[j].header(),
                                  for (final r in group[j].rows) r(),
                                ])
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ]));
            }
          }
          titles = ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: items.length,
            itemBuilder: (context, i) => items[i](),
          );
        } else if (grid) {
          titles = CustomScrollView(slivers: [
            SliverPadding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), sliver: SliverToBoxAdapter(child: header)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: _titleView == 'cards' ? (_columns == 1 ? 4 : 1.6) : (_titleView == 'covers' ? .69 : .56),
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) => _tile(view, byId[shown[i]]!, posOf[shown[i]] ?? 0),
              ),
            ),
          ]);
        } else if (!filtered) {
          // Drag to reorder (the Order itself).
          titles = ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            header: header,
            buildDefaultDragHandles: false,
            itemCount: titleIds.length,
            onReorderItem: (from, to) =>
                _order('Reorder Personal Order', (plan, s, now, uid) => orderMoveTitle(plan, s, titleIds[from], toPosition: to)),
            itemBuilder: (context, i) => KeyedSubtree(
              key: ValueKey(titleIds[i]),
              child: _row(view, byId[titleIds[i]]!, i, titleIds.length, null, dragIndex: i),
            ),
          );
        } else {
          titles = ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: shown.length + 1,
            itemBuilder: (context, i) => i == 0 ? header : _row(view, byId[shown[i - 1]]!, posOf[shown[i - 1]] ?? 0, titleIds.length, null),
          );
        }
        final showTitles = qv['showRegularQueues'] == true || qv['showCollectionQueues'] != true;
        final showQueues = qv['showCollectionQueues'] == true;
        final sections = <(String, Widget)>[
          if (showTitles) ('Titles', titles),
          if (showQueues) ('Collection queues', _QueuesTab(account: account, view: view, order: _order, onAddTitles: () => _addTitles(view, titleIds))),
        ];
        if (qv['sectionOrder'] == 'collections-first') sections.setAll(0, sections.reversed.toList());
        return DefaultTabController(
          key: ValueKey('order-tabs-${sections.map((x) => x.$1).join()}'),
          length: sections.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Personal Order'),
              actions: [
                IconButton(
                  tooltip: 'Add titles',
                  icon: const Icon(Icons.playlist_add_rounded),
                  onPressed: () => _addTitles(view, titleIds),
                ),
                SyncIndicator(account: account),
              ],
              bottom: sections.length < 2 ? null : TabBar(tabs: [for (final x in sections) Tab(text: x.$1)]),
            ),
            body: sections.length < 2 ? sections.first.$2 : TabBarView(children: [for (final x in sections) x.$2]),
          ),
        );
      },
    );
  }

  /// A title in the Cards / Covers / Covers + title views.
  Widget _tile(AccountView view, LibraryTitle t, int position) {
    final cat = view.category(t.categoryId);
    if (_titleView == 'cards') {
      return InkWell(
        onTap: () => openTitle(context, account, t.id),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: MF.border)),
          child: Row(children: [
            Cover(title: t, category: cat, width: 44),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('#${position + 1}', style: TextStyle(color: MF.accent, fontWeight: FontWeight.w900, fontSize: 11)),
                Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${cat.name} · ${progressText(t, cat)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim, fontSize: 11)),
              ]),
            ),
          ]),
        ),
      );
    }
    return InkWell(
      onTap: () => openTitle(context, account, t.id),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            LayoutBuilder(builder: (context, c) => Cover(title: t, category: cat, width: c.maxWidth)),
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(8)),
                child: Text('${position + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
              ),
            ),
          ]),
        ),
        if (_titleView == 'covers-title')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _categoryOrderRow(Map<String, dynamic> p) => Row(children: [
        const Text('Category order', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        CompactDropdown<String>(
          value: p['categoryMode'] == 'custom' ? 'custom' : 'default',
          items: const [('default', 'Like Settings'), ('custom', 'Custom')],
          onChanged: (v) => _order('Order categories', (plan, s, now, uid) => orderSetCategoryMode(plan, s, v)),
        ),
      ]);

  List<Widget> _allTitlesCollections(AccountView view) {
    final queues = memoFor(view, 'orderQueues', () => orderQueues(view.state));
    final refs = memoFor(view, 'orderQueueRefs', () => _QueueRefs.of(view.state));
    final rows = <Widget>[];
    for (final q in queues) {
      final cat = view.category(q.categoryId);
      for (var i = 0; i < q.tokens.length; i++) {
        if (!q.tokens[i].startsWith('c:')) continue;
        rows.add(_CollectionQueueRow(view: view, refs: refs, category: cat, token: q.tokens[i], index: i, count: q.tokens.length, order: _order));
      }
    }
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Text('Collections · their number is their place in their category queue', style: TextStyle(color: MF.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      ...rows,
      const SizedBox(height: 8),
    ];
  }

  Future<void> _addTitles(AccountView view, List<String> titleIds, {String? categoryId}) async {
    final cat = categoryId == null ? null : view.category(categoryId);
    final ids = await pickLibraryTitles(context, view,
        exclude: {...titleIds, if (categoryId != null) for (final t in view.library) if (t.categoryId != categoryId) t.id},
        title: cat == null ? 'Add titles to Order' : 'Add ${cat.name} titles');
    if (ids == null || ids.isEmpty) return;
    await _order('Add to Personal Order', (plan, s, now, uid) => orderAddTitles(plan, s, ids));
    if (mounted) _toast(context, '${ids.length} title${ids.length == 1 ? '' : 's'} added to Order ✓');
  }

  /// One block per category: its header (with Add, move and hide) and its
  /// rows, built only when shown. With "Collections in this list" on, the
  /// rows follow the category's queue, so assigned Collections sit between
  /// the titles where MediaFlow Recommends meets them.
  List<({String cid, int count, Widget Function() header, List<Widget Function()> rows})> _byCategory(
      AccountView view, Map<String, dynamic> p, OrderTitlesModel model, Map<String, dynamic> qv) {
    final hidden = asList(p['hiddenCategories']).map(jsStr).toSet();
    final out = <({String cid, int count, Widget Function() header, List<Widget Function()> rows})>[];
    final byId = model.byId;
    final mixed = qv['showCollectionsInRegularQueues'] == true;
    final queues = mixed ? {for (final q in memoFor(view, 'orderQueues', () => orderQueues(view.state))) q.categoryId: q} : const <String, OrderQueue>{};
    final refs = mixed ? memoFor(view, 'orderQueueRefs', () => _QueueRefs.of(view.state)) : null;
    for (final cid in orderCategoryDisplay(p, view.state)) {
      final cat = view.category(cid);
      final ids = model.byCategory[cid] ?? const <String>[];
      final queue = queues[cid];
      final collectionCount = queue == null ? 0 : queue.tokens.where((t) => t.startsWith('c:')).length;
      final isHidden = hidden.contains(cid);
      Widget header() => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Row(children: [
              CategoryBadge(cat, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${cat.name} · ${ids.length}${collectionCount > 0 ? ' + $collectionCount Collection${collectionCount == 1 ? '' : 's'}' : ''}',
                    style: TextStyle(fontWeight: FontWeight.w900, color: MF.accent)),
              ),
              IconButton(
                tooltip: 'Add ${cat.name} titles',
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                onPressed: () => _addTitles(view, model.titleIds, categoryId: cid),
              ),
              IconButton(
                tooltip: 'Add a Collection to ${cat.name}',
                icon: const Icon(Icons.library_add_rounded, size: 18),
                onPressed: () => _addCollection(context, account, view, _order, categoryId: cid, showInTitles: true),
              ),
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
          );
      final rows = <Widget Function()>[];
      if (!isHidden) {
        if (queue != null && collectionCount > 0) {
          final tokens = queue.tokens;
          for (var k = 0; k < tokens.length; k++) {
            final token = tokens[k], pos = k;
            if (token.startsWith('t:')) {
              final id = token.substring(2);
              final t = byId[id];
              final ti = queue.titleIndex[id];
              if (t == null || ti == null) continue;
              rows.add(() => _row(view, t, ti, ids.length, cid, number: pos + 1));
            } else {
              rows.add(() => _CollectionQueueRow(
                    view: view, refs: refs!, category: cat, token: token, index: pos, count: tokens.length, order: _order));
            }
          }
        } else {
          for (var i = 0; i < ids.length; i++) {
            final id = ids[i], index = i, count = ids.length;
            rows.add(() => _row(view, byId[id]!, index, count, cid));
          }
        }
      }
      out.add((cid: cid, count: ids.length + collectionCount, header: header, rows: rows));
    }
    return out;
  }

  Widget _row(AccountView view, LibraryTitle t, int i, int count, String? categoryId, {int? dragIndex, int? number}) {
    final cat = view.category(t.categoryId);
    final compact = _titleView == 'compact';
    void move({int delta = 0, int? to}) =>
        _order('Reorder Personal Order', (plan, s, now, uid) => orderMoveTitle(plan, s, t.id, delta: delta, toPosition: to, categoryId: categoryId));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        if (dragIndex != null)
          ReorderableDragStartListener(index: dragIndex, child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.drag_indicator_rounded, color: MF.textDim))),
        SizedBox(width: 32, child: Text('${number ?? i + 1}', style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w800))),
        if (!compact) Cover(title: t, category: cat, width: 36),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => openTitle(context, account, t.id),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title, maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (!compact)
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

typedef _OrderEdit = Future<void> Function(
    String label, void Function(Map<String, dynamic> plan, Map<String, dynamic> state, int now, String Function() uid) f);

/// 9.0.0: the clear "Add title" / "Add collection" buttons, the same in both tabs.
class _AddBar extends StatelessWidget {
  const _AddBar({required this.onAddTitles, required this.onAddCollection, this.trailing});
  final VoidCallback onAddTitles;
  final VoidCallback onAddCollection;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(onPressed: onAddTitles, icon: const Icon(Icons.playlist_add_rounded), label: const Text('Add title')),
        FilledButton.tonalIcon(onPressed: onAddCollection, icon: const Icon(Icons.library_add_rounded), label: const Text('Add collection')),
        if (trailing != null) trailing!,
      ]);
}

/// Adds a Collection to a task category's queue (`v287AddCollectionAssignment`).
/// From the Titles tab it also turns on "Collections in this list" so the new
/// Collection shows up where it was added.
Future<void> _addCollection(BuildContext context, AccountController account, AccountView view, _OrderEdit order,
    {String? categoryId, bool showInTitles = false}) async {
  final cols = collectionsOf(view.state);
  if (cols.isEmpty) {
    _toast(context, 'You have no Collections yet. Create one in Collections first.');
    return;
  }
  String? col = jsStr(cols.first['id']);
  String? cat = categoryId ?? (view.categories.isEmpty ? null : view.categories.first.id);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(categoryId == null ? 'Add a Collection' : 'Add a Collection to ${view.category(categoryId).name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: col,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Collection'),
            items: [for (final c in cols) DropdownMenuItem(value: jsStr(c['id']), child: Text(jsStr(c['title']), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => set(() => col = v),
          ),
          if (categoryId == null)
            DropdownButtonFormField<String>(
              initialValue: cat,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Task category'),
              items: [for (final c in setCategories(view)) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => set(() => cat = v),
            ),
          const SizedBox(height: 8),
          Text('MediaFlow Recommends walks the Collection in its own order when it reaches it in the queue.',
              style: TextStyle(color: MF.textDim, fontSize: 12)),
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
  await order('Assign Collection', (plan, s, now, uid) {
    error = orderAssignCollection(plan, col!, cat!, now, uid);
    if (error == null && showInTitles && _OrderScreenState._queueView(plan)['showCollectionsInRegularQueues'] != true) {
      plan['v288QueueView'] = {..._OrderScreenState._queueView(plan), 'showCollectionsInRegularQueues': true};
    }
  });
  if (context.mounted) _toast(context, error ?? 'Collection added to ${view.category(cat!).name} ✓');
}

/// Assignments and Collections by id, once per account change.
class _QueueRefs {
  _QueueRefs(this.assignments, this.collections);
  final Map<String, Map<String, dynamic>> assignments;
  final Map<String, Map<String, dynamic>> collections;

  static _QueueRefs of(Map<String, dynamic> state) {
    final p = asMap(state['orderPlan']) ?? const <String, dynamic>{};
    return _QueueRefs(
      {for (final a in asList(p['collectionAssignments']).map(asMap).whereType<Map<String, dynamic>>()) jsStr(a['id']): a},
      {for (final c in collectionsOf(state)) jsStr(c['id']): c},
    );
  }
}

/// A Collection in a task category's queue: its place, rules, move, reset, remove.
class _CollectionQueueRow extends StatelessWidget {
  const _CollectionQueueRow(
      {required this.view, required this.refs, required this.category, required this.token, required this.index, required this.count, required this.order});
  final AccountView view;
  final _QueueRefs refs;
  final Category category;
  final String token;
  final int index, count;
  final _OrderEdit order;

  @override
  Widget build(BuildContext context) {
    final a = refs.assignments[token.substring(2)];
    final c = a == null ? null : refs.collections[jsStr(a['collectionId'])];
    if (a == null || c == null) return const SizedBox.shrink();
    final aid = jsStr(a['id']);
    final cid = category.id;
    void move({int delta = 0, int? to}) =>
        order('Reorder queue', (plan, s, now, uid) => orderMoveQueueToken(s, plan, cid, token, delta: delta, toIndex: to));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(12), border: Border.all(color: MF.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SizedBox(width: 28, child: Text('${index + 1}', style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w800))),
          CollectionCover(view: view, collection: c, size: 34),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(jsStr(c['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('Collection · ${collectionTitleIds(c).length} titles · ${asList(a['traversedTitleIds']).length} passed',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim, fontSize: 12)),
            ]),
          ),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_upward_rounded, size: 18), onPressed: index == 0 ? null : () => move(delta: -1)),
          IconButton(
              visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_downward_rounded, size: 18), onPressed: index >= count - 1 ? null : () => move(delta: 1)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'top') move(to: 0);
              if (v == 'bottom') move(to: count - 1);
              if (v == 'reset') order('Reset Collection queue', (plan, s, now, uid) => orderSetAssignmentRule(plan, aid, 'reset', '', now));
              if (v == 'remove') order('Remove Collection from queue', (plan, s, now, uid) => orderRemoveAssignment(plan, aid));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'top', child: Text('Move to top')),
              PopupMenuItem(value: 'bottom', child: Text('Move to bottom')),
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

/// Collection queues: every task category's queue, titles and Collections
/// mixed. Computed once per account change; only the rows on screen are built.
class _QueuesTab extends StatelessWidget {
  const _QueuesTab({required this.account, required this.view, required this.order, required this.onAddTitles});
  final AccountController account;
  final AccountView view;
  final _OrderEdit order;
  final VoidCallback onAddTitles;

  @override
  Widget build(BuildContext context) {
    final queues = memoFor(view, 'orderQueues', () => orderQueues(view.state));
    final refs = memoFor(view, 'orderQueueRefs', () => _QueueRefs.of(view.state));
    final byId = memoFor(view, 'orderLibraryTitles', () => {for (final t in view.library) t.id: t});
    final items = <Widget Function()>[
      () => Text('Each task category can mix ordered titles with Collections. MediaFlow Recommends walks the queue from the top.',
          style: TextStyle(color: MF.textDim)),
      () => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _AddBar(onAddTitles: onAddTitles, onAddCollection: () => _addCollection(context, account, view, order)),
          ),
      if (queues.isEmpty)
        () => Padding(padding: const EdgeInsets.all(24), child: Text('No queues yet.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim))),
    ];
    for (final q in queues) {
      final cat = view.category(q.categoryId);
      items.add(() => Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 6),
            child: Row(children: [
              CategoryBadge(cat, size: 24),
              const SizedBox(width: 8),
              Expanded(child: Text('${cat.name} · ${q.tokens.length}', style: TextStyle(fontWeight: FontWeight.w900, color: MF.accent))),
              IconButton(
                tooltip: 'Add a Collection to ${cat.name}',
                icon: const Icon(Icons.library_add_rounded, size: 18),
                onPressed: () => _addCollection(context, account, view, order, categoryId: cat.id),
              ),
            ]),
          ));
      for (var i = 0; i < q.tokens.length; i++) {
        final token = q.tokens[i], index = i, count = q.tokens.length;
        if (token.startsWith('t:')) {
          final t = byId[token.substring(2)];
          if (t == null) continue;
          items.add(() => _titleToken(context, cat, t, token, index, count));
        } else {
          items.add(() => _CollectionQueueRow(view: view, refs: refs, category: cat, token: token, index: index, count: count, order: order));
        }
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: items.length,
      itemBuilder: (context, i) => items[i](),
    );
  }

  Widget _titleToken(BuildContext context, Category cat, LibraryTitle t, String token, int i, int count) {
    void move(int delta) => order('Reorder queue', (plan, s, now, uid) => orderMoveQueueToken(s, plan, cat.id, token, delta: delta));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 28, child: Text('${i + 1}', style: TextStyle(color: MF.textDim))),
        Cover(title: t, category: cat, width: 30),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => openTitle(context, account, t.id),
            child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_upward_rounded, size: 18), onPressed: i == 0 ? null : () => move(-1)),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_downward_rounded, size: 18), onPressed: i >= count - 1 ? null : () => move(1)),
      ]),
    );
  }
}
