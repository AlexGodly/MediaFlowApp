// 10.0.0: choosing titles from your Library, with the Library's tools —
// search, categories (several at once), statuses, priorities, sort with
// Asc/Desc, five view styles, pages, Select visible / Select all matches /
// Deselect all, and "show only selected". Used everywhere you pick titles:
// Personal Order, Collections, Titles to keep offline, Discord's pinned title…

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/app_prefs.dart';
import '../logic/choice_layout.dart' show filterCategories, viewChoices;
import '../logic/library_index.dart';
import '../state/models.dart';
import 'presence.dart';
import 'theme.dart';
import 'title_screen.dart' show kStatusChoices, kPriorityChoices;
import 'widgets.dart';

const _sorts = [
  ('title', 'Title'),
  ('added', 'Date added'),
  ('edited', 'Last edited'),
  ('priority', 'Priority'),
  ('rating', 'Rating'),
  ('progress', 'Progress'),
  ('remaining', 'Remaining'),
  ('logging', 'Last logged'),
];

const _views = [
  ('list', 'List', Icons.view_list_rounded),
  ('compact', 'Compact', Icons.view_headline_rounded),
  ('cards', 'Cards', Icons.view_agenda_rounded),
  ('covers', 'Covers', Icons.grid_view_rounded),
  ('covers-title', 'Covers + title', Icons.view_module_rounded),
];

/// Lets the person choose titles. [exclude]: titles already added (hidden,
/// or shown greyed out with "Show titles already added"). [initial]: titles
/// already chosen (e.g. kept offline). Returns the chosen ids, or null.
Future<List<String>?> pickLibraryTitles(BuildContext context, AccountView view,
    {Set<String> exclude = const {},
    String title = 'Add titles',
    bool single = false,
    Set<String> initial = const {},
    String confirm = 'Add',
    bool allowEmpty = false,
    Set<String> categories = const {}}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    builder: (c) => PresenceScope(
      info: const PresenceInfo(situation: 'collections'),
      child: TitlePicker(
          view: view,
          exclude: exclude,
          title: title,
          single: single,
          initial: initial,
          confirm: confirm,
          allowEmpty: allowEmpty,
          categories: categories),
    ),
  );
}

class TitlePicker extends StatefulWidget {
  const TitlePicker(
      {super.key,
      required this.view,
      required this.exclude,
      required this.title,
      this.single = false,
      this.initial = const {},
      this.confirm = 'Add',
      this.allowEmpty = false,
      this.categories = const {}});
  final AccountView view;

  /// The category filter to start with (e.g. "Add Anime titles").
  final Set<String> categories;
  final Set<String> exclude, initial;
  final String title, confirm;
  final bool single, allowEmpty;

  @override
  State<TitlePicker> createState() => _TitlePickerState();
}

class _TitlePickerState extends State<TitlePicker> {
  static const _pageSize = 40;
  final _search = TextEditingController();
  late final Set<String> _picked = {...widget.initial};
  late Set<String> _cats = {...widget.categories};
  String _status = 'all', _priority = 'all', _query = '';
  bool _onlyPicked = false, _showAdded = false;
  int _page = 0;
  Timer? _timer;
  Int32List? _order;
  String _orderKey = '', _rowsKey = '';
  List<LibraryTitle> _rows = const [];
  late final LibraryIndex _index = LibraryIndex.of(widget.view.state);

