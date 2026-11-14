// 10.0.0: choosing Collections (Personal Order → Add collection), with the
// Collections page's tools: search (names and the titles inside), the
// categories of their titles, "in a queue / not yet", sort with Asc/Desc,
// List / Cards / Covers, pages, Select visible / all matches / Deselect all.

import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/choice_layout.dart' show filterCategories, setCategories;
import '../logic/collections_logic.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'collections_screen.dart' show CollectionCover;
import 'presence.dart';
import 'theme.dart';
import 'widgets.dart';

/// The chosen Collections and the task category to put them in, or null.
Future<({List<String> ids, String categoryId})?> pickCollections(BuildContext context, AccountView view,
    {String? categoryId, String title = 'Add a Collection'}) {
  return showModalBottomSheet<({List<String> ids, String categoryId})>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    builder: (c) => PresenceScope(
      info: const PresenceInfo(situation: 'order'),
      child: _CollectionPicker(view: view, categoryId: categoryId, title: title),
    ),
  );
}

class _CollectionPicker extends StatefulWidget {
  const _CollectionPicker({required this.view, required this.categoryId, required this.title});
  final AccountView view;
  final String? categoryId;
  final String title;

  @override
  State<_CollectionPicker> createState() => _CollectionPickerState();
}

class _CollectionPickerState extends State<_CollectionPicker> {
  static const _pageSize = 20;
  final _search = TextEditingController();
  final Set<String> _picked = {};
  Set<String> _cats = {};
  String _queued = 'any', _sort = 'title', _dir = 'asc', _style = 'list', _query = '';
  int _page = 0;
  Timer? _timer;
  late String? _target = widget.categoryId ??
      (setCategories(widget.view).isEmpty ? null : setCategories(widget.view).first.id);

  late final List<Map<String, dynamic>> _all = collectionsOf(widget.view.state);
  late final Map<String, LibraryTitle> _byId = {for (final t in widget.view.library) t.id: t};

  /// Collections already in a queue, by task category.
  late final Map<String, Set<String>> _assigned = () {
    final out = <String, Set<String>>{};
    final p = asMap(widget.view.state['orderPlan']) ?? const <String, dynamic>{};
    for (final a in asList(p['collectionAssignments']).map(asMap).whereType<Map<String, dynamic>>()) {
      (out[jsStr(a['collectionId'])] ??= {}).add(jsStr(a['categoryId']));
    }
    return out;
  }();

  late final Map<String, String> _searchText = {
    for (final c in _all)
      jsStr(c['id']): [
        cleanTitle(c['title']),
        for (final id in collectionTitleIds(c)) _byId[id]?.title ?? '',
      ].join('\n').toLowerCase(),
  };

