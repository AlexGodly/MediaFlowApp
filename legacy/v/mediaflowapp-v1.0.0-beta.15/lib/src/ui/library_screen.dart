// The Library: search, category / status / priority filters, the website's
// eleven sorts with direction, List / Compact / Cards / Covers views, paging,
// select + batch actions (status, priority, Move to…, Fix completed progress,
// delete), Add title, Title Details, Rate Your Library and Missing Covers.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../logic/library_logic.dart';
import '../logic/log_arrange.dart' show lastTouchedIndex, remainingUnits, compareTitlesNatural, seedHash;
import '../state/models.dart';
import '../util/js.dart';
import 'theme.dart';
import 'title_screen.dart';
import 'widgets.dart';

const _sorts = [
  ('edited', 'Last edited'),
  ('added', 'Date added'),
  ('title', 'Title'),
  ('priority', 'Priority'),
  ('rating', 'Rating'),
  ('progress', 'Progress'),
  ('total', 'Total'),
  ('remaining', 'Remaining'),
  ('logging', 'Last logged'),
  ('seen', 'Last seen'),
  ('random', 'Random'),
];

const _views = [
  ('list', 'List', Icons.view_list_rounded),
  ('compact', 'Compact', Icons.view_headline_rounded),
  ('cards', 'Cards', Icons.view_agenda_rounded),
  ('covers', 'Covers', Icons.grid_view_rounded),
];

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _search = TextEditingController();
  final Set<String> _cats = {};
  final Set<String> _selected = {};
  String _status = 'all', _priority = 'all';
  int _page = 0;
  final int _seed = DateTime.now().millisecondsSinceEpoch % 100000 + 1;

  AccountController get account => widget.account;
  AppPrefs get prefs => AppPrefs.instance;
  String get _sort => prefs.get<String>('librarySort', 'edited');
  String get _dir => prefs.get<String>('librarySortDir', 'desc');
  String get _view => prefs.get<String>('libraryView', 'list');
  int get _pageSize => prefs.get<int>('libraryPageSize', 50);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// `v189CompareLibraryItems`, then the filters. The sorted Library is kept
  /// per account version, so typing in search only filters.
  List<LibraryTitle> _filtered(AccountView view) {
    final q = _search.text.trim().toLowerCase();
    final sorted = memoFor(view, 'library|$_sort|$_dir|$_seed', () => _sorted(view));
    return sorted.where((t) {
      if (_status != 'all' && t.status != _status) return false;
      if (_priority != 'all' && (jsStr(t.raw['priority']).isEmpty ? 'medium' : jsStr(t.raw['priority'])) != _priority) return false;
      if (_cats.isNotEmpty && !_cats.contains(t.categoryId)) return false;
      if (q.isNotEmpty) {
        final tags = asList(t.raw['tags']).map(jsStr).join(' ');
        if (!'${t.title} $tags'.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();
  }

  List<LibraryTitle> _sorted(AccountView view) {
    final rows = List<LibraryTitle>.of(view.library);
    final sort = _sort, asc = _dir == 'asc';
    final touched = sort == 'logging' ? lastTouchedIndex(view.state) : const <String, double>{};
    double n(Object? v) => jsNumOrNull(v) ?? 0;
    int titleCmp(LibraryTitle a, LibraryTitle b) => compareTitlesNatural(a.title, b.title);
    const rank = {'low': 0, 'medium': 1, 'high': 2};
    int r(LibraryTitle t) => rank[jsStr(t.raw['priority']).isEmpty ? 'medium' : jsStr(t.raw['priority'])] ?? 1;
    double touch(LibraryTitle t) => touched[t.id] ?? 0;
    rows.sort((a, b) {
      if (sort == 'remaining') {
        final av = remainingUnits(a.raw), bv = remainingUnits(b.raw);
        if (av == null && bv != null) return 1;
        if (av != null && bv == null) return -1;
        if (av == null && bv == null) return titleCmp(a, b);
        final d = (av! - bv!) * (asc ? 1 : -1);
        return d != 0 ? d.sign.toInt() : titleCmp(a, b);
      }
      if (sort == 'title') return asc ? titleCmp(a, b) : -titleCmp(a, b);
      double d;
      switch (sort) {
        case 'priority':
          d = (r(a) - r(b)).toDouble();
        case 'rating':
          d = n(a.raw['rating']) - n(b.raw['rating']);
        case 'progress':
          d = n(a.raw['progress']) - n(b.raw['progress']);
        case 'total':
          d = n(a.raw['total']) - n(b.raw['total']);
        case 'logging':
          d = touch(a) - touch(b);
        case 'seen':
          d = n(a.raw['lastSeenAt']) - n(b.raw['lastSeenAt']);
        case 'added':
          d = n(a.raw['createdAt']) - n(b.raw['createdAt']);
        case 'random':
          d = (seedHash(a.id, _seed) - seedHash(b.id, _seed)).toDouble();
        default:
          d = n(jsTruthy(a.raw['modifiedAt']) ? a.raw['modifiedAt'] : a.raw['createdAt']) -
              n(jsTruthy(b.raw['modifiedAt']) ? b.raw['modifiedAt'] : b.raw['createdAt']);
      }
      if (sort != 'random' && !asc) d = -d;
      return d != 0 ? d.sign.toInt() : titleCmp(a, b);
    });
    return rows;
  }

  Future<void> _pickCategories(AccountView view) async {
    final chosen = {..._cats};
    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: MF.surface,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                title: const Text('Categories', style: TextStyle(fontWeight: FontWeight.w800)),
                trailing: TextButton(onPressed: () => set(chosen.clear), child: const Text('All')),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final cat in view.categories)
                    CheckboxListTile(
                      value: chosen.contains(cat.id),
                      onChanged: (v) => set(() => v == true ? chosen.add(cat.id) : chosen.remove(cat.id)),
                      secondary: CategoryBadge(cat, size: 26),
                      title: Text(cat.name),
                      subtitle: Text('${view.library.where((t) => t.categoryId == cat.id).length} titles'),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: () => Navigator.pop(c, chosen),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: const Text('Done'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (res != null) {
      setState(() {
        _cats
          ..clear()
          ..addAll(res);
        _page = 0;
      });
    }
  }

  Future<bool> _confirm(String title, String body, String yes, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: MF.bad) : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _batch(String kind, String value, {String label = ''}) async {
    final ids = {..._selected};
    final n = ids.length;
    if (n == 0) return;
    final what = switch (kind) {
      'status' => 'Change $n ${n == 1 ? 'title' : 'titles'} to $label?',
      'priority' => 'Change the priority of $n ${n == 1 ? 'title' : 'titles'} to $label?',
      'category' => 'Move $n ${n == 1 ? 'title' : 'titles'} to $label?',
      _ => 'Delete $n ${n == 1 ? 'title' : 'titles'}?',
    };
    final ok = await _confirm(
      what,
      kind == 'delete'
          ? 'The titles are removed from your Library. History logs stay. You can restore them from Library History or with Undo.'
          : 'This applies to every selected title and can be undone.',
      kind == 'delete' ? 'Delete $n' : 'Apply',
      danger: kind == 'delete',
    );
    if (!ok) return;
    var changed = 0;
    await account.edit((s, now) {
      var k = 0;
      String uid() => mediaFlowUid(now + k++);
      changed = kind == 'delete' ? deleteTitles(s, ids, now, uid) : batchEdit(s, ids, kind, value, now, uid, categoryName: label);
    }, label: kind == 'delete' ? 'Batch delete' : 'Batch $kind');
    setState(_selected.clear);
    if (!mounted) return;
    _toast(context, switch (kind) {
      'status' => '$changed ${changed == 1 ? 'title' : 'titles'} changed to $label ✓',
      'priority' => '$changed ${changed == 1 ? 'title' : 'titles'} priority changed to $label ✓',
      'category' => '$changed ${changed == 1 ? 'title' : 'titles'} moved to $label ✓',
      _ => '$changed ${changed == 1 ? 'title' : 'titles'} deleted',
    });
  }

  Future<void> _repair({required bool selectedOnly}) async {
    var n = 0;
    await account.edit((s, now) {
      var k = 0;
      n = repairCompleted(s, selectedOnly ? {..._selected} : null, now, () => mediaFlowUid(now + k++));
    }, label: 'Fix completed progress');
    if (!mounted) return;
    _toast(
        context,
        n == 0
            ? (selectedOnly ? 'No selected completed titles needed repair.' : 'All completed titles with known totals are already correct.')
            : '$n ${selectedOnly ? 'selected ' : 'completed '}title${n == 1 ? '' : 's'} repaired ✓');
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: Listenable.merge([account, prefs]),
      builder: (context, _) {
        final view = account.view;
        if (view == null) return const SizedBox.shrink();
        final titles = _filtered(view);
        final size = _pageSize;
        final pages = math.max(1, (titles.length / size).ceil());
        if (_page > pages - 1) _page = pages - 1;
        final pageItems = titles.skip(_page * size).take(size).toList();
        final unrated = view.library.where((t) => !(t.rating != null && t.rating! > 0)).length;
        final noCover = view.library.where((t) => t.coverUrl.isEmpty).length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Library'),
            actions: [
              IconButton(
                tooltip: 'Rate Your Library ($unrated unrated)',
                icon: Badge(isLabelVisible: unrated > 0, label: Text('$unrated'), child: const Icon(Icons.star_outline_rounded)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RateLibraryScreen(account: account))),
              ),
              IconButton(
                tooltip: 'Missing Covers ($noCover)',
                icon: Badge(isLabelVisible: noCover > 0, label: Text('$noCover'), child: const Icon(Icons.image_not_supported_outlined)),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MissingCoversScreen(account: account))),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'repairAll') _repair(selectedOnly: false);
                  if (v == 'undo') {
                    final l = await account.undo();
                    if (l != null && context.mounted) _toast(context, 'Undid $l');
                  }
                  if (v == 'redo') {
                    final l = await account.redo();
                    if (l != null && context.mounted) _toast(context, 'Redid $l');
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'undo', enabled: account.undoStack.isNotEmpty, child: const Text('Undo')),
                  PopupMenuItem(value: 'redo', enabled: account.redoStack.isNotEmpty, child: const Text('Redo')),
                  const PopupMenuItem(value: 'repairAll', child: Text('Fix all completed progress')),
                ],
              ),
              SyncIndicator(account: account),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TitleEditor(account: account, initialCategory: _cats.length == 1 ? _cats.first : null))),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add title'),
          ),
          body: RefreshIndicator(
            onRefresh: account.sync,
            child: CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                sliver: SliverList.list(children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() => _page = 0),
                    decoration: InputDecoration(
                      hintText: 'Search ${fmtNumber(view.library.length)} titles',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close_rounded), onPressed: () => setState(_search.clear)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    ActionChip(
                      avatar: const Icon(Icons.category_outlined, size: 16),
                      label: Text(_cats.isEmpty ? 'All categories' : '${_cats.length} categories'),
                      onPressed: () => _pickCategories(view),
                    ),
                    CompactDropdown<String>(
                      value: _status,
                      items: [('all', 'All statuses'), ...kStatusChoices],
                      onChanged: (v) => setState(() {
                        _status = v;
                        _page = 0;
                      }),
                      maxWidth: 170,
                    ),
                    CompactDropdown<String>(
                      value: _priority,
                      items: [('all', 'All priorities'), ...kPriorityChoices],
                      onChanged: (v) => setState(() {
                        _priority = v;
                        _page = 0;
                      }),
                      maxWidth: 170,
                    ),
                    CompactDropdown<String>(value: _sort, items: _sorts, onChanged: (v) => prefs.set('librarySort', v), maxWidth: 170),
                    if (_sort != 'random')
                      ActionChip(
                        avatar: Icon(_dir == 'asc' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16),
                        label: Text(_dir == 'asc' ? 'Asc' : 'Desc'),
                        onPressed: () => prefs.set('librarySortDir', _dir == 'asc' ? 'desc' : 'asc'),
                      ),
                    if (_cats.isNotEmpty || _status != 'all' || _priority != 'all')
                      TextButton(
                        onPressed: () => setState(() {
                          _cats.clear();
                          _status = 'all';
                          _priority = 'all';
                          _page = 0;
                        }),
                        child: const Text('Clear filters'),
                      ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: Text('${fmtNumber(titles.length)} title${titles.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: MF.textDim, fontSize: 12)),
                    ),
                    for (final v in _views)
                      IconButton(
                        tooltip: v.$2,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(v.$3, size: 20, color: _view == v.$1 ? MF.accent : MF.textDim),
                        onPressed: () => prefs.set('libraryView', v.$1),
                      ),
                  ]),
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    TextButton(
                      onPressed: pageItems.isEmpty ? null : () => setState(() => _selected.addAll(pageItems.map((t) => t.id))),
                      child: const Text('Select visible'),
                    ),
                    if (_selected.isNotEmpty) ...[
                      TextButton(onPressed: () => setState(_selected.clear), child: Text('Deselect (${_selected.length})')),
                      CompactDropdown<String>(
                        value: '',
                        items: [('', 'Status…'), ...kStatusChoices],
                        onChanged: (v) {
                          if (v.isNotEmpty) _batch('status', v, label: kStatusChoices.firstWhere((s) => s.$1 == v).$2);
                        },
                        maxWidth: 150,
                      ),
                      CompactDropdown<String>(
                        value: '',
                        items: [('', 'Priority…'), ...kPriorityChoices],
                        onChanged: (v) {
                          if (v.isNotEmpty) _batch('priority', v, label: kPriorityChoices.firstWhere((s) => s.$1 == v).$2);
                        },
                        maxWidth: 150,
                      ),
                      CompactDropdown<String>(
                        value: '',
                        items: [('', 'Move to…'), for (final c in view.categories) (c.id, c.name)],
                        onChanged: (v) {
                          if (v.isNotEmpty) _batch('category', v, label: view.category(v).name);
                        },
                        maxWidth: 170,
                      ),
                      TextButton(onPressed: () => _repair(selectedOnly: true), child: const Text('Fix completed progress')),
                      TextButton(onPressed: () => _batch('delete', ''), child: const Text('Delete selected', style: TextStyle(color: MF.bad))),
                    ],
                  ]),
                ]),
              ),
              if (titles.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.video_library_outlined,
                    title: view.library.isEmpty ? 'Your Library is empty' : 'No matching titles',
                    body: view.library.isEmpty ? 'Tap Add title to start your Library.' : 'Try a different search or filter.',
                  ),
                )
              else if (_view == 'covers')
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.52),
                    itemCount: pageItems.length,
                    itemBuilder: (context, i) => _CoverTile(
                      title: pageItems[i],
                      category: view.category(pageItems[i].categoryId),
                      selected: _selected.contains(pageItems[i].id),
                      onTap: () => _selected.isNotEmpty ? setState(() => _toggle(pageItems[i].id)) : openTitle(context, account, pageItems[i].id),
                      onLongPress: () => setState(() => _toggle(pageItems[i].id)),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList.builder(
                    itemCount: pageItems.length,
                    itemBuilder: (context, i) => _TitleRow(
                      title: pageItems[i],
                      category: view.category(pageItems[i].categoryId),
                      layout: _view,
                      selected: _selected.contains(pageItems[i].id),
                      onSelect: () => setState(() => _toggle(pageItems[i].id)),
                      onTap: () => openTitle(context, account, pageItems[i].id),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                    if (pages > 1) ...[
                      IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: _page == 0 ? null : () => setState(() => _page--)),
                      Text('Page ${_page + 1} of $pages'),
                      IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: _page >= pages - 1 ? null : () => setState(() => _page++)),
                    ],
                    CompactDropdown<int>(
                      value: size,
                      items: const [(25, '25 per page'), (50, '50 per page'), (100, '100 per page'), (250, '250 per page'), (1000, '1000 per page')],
                      onChanged: (v) {
                        prefs.set('libraryPageSize', v);
                        setState(() => _page = 0);
                      },
                      maxWidth: 160,
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _toggle(String id) => _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title, required this.category, required this.layout, required this.selected, required this.onSelect, required this.onTap});
  final LibraryTitle title;
  final Category category;
  final String layout;
  final bool selected;
  final VoidCallback onSelect, onTap;

  @override
  Widget build(BuildContext context) {
    final total = title.total;
    final pct = total == null || total == 0 ? null : (title.progress / total).clamp(0, 1).toDouble();
    final rating = title.rating != null && title.rating! > 0 ? ' · ★ ${fmtNumber(title.rating!)}' : '';
    final check = Checkbox(value: selected, onChanged: (_) => onSelect(), visualDensity: VisualDensity.compact);
    if (layout == 'compact') {
      return InkWell(
        onTap: onTap,
        onLongPress: onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            check,
            Expanded(child: Text(title.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(progressText(title, category), style: const TextStyle(color: MF.textDim, fontSize: 12)),
            const SizedBox(width: 8),
          ]),
        ),
      );
    }
    final cover = Cover(title: title, category: category, width: layout == 'cards' ? 64 : 44);
    final body = Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('${category.name} · ${progressText(title, category)}$rating', maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: MF.textDim, fontSize: 12.5)),
        Text(statusLabel(title.status), style: TextStyle(color: statusColor(title.status), fontSize: 12, fontWeight: FontWeight.w700)),
        if (layout == 'cards' && pct != null) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: pct, minHeight: 4, borderRadius: BorderRadius.circular(4)),
        ],
      ]),
    );
    final row = InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(children: [check, cover, const SizedBox(width: 12), body]),
      ),
    );
    return layout == 'cards' ? Card(margin: const EdgeInsets.only(bottom: 8), child: row) : row;
  }
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.title, required this.category, required this.selected, required this.onTap, required this.onLongPress});
  final LibraryTitle title;
  final Category category;
  final bool selected;
  final VoidCallback onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: LayoutBuilder(
        builder: (context, c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Cover(title: title, category: category, width: c.maxWidth),
            if (selected) const Positioned(right: 4, top: 4, child: Icon(Icons.check_circle_rounded, color: MF.accent)),
          ]),
          const SizedBox(height: 4),
          Text(title.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

// ---- Rate Your Library ---------------------------------------------------------------

class RateLibraryScreen extends StatefulWidget {
  const RateLibraryScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<RateLibraryScreen> createState() => _RateLibraryScreenState();
}

class _RateLibraryScreenState extends State<RateLibraryScreen> {
  double _value = 7;

  List<String> get _skipped => AppPrefs.instance.get<List>('ratingSkipped', const []).map((e) => '$e').toList();

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return LiveBuilder(
      listenable: Listenable.merge([account, AppPrefs.instance]),
      builder: (context, _) {
        final view = account.view;
        if (view == null) return const SizedBox.shrink();
        final skipped = _skipped.toSet();
        final queue = view.library.where((t) => !(t.rating != null && t.rating! > 0)).toList()
          ..sort((a, b) {
            final s = (skipped.contains(a.id) ? 1 : 0) - (skipped.contains(b.id) ? 1 : 0);
            if (s != 0) return s;
            final c = (b.status == 'completed' ? 1 : 0) - (a.status == 'completed' ? 1 : 0);
            return c != 0 ? c : b.modifiedAt.compareTo(a.modifiedAt);
          });
        final t = queue.firstOrNull;
        return Scaffold(
          appBar: AppBar(title: const Text('Rate Your Library')),
          body: t == null
              ? const EmptyState(icon: Icons.star_rounded, title: 'Everything is rated', body: 'Every Library title has a rating.')
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ListView(padding: const EdgeInsets.all(24), children: [
                      Text('${queue.length} unrated title${queue.length == 1 ? '' : 's'}', textAlign: TextAlign.center, style: const TextStyle(color: MF.textDim)),
                      const SizedBox(height: 16),
                      Center(child: Cover(title: t, category: view.category(t.categoryId), width: 150)),
                      const SizedBox(height: 12),
                      Text(t.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      Text('${view.category(t.categoryId).name} · ${statusLabel(t.status)}', textAlign: TextAlign.center, style: const TextStyle(color: MF.textDim)),
                      const SizedBox(height: 16),
                      Text('${_value.toStringAsFixed(1)} / 10', textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                      Slider(value: _value, min: 0.1, max: 10, divisions: 99, onChanged: (v) => setState(() => _value = (v * 10).round() / 10)),
                      const SizedBox(height: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                        onPressed: () async {
                          var xp = 0.0;
                          final r = _value;
                          await account.edit((s, now) {
                            var k = 0;
                            xp = rateTitle(s, t.id, r, now, () => mediaFlowUid(now + k++));
                          }, label: 'Rate title');
                          if (context.mounted) _toast(context, 'Rated ${t.title} ${fmtNumber(r)}/10${xp > 0 ? ' · +${fmtNumber(xp)} XP' : ''} ✓');
                        },
                        child: const Text('Rate'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () => AppPrefs.instance.set('ratingSkipped', [...skipped.where((x) => x != t.id), t.id]),
                        child: const Text('Skip for now'),
                      ),
                    ]),
                  ),
                ),
        );
      },
    );
  }
}

// ---- Missing Covers ---------------------------------------------------------------------

class MissingCoversScreen extends StatelessWidget {
  const MissingCoversScreen({super.key, required this.account});
  final AccountController account;

  Future<void> _set(BuildContext context, LibraryTitle t, String url, {bool auto = false}) async {
    var xp = 0.0;
    await account.edit((s, now) {
      var k = 0;
      xp = setCover(s, t.id, url, now, () => mediaFlowUid(now + k++), auto: auto);
    }, label: 'Cover');
    if (context.mounted) _toast(context, 'Cover saved for ${t.title}${xp > 0 ? ' · +${fmtNumber(xp)} XP' : ''}');
  }

  Future<void> _paste(BuildContext context, LibraryTitle t) async {
    final c = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Cover for ${t.title}'),
        content: TextField(controller: c, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Image URL')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (url != null && url.isNotEmpty && context.mounted) await _set(context, t, url);
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: account,
      builder: (context, _) {
        final view = account.view;
        if (view == null) return const SizedBox.shrink();
        final missing = view.library.where((t) => t.coverUrl.isEmpty).toList()..sort((a, b) => compareTitlesNatural(a.title, b.title));
        return Scaffold(
          appBar: AppBar(title: Text('Missing Covers (${missing.length})')),
          body: missing.isEmpty
              ? const EmptyState(icon: Icons.image_rounded, title: 'Every title has a cover', body: 'Nice and tidy.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  itemCount: missing.length,
                  itemBuilder: (context, i) {
                    final t = missing[i];
                    final cat = view.category(t.categoryId);
                    return ListTile(
                      leading: Cover(title: t, category: cat, width: 40),
                      title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(cat.name),
                      trailing: Wrap(spacing: 4, children: [
                        IconButton(
                          tooltip: 'Search online',
                          icon: const Icon(Icons.travel_explore_rounded),
                          onPressed: () async {
                            final r = await searchOnline(context, t.title, cat);
                            if (r != null && r.coverUrl.isNotEmpty && context.mounted) await _set(context, t, r.coverUrl, auto: true);
                          },
                        ),
                        IconButton(tooltip: 'Paste a URL', icon: const Icon(Icons.link_rounded), onPressed: () => _paste(context, t)),
                      ]),
                    );
                  },
                ),
        );
      },
    );
  }
}