  String get _sort => AppPrefs.instance.get<String>('pickerSort', 'title');
  String get _dir => AppPrefs.instance.get<String>('pickerDir', _sort == 'title' ? 'asc' : 'desc');
  String get _style => AppPrefs.instance.get<String>('pickerView', 'list');

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  void _loadOrder() {
    final key = '$_sort|$_dir';
    if (key == _orderKey && _order != null) return;
    _orderKey = key;
    _order = null;
    _index.libraryOrder(_sort, _dir, 0).then((o) {
      if (!mounted || _orderKey != key) return;
      setState(() => _order = o);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: _index.length >= kLibraryBackgroundThreshold ? 250 : 120), () {
      if (!mounted) return;
      setState(() {
        _query = text.trim().toLowerCase();
        _page = 0;
      });
    });
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _page = 0;
      });

  /// Every title the filters let through, in the chosen order.
  List<LibraryTitle> _filtered() {
    final order = _order;
    if (order == null) return const [];
    final key = '$_orderKey|${_cats.join(',')}|$_status|$_priority|$_query|$_onlyPicked|$_showAdded|${_onlyPicked ? _picked.length : 0}';
    if (key == _rowsKey) return _rows;
    final search = _query.isEmpty ? null : _index.titleSearch;
    final out = <LibraryTitle>[];
    for (final i in order) {
      final t = _index.titles[i];
      if (!_showAdded && widget.exclude.contains(t.id)) continue;
      if (_onlyPicked && !_picked.contains(t.id)) continue;
      if (_cats.isNotEmpty && !_cats.contains(t.categoryId)) continue;
      if (_status != 'all' && t.status != _status) continue;
      if (_priority != 'all' && (t.raw['priority'] ?? 'medium') != _priority) continue;
      if (search != null && !search[i].contains(_query)) continue;
      out.add(t);
    }
    _rowsKey = key;
    return _rows = out;
  }

  Future<void> _chooseCategories() async {
    final cats = filterCategories(widget.view, keep: _cats);
    final chosen = {..._cats};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Categories'),
          content: SizedBox(
            width: 380,
            child: ListView(shrinkWrap: true, children: [
              for (final c in cats)
                CheckboxListTile(
                  dense: true,
                  value: chosen.contains(c.id),
                  secondary: CategoryBadge(c, size: 26),
                  title: Text(c.name),
                  onChanged: (v) => set(() => v == true ? chosen.add(c.id) : chosen.remove(c.id)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => set(chosen.clear), child: const Text('All categories')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Done')),
          ],
        ),
      ),
    );
    if (ok == true) _set(() => _cats = chosen);
  }

  void _toggle(LibraryTitle t) {
    if (widget.exclude.contains(t.id)) return;
    if (widget.single) {
      Navigator.pop(context, [t.id]);
      return;
    }
    setState(() => _picked.contains(t.id) ? _picked.remove(t.id) : _picked.add(t.id));
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final rows = _filtered();
    final loading = _order == null;
    final pages = rows.isEmpty ? 1 : (rows.length + _pageSize - 1) ~/ _pageSize;
    if (_page >= pages) _page = pages - 1;
    final visible = rows.skip(_page * _pageSize).take(_pageSize).toList();
    final selectable = visible.where((t) => !widget.exclude.contains(t.id));
    final grid = _style == 'covers' || _style == 'covers-title';
    final changed = !(_picked.length == widget.initial.length && _picked.containsAll(widget.initial));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text('${widget.title}${widget.single ? '' : ' (${fmtNumber(_picked.length)})'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            if (!widget.single)
              FilledButton(
                onPressed: (_picked.isEmpty && !widget.allowEmpty) || (widget.allowEmpty && !changed)
                    ? null
                    : () => Navigator.pop(context, _picked.toList()),
                child: Text(widget.confirm),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            decoration: InputDecoration(
                isDense: true, hintText: 'Search ${fmtNumber(_index.length)} titles', prefixIcon: const Icon(Icons.search_rounded)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ActionChip(
              avatar: const Icon(Icons.category_outlined, size: 16),
              label: Text(_cats.isEmpty ? 'All categories' : '${_cats.length} categor${_cats.length == 1 ? 'y' : 'ies'}'),
              onPressed: _chooseCategories,
            ),
            CompactDropdown<String>(
              value: _status,
              items: [('all', 'All statuses'), ...viewChoices(view, 'statusFilter', kStatusChoices, keep: _status)],
              onChanged: (v) => _set(() => _status = v),
              maxWidth: 160,
            ),
            CompactDropdown<String>(
              value: _priority,
              items: [('all', 'All priorities'), ...viewChoices(view, 'priorityFilter', kPriorityChoices, keep: _priority)],
              onChanged: (v) => _set(() => _priority = v),
              maxWidth: 160,
            ),
            CompactDropdown<String>(
              value: _sort,
              items: _sorts,
              onChanged: (v) async {
                await AppPrefs.instance.set('pickerSort', v);
                _set(_loadOrder);
              },
              maxWidth: 160,
            ),
            IconButton(
              tooltip: _dir == 'asc' ? 'Ascending' : 'Descending',
              icon: Icon(_dir == 'asc' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 18),
              onPressed: () async {
                await AppPrefs.instance.set('pickerDir', _dir == 'asc' ? 'desc' : 'asc');
                _set(_loadOrder);
              },
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text(
                loading
                    ? 'Sorting…'
                    : '${fmtNumber(rows.length)} matches${pages > 1 ? ' · Page ${_page + 1}/${fmtNumber(pages)}' : ''}',
                style: TextStyle(color: MF.textDim, fontSize: 12),
              ),
            ),
            for (final v in _views)
              IconButton(
                tooltip: v.$2,
                visualDensity: VisualDensity.compact,
                color: _style == v.$1 ? MF.accent : MF.textDim,
                icon: Icon(v.$3, size: 20),
                onPressed: () => setState(() => AppPrefs.instance.set('pickerView', v.$1)),
              ),
          ]),
        ),
        if (!widget.single)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(spacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton(onPressed: () => setState(() => _picked.addAll(selectable.map((t) => t.id))), child: const Text('Select visible')),
              TextButton(
                onPressed: () => setState(() => _picked.addAll(rows.where((t) => !widget.exclude.contains(t.id)).map((t) => t.id))),
                child: Text('Select all ${fmtNumber(rows.where((t) => !widget.exclude.contains(t.id)).length)} matches'),
              ),
              TextButton(onPressed: _picked.isEmpty ? null : () => setState(_picked.clear), child: const Text('Deselect all')),
              FilterChip(
                label: const Text('Only selected'),
                selected: _onlyPicked,
                onSelected: (v) => _set(() => _onlyPicked = v),
              ),
              if (widget.exclude.isNotEmpty) ...[
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Show titles already added'),
                  selected: _showAdded,
                  onSelected: (v) => _set(() => _showAdded = v),
                ),
              ],
            ]),
          ),
        const Divider(height: 8),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(child: Text('No titles match.', style: TextStyle(color: MF.textDim)))
                  : grid
                      ? GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 130, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: _style == 'covers' ? .68 : .55),
                          itemCount: visible.length,
                          itemBuilder: (context, i) => _tile(visible[i]),
                        )
                      : ListView.builder(itemCount: visible.length, itemBuilder: (context, i) => _row(visible[i])),
        ),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: _page == 0 ? null : () => setState(() => _page = 0), icon: const Icon(Icons.first_page_rounded)),
              IconButton(onPressed: _page == 0 ? null : () => setState(() => _page--), icon: const Icon(Icons.chevron_left_rounded)),
              Text('Page ${_page + 1} of ${fmtNumber(pages)}'),
              IconButton(onPressed: _page >= pages - 1 ? null : () => setState(() => _page++), icon: const Icon(Icons.chevron_right_rounded)),
              IconButton(
                  onPressed: _page >= pages - 1 ? null : () => setState(() => _page = pages - 1), icon: const Icon(Icons.last_page_rounded)),
            ]),
          ),
      ]),
    );
  }

  Widget _row(LibraryTitle t) {
    final cat = widget.view.category(t.categoryId);
    final added = widget.exclude.contains(t.id);
    final on = _picked.contains(t.id);
    final compact = _style == 'compact';
    final sub = '${cat.name} · ${statusLabel(t.status)}${added ? ' · already added' : ''}';
    return Opacity(
      opacity: added ? .45 : 1,
      child: ListTile(
        key: ValueKey(t.id),
        dense: compact,
        enabled: !added,
        leading: compact ? null : Cover(title: t, category: cat, width: _style == 'cards' ? 44 : 32),
        title: Text(t.title, maxLines: _style == 'cards' ? 2 : 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_style == 'cards' ? '$sub · ${progressText(t, cat)}' : sub, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: widget.single || added ? null : Checkbox(value: on, onChanged: (_) => _toggle(t)),
        onTap: () => _toggle(t),
      ),
    );
  }

  Widget _tile(LibraryTitle t) {
    final cat = widget.view.category(t.categoryId);
    final added = widget.exclude.contains(t.id);
    final on = _picked.contains(t.id);
    return Opacity(
      opacity: added ? .45 : 1,
      child: InkWell(
        key: ValueKey(t.id),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggle(t),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              LayoutBuilder(builder: (context, c) => Cover(title: t, category: cat, width: c.maxWidth)),
              if (!widget.single && !added)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    decoration: BoxDecoration(color: on ? MF.accent : Colors.black54, borderRadius: BorderRadius.circular(99)),
                    padding: const EdgeInsets.all(3),
                    child: Icon(on ? Icons.check_rounded : Icons.add_rounded, size: 16, color: Colors.white),
                  ),
                ),
            ]),
          ),
          if (_style == 'covers-title')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }
}
