// Personal Order: one title sequence (All titles or By category), add titles,
// move / position / remove, clear; category display order and visibility;
// Collection queues per task category (assign, rules, move, reset, remove);
// and the "Prioritize Personal Order" recommendation switch.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../logic/collections_logic.dart';
import '../logic/recommend.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'collections_screen.dart' show pickLibraryTitles, CollectionCover;
import '../platform/file_io.dart';
import 'floating_dock.dart' show recoveryShortcuts;
import 'recovery_screen.dart' show openRecovery;
import 'theme.dart';
import 'title_screen.dart';
import 'widgets.dart';
import '../logic/title_names.dart' show nameMatches;

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

  List<String> _visible(AccountView view, List<String> ids, Map<String, LibraryTitle> byId) {
    final q = _search.text.trim().toLowerCase();
    var out = [
      for (final id in ids)
        if ((_cat == 'all' || byId[id]!.categoryId == _cat) &&
            (_status == 'all' || byId[id]!.status == _status) &&
            (q.isEmpty || nameMatches(byId[id]!.raw, q)))
          id,
    ];
    if (_sort != 'order') {
      final pos = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      int cmp(String a, String b) {
        final x = byId[a]!, y = byId[b]!;
        final r = switch (_sort) {
          'title' => x.title.toLowerCase().compareTo(y.title.toLowerCase()),
          'progress' => y.progress.compareTo(x.progress),
          'added' => jsNum(y.raw['createdAt']).compareTo(jsNum(x.raw['createdAt'])),
          'rating' => (y.rating ?? 0).compareTo(x.rating ?? 0),
          _ => 0,
        };
        return r != 0 ? r : pos[a]! - pos[b]!;
      }

      out = [...out]..sort(cmp);
    }
    return out;
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
        final byId = memoFor(view, 'libraryById', () => {for (final t in view.library) t.id: t});
        final titleIds = [for (final x in asList(p['titleIds'])) if (byId.containsKey(jsStr(x))) jsStr(x)];
        final prioritize = jsTruthy(asMap(state['settings'])?['prioritizePersonalOrder']);
        final byCategory = p['viewMode'] == 'category';
        final qv = _queueView(p);
        final canRestore = asList(asMap(p['lastClearedOrder'])?['titleIds']).isNotEmpty;
        final shown = _visible(view, titleIds, byId);
        // Each title's place in the Order, computed once per change (was a scan per row).
        final posOf = <String, int>{for (var i = 0; i < titleIds.length; i++) titleIds[i]: i};
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
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              CompactDropdown<String>(
                value: _cat,
                items: [('all', 'All categories'), for (final c in view.categories) (c.id, c.name)],
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
          final blocks = _byCategory(view, p, titleIds, byId, qv);
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
          if (showQueues) ('Collection queues', _QueuesTab(account: account, view: view, order: _order)),
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
                  onPressed: () async {
                    final ids = await pickLibraryTitles(context, view, exclude: titleIds.toSet(), title: 'Add titles to Order');
                    if (ids == null || ids.isEmpty) return;
                    await _order('Add to Personal Order', (plan, s, now, uid) => orderAddTitles(plan, s, ids));
                    if (context.mounted) _toast(context, '${ids.length} title${ids.length == 1 ? '' : 's'} added to Order ✓');
                  },
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

  /// One block per category: its header (with Add, move, hide and any
  /// assigned Collections) and its rows, built only when shown.
  List<({String cid, int count, Widget Function() header, List<Widget Function()> rows})> _byCategory(
      AccountView view, Map<String, dynamic> p, List<String> titleIds, Map<String, LibraryTitle> byId, Map<String, dynamic> qv) {
    final hidden = asList(p['hiddenCategories']).map(jsStr).toSet();
    final out = <({String cid, int count, Widget Function() header, List<Widget Function()> rows})>[];
    // One pass to group the Order by category.
    final byCat = <String, List<String>>{};
    for (final id in titleIds) {
      (byCat[byId[id]!.categoryId] ??= []).add(id);
    }
    final mixed = qv['showCollectionsInRegularQueues'] == true;
    final cols = {for (final c in collectionsOf(view.state)) jsStr(c['id']): c};
    final assigned = <String, List<String>>{};
    for (final a in asList(p['collectionAssignments']).map(asMap).whereType<Map<String, dynamic>>()) {
      final c = cols[jsStr(a['collectionId'])];
      if (c != null) (assigned[jsStr(a['categoryId'])] ??= []).add(jsStr(c['title']));
    }
    for (final cid in orderCategoryDisplay(p, view.state)) {
      final cat = view.category(cid);
      final ids = byCat[cid] ?? const <String>[];
      final isHidden = hidden.contains(cid);
      final collections = mixed ? (assigned[cid] ?? const <String>[]) : const <String>[];
      Widget header() => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                CategoryBadge(cat, size: 24),
                const SizedBox(width: 8),
                Expanded(child: Text('${cat.name} · ${ids.length}', style: TextStyle(fontWeight: FontWeight.w900, color: MF.accent))),
                IconButton(
                  tooltip: 'Add ${cat.name} titles',
                  icon: const Icon(Icons.playlist_add_rounded, size: 18),
                  onPressed: () async {
                    final pick = await pickLibraryTitles(context, view,
                        exclude: {...titleIds, for (final t in view.library) if (t.categoryId != cid) t.id}, title: 'Add ${cat.name} titles');
                    if (pick == null || pick.isEmpty) return;
                    await _order('Add to Personal Order', (plan, s, now, uid) => orderAddTitles(plan, s, pick));
                  },
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
              if (collections.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final name in collections)
                    Chip(visualDensity: VisualDensity.compact, avatar: const Icon(Icons.collections_bookmark_rounded, size: 16), label: Text(name)),
                ]),
            ]),
          );
      final rows = <Widget Function()>[];
      if (!isHidden) {
        for (var i = 0; i < ids.length; i++) {
          final id = ids[i], index = i, count = ids.length;
          rows.add(() => _row(view, byId[id]!, index, count, cid));
        }
      }
      out.add((cid: cid, count: ids.length, header: header, rows: rows));
    }
    return out;
  }

  Widget _row(AccountView view, LibraryTitle t, int i, int count, String? categoryId, {int? dragIndex}) {
    final cat = view.category(t.categoryId);
    final compact = _titleView == 'compact';
    void move({int delta = 0, int? to}) =>
        _order('Reorder Personal Order', (plan, s, now, uid) => orderMoveTitle(plan, s, t.id, delta: delta, toPosition: to, categoryId: categoryId));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        if (dragIndex != null)
          ReorderableDragStartListener(index: dragIndex, child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.drag_indicator_rounded, color: MF.textDim))),
        SizedBox(width: 32, child: Text('${i + 1}', style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w800))),
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