  late final Map<String, Set<String>> _catsOf = {
    for (final c in _all) jsStr(c['id']): {for (final id in collectionTitleIds(c)) if (_byId[id] != null) _byId[id]!.categoryId},
  };

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _page = 0;
      });

  bool _inQueue(String id) => (_assigned[id] ?? const {}).isNotEmpty;
  bool _inTarget(String id) => _target != null && (_assigned[id] ?? const {}).contains(_target);

  List<Map<String, dynamic>> _rows() {
    final out = [
      for (final c in _all)
        if ((_query.isEmpty || _searchText[jsStr(c['id'])]!.contains(_query)) &&
            (_cats.isEmpty || _catsOf[jsStr(c['id'])]!.any(_cats.contains)) &&
            (_queued == 'any' || (_queued == 'queued') == _inQueue(jsStr(c['id']))))
          c,
    ];
    int key(Map<String, dynamic> a, Map<String, dynamic> b) => switch (_sort) {
          'titles' => collectionTitleIds(a).length.compareTo(collectionTitleIds(b).length),
          'created' => jsNum(a['createdAt']).compareTo(jsNum(b['createdAt'])),
          'edited' => jsNum(a['updatedAt']).compareTo(jsNum(b['updatedAt'])),
          _ => cleanTitle(a['title']).toLowerCase().compareTo(cleanTitle(b['title']).toLowerCase()),
        };
    out.sort((a, b) => _dir == 'asc' ? key(a, b) : key(b, a));
    return out;
  }

  Future<void> _chooseCategories() async {
    final chosen = {..._cats};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Categories of their titles'),
          content: SizedBox(
            width: 380,
            child: ListView(shrinkWrap: true, children: [
              for (final c in filterCategories(widget.view, keep: _cats))
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

  void _toggle(String id) {
    if (_inTarget(id)) return;
    setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id));
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final rows = _rows();
    final pages = rows.isEmpty ? 1 : (rows.length + _pageSize - 1) ~/ _pageSize;
    if (_page >= pages) _page = pages - 1;
    final visible = rows.skip(_page * _pageSize).take(_pageSize).toList();
    final target = _target == null ? null : view.category(_target!);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text('${widget.categoryId == null || target == null ? widget.title : 'Add a Collection to ${target.name}'} (${_picked.length})',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: _picked.isEmpty || _target == null
                  ? null
                  : () => Navigator.pop(context, (ids: _picked.toList(), categoryId: _target!)),
              child: const Text('Add'),
            ),
          ]),
        ),
        if (widget.categoryId == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              const Text('Task category', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: CompactDropdown<String>(
                  value: _target ?? '',
                  items: [for (final c in setCategories(view, keep: [if (_target != null) _target!])) (c.id, c.name)],
                  onChanged: (v) => setState(() {
                    _target = v;
                    _picked.removeWhere(_inTarget);
                  }),
                ),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: TextField(
            controller: _search,
            onChanged: (t) {
              _timer?.cancel();
              _timer = Timer(const Duration(milliseconds: 150), () {
                if (mounted) _set(() => _query = t.trim().toLowerCase());
              });
            },
            decoration: const InputDecoration(
                isDense: true, hintText: 'Search Collections and the titles in them', prefixIcon: Icon(Icons.search_rounded)),
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
              value: _queued,
              items: const [('any', 'In a queue or not'), ('queued', 'In a queue'), ('free', 'Not in a queue yet')],
              onChanged: (v) => _set(() => _queued = v),
              maxWidth: 190,
            ),
            CompactDropdown<String>(
              value: _sort,
              items: const [('title', 'Name'), ('titles', 'Number of titles'), ('created', 'Date created'), ('edited', 'Last edited')],
              onChanged: (v) => _set(() => _sort = v),
              maxWidth: 170,
            ),
            IconButton(
              tooltip: _dir == 'asc' ? 'Ascending' : 'Descending',
              icon: Icon(_dir == 'asc' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 18),
              onPressed: () => _set(() => _dir = _dir == 'asc' ? 'desc' : 'asc'),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text('${fmtNumber(rows.length)} collection${rows.length == 1 ? '' : 's'}${pages > 1 ? ' · Page ${_page + 1}/$pages' : ''}',
                  style: TextStyle(color: MF.textDim, fontSize: 12)),
            ),
            for (final v in const [('list', 'List', Icons.view_list_rounded), ('cards', 'Cards', Icons.view_agenda_rounded), ('covers', 'Covers', Icons.grid_view_rounded)])
              IconButton(
                tooltip: v.$2,
                visualDensity: VisualDensity.compact,
                color: _style == v.$1 ? MF.accent : MF.textDim,
                icon: Icon(v.$3, size: 20),
                onPressed: () => setState(() => _style = v.$1),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(children: [
            TextButton(
              onPressed: () => setState(() => _picked.addAll(visible.map((c) => jsStr(c['id'])).where((id) => !_inTarget(id)))),
              child: const Text('Select visible'),
            ),
            TextButton(
              onPressed: () => setState(() => _picked.addAll(rows.map((c) => jsStr(c['id'])).where((id) => !_inTarget(id)))),
              child: Text('Select all ${fmtNumber(rows.length)} matches'),
            ),
            TextButton(onPressed: _picked.isEmpty ? null : () => setState(_picked.clear), child: const Text('Deselect all')),
          ]),
        ),
        const Divider(height: 8),
        Expanded(
          child: _all.isEmpty
              ? Center(child: Text('You have no Collections yet. Create one in Collections first.', style: TextStyle(color: MF.textDim)))
              : rows.isEmpty
                  ? Center(child: Text('No Collections match.', style: TextStyle(color: MF.textDim)))
                  : _style == 'covers'
                      ? GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 140, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .62),
                          itemCount: visible.length,
                          itemBuilder: (context, i) => _tile(visible[i]),
                        )
                      : ListView.builder(itemCount: visible.length, itemBuilder: (context, i) => _row(visible[i])),
        ),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: _page == 0 ? null : () => setState(() => _page--), icon: const Icon(Icons.chevron_left_rounded)),
              Text('Page ${_page + 1} of $pages'),
              IconButton(onPressed: _page >= pages - 1 ? null : () => setState(() => _page++), icon: const Icon(Icons.chevron_right_rounded)),
            ]),
          ),
      ]),
    );
  }

  String _meta(Map<String, dynamic> c) {
    final id = jsStr(c['id']);
    final n = collectionTitleIds(c).length;
    final queues = [for (final cid in _assigned[id] ?? const <String>{}) widget.view.category(cid).name];
    return [
      '$n title${n == 1 ? '' : 's'}',
      if (_inTarget(id)) 'already in this queue' else if (queues.isNotEmpty) 'in ${queues.join(', ')}',
    ].join(' · ');
  }

  Widget _row(Map<String, dynamic> c) {
    final id = jsStr(c['id']);
    final done = _inTarget(id);
    return Opacity(
      opacity: done ? .45 : 1,
      child: ListTile(
        key: ValueKey(id),
        enabled: !done,
        leading: CollectionCover(view: widget.view, collection: c, size: _style == 'cards' ? 52 : 36),
        title: Text(cleanTitle(c['title']), maxLines: _style == 'cards' ? 2 : 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_meta(c), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: done ? null : Checkbox(value: _picked.contains(id), onChanged: (_) => _toggle(id)),
        onTap: () => _toggle(id),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final id = jsStr(c['id']);
    final done = _inTarget(id), on = _picked.contains(id);
    return Opacity(
      opacity: done ? .45 : 1,
      child: InkWell(
        onTap: () => _toggle(id),
        borderRadius: BorderRadius.circular(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              LayoutBuilder(builder: (context, b) => CollectionCover(view: widget.view, collection: c, size: b.maxWidth)),
              if (!done)
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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(cleanTitle(c['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Text(_meta(c), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim, fontSize: 11)),
        ]),
      ),
    );
  }
}
