// Collections: browse (covers / list), search and sort; a collection's titles
// with progress, reorder, remove, Add titles (search, filters, multi-select);
// create, edit and delete — with the website's Collection XP.

import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../logic/collections_logic.dart';
import '../logic/log_arrange.dart' show compareTitlesNatural;
import '../state/models.dart';
import '../util/js.dart';
import 'theme.dart';
import 'title_screen.dart';
import 'widgets.dart';

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

/// A 2×2 collage of the collection's covers (or its own cover).
class CollectionCover extends StatelessWidget {
  const CollectionCover({super.key, required this.view, required this.collection, this.size = 96});
  final AccountView view;
  final Map<String, dynamic> collection;
  final double size;

  @override
  Widget build(BuildContext context) {
    final own = jsStr(collection['coverUrl']);
    if (own.isNotEmpty) {
      return Cover(title: LibraryTitle(<String, dynamic>{'title': collection['title'], 'coverUrl': own}), category: Category.removed(''), width: size);
    }
    final byId = {for (final t in view.library) t.id: t};
    final items = [for (final id in collectionTitleIds(collection)) if (byId[id] != null) byId[id]!];
    final withCovers = items.where((t) => t.coverUrl.isNotEmpty).toList();
    final shown = (withCovers.isNotEmpty ? withCovers : items).take(4).toList();
    final h = size * 1.5;
    if (shown.isEmpty) {
      return Container(
        width: size,
        height: h,
        decoration: BoxDecoration(color: MF.raised, borderRadius: BorderRadius.circular(10)),
        child: const Center(child: Text('◇', style: TextStyle(fontSize: 28, color: MF.textDim))),
      );
    }
    if (shown.length == 1) return Cover(title: shown.first, category: view.category(shown.first.categoryId), width: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: h,
        child: GridView.count(
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: (size / 2) / (h / 2),
          children: [for (final t in shown) Cover(title: t, category: view.category(t.categoryId), width: size / 2)],
        ),
      ),
    );
  }
}

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key, required this.account});
  final AccountController account;

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  final _search = TextEditingController();
  AccountController get account => widget.account;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([account, AppPrefs.instance]),
      builder: (context, _) {
        final view = account.view;
        if (view == null) return const SizedBox.shrink();
        final sort = AppPrefs.instance.get<String>('collectionsSort', 'updated');
        final layout = AppPrefs.instance.get<String>('collectionsView', 'covers');
        final q = _search.text.trim().toLowerCase();
        final list = collectionsOf(view.state).where((c) => q.isEmpty || '${c['title']} ${c['description']}'.toLowerCase().contains(q)).toList()
          ..sort((a, b) => switch (sort) {
                'title' => compareTitlesNatural(jsStr(a['title']), jsStr(b['title'])),
                'created' => jsNum(b['createdAt']).compareTo(jsNum(a['createdAt'])),
                'size' => collectionTitleIds(b).length.compareTo(collectionTitleIds(a).length),
                _ => jsNum(b['updatedAt']).compareTo(jsNum(a['updatedAt'])),
              });
        return Scaffold(
          appBar: AppBar(title: const Text('Collections'), actions: [SyncIndicator(account: account)]),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () => editCollection(context, account, null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New collection'),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Search collections', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              CompactDropdown<String>(
                value: sort,
                items: const [('updated', 'Recently updated'), ('created', 'Newest'), ('title', 'Title'), ('size', 'Most titles')],
                onChanged: (v) => AppPrefs.instance.set('collectionsSort', v),
              ),
              const Spacer(),
              for (final v in const [('covers', Icons.grid_view_rounded), ('list', Icons.view_list_rounded)])
                IconButton(
                  icon: Icon(v.$2, color: layout == v.$1 ? MF.accent : MF.textDim),
                  onPressed: () => AppPrefs.instance.set('collectionsView', v.$1),
                ),
            ]),
            const SizedBox(height: 8),
            if (list.isEmpty)
              const EmptyState(icon: Icons.collections_bookmark_outlined, title: 'No collections yet', body: 'Group titles into collections — a franchise, a reading list, anything.')
            else if (layout == 'covers')
              Wrap(spacing: 12, runSpacing: 14, children: [
                for (final c in list)
                  SizedBox(
                    width: 150,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollectionScreen(account: account, id: jsStr(c['id'])))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CollectionCover(view: view, collection: c, size: 150),
                        const SizedBox(height: 6),
                        Text(jsStr(c['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(_summary(view, c), style: const TextStyle(color: MF.textDim, fontSize: 12)),
                      ]),
                    ),
                  ),
              ])
            else
              for (final c in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CollectionCover(view: view, collection: c, size: 44),
                  title: Text(jsStr(c['title']), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(_summary(view, c)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollectionScreen(account: account, id: jsStr(c['id'])))),
                ),
          ]),
        );
      },
    );
  }

  String _summary(AccountView view, Map<String, dynamic> c) {
    final p = collectionProgress(view.state, c);
    return '${p.total} title${p.total == 1 ? '' : 's'} · ${p.pct}% · ${p.done} done';
  }
}

/// Create (id null) or edit a collection.
Future<void> editCollection(BuildContext context, AccountController account, String? id) async {
  final view = account.view!;
  final c = id == null ? null : collectionById(view.state, id);
  final title = TextEditingController(text: jsStr(c?['title']));
  final cover = TextEditingController(text: jsStr(c?['coverUrl']));
  final desc = TextEditingController(text: jsStr(c?['description']));
  final bg = TextEditingController(text: jsStr(c?['backgroundUrl']));
  var custom = c?['backgroundMode'] == 'custom';
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(id == null ? 'New collection' : 'Edit collection'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, autofocus: id == null, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: desc, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
            TextField(controller: cover, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Cover image URL (optional)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Custom background'),
              subtitle: const Text('Otherwise the background rotates through title covers.'),
              value: custom,
              onChanged: (v) => set(() => custom = v),
            ),
            if (custom) TextField(controller: bg, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Background image URL')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  final values = (title.text, cover.text, desc.text, bg.text);
  for (final x in [title, cover, desc, bg]) {
    x.dispose();
  }
  if (ok != true) return;
  if (values.$1.trim().isEmpty) {
    if (context.mounted) _toast(context, 'Give the collection a title.');
    return;
  }
  await account.edit((s, now) {
    var k = 0;
    saveCollection(s, id, now, () => mediaFlowUid(now + k++),
        title: values.$1, coverUrl: values.$2, description: values.$3, backgroundUrl: values.$4, customBackground: custom);
  }, label: id == null ? 'Create collection' : 'Edit collection');
  if (context.mounted) _toast(context, id == null ? 'Collection created ✓' : 'Collection updated ✓');
}

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.account, required this.id});
  final AccountController account;
  final String id;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final Set<String> _selected = {};
  AccountController get account => widget.account;

  Future<void> _run(String label, void Function(Map<String, dynamic> s, int now, String Function() uid) f) =>
      account.edit((s, now) {
        var k = 0;
        f(s, now, () => mediaFlowUid(now + k++));
      }, label: label);

  Future<void> _addTitles(AccountView view, Map<String, dynamic> c) async {
    final ids = await pickLibraryTitles(context, view, exclude: collectionTitleIds(c).toSet(), title: 'Add titles to ${jsStr(c['title'])}');
    if (ids == null || ids.isEmpty) return;
    var n = 0;
    await _run('Add titles to collection', (s, now, uid) => n = addCollectionTitles(s, widget.id, ids, now, uid));
    if (mounted) _toast(context, '$n title${n == 1 ? '' : 's'} added ✓');
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete collection “${jsStr(c['title'])}”?'),
        content: const Text('Titles stay in your Library.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: MF.bad), onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    await _run('Delete collection', (s, now, uid) => deleteCollection(s, widget.id, now));
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final view = account.view;
        final c = view == null ? null : collectionById(view.state, widget.id);
        if (view == null || c == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Collection not found'));
        }
        final byId = {for (final t in view.library) t.id: t};
        final ids = collectionTitleIds(c);
        final items = [for (final id in ids) if (byId[id] != null) byId[id]!];
        final p = collectionProgress(view.state, c);
        return Scaffold(
          appBar: AppBar(
            title: Text(jsStr(c['title'])),
            actions: [
              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_rounded), onPressed: () => editCollection(context, account, widget.id)),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'delete') _delete(c);
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete collection', style: TextStyle(color: MF.bad)))],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () => _addTitles(view, c),
            icon: const Icon(Icons.playlist_add_rounded),
            label: const Text('Add titles'),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CollectionCover(view: view, collection: c, size: 96),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(jsStr(c['title']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  if (jsStr(c['description']).isNotEmpty) Text(jsStr(c['description']), style: const TextStyle(color: MF.textDim)),
                  const SizedBox(height: 8),
                  Text('${p.total} titles · ${p.done} completed', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: p.pct / 100, minHeight: 6, borderRadius: BorderRadius.circular(4)),
                  Text('${p.pct}% complete', style: const TextStyle(color: MF.textDim, fontSize: 12)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            if (_selected.isNotEmpty)
              Wrap(spacing: 8, children: [
                TextButton(onPressed: () => setState(_selected.clear), child: Text('Deselect (${_selected.length})')),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final ids = {..._selected};
                    await _run('Remove from collection', (s, now, uid) => removeCollectionTitles(s, widget.id, ids, now, uid));
                    setState(_selected.clear);
                  },
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                  label: const Text('Remove selected'),
                ),
              ]),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No titles yet. Tap Add titles.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
              ),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Checkbox(
                    value: _selected.contains(items[i].id),
                    onChanged: (v) => setState(() => v == true ? _selected.add(items[i].id) : _selected.remove(items[i].id)),
                  ),
                  SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(color: MF.textDim, fontWeight: FontWeight.w800))),
                  Cover(title: items[i], category: view.category(items[i].categoryId), width: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => openTitle(context, account, items[i].id),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(items[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${view.category(items[i].categoryId).name} · ${progressText(items[i], view.category(items[i].categoryId))} · ${statusLabel(items[i].status)}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MF.textDim, fontSize: 12)),
                      ]),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      final tid = items[i].id;
                      switch (v) {
                        case 'top':
                          _run('Reorder collection', (s, now, uid) => moveCollectionTitle(s, widget.id, tid, now, uid, toIndex: 0));
                        case 'up':
                          _run('Reorder collection', (s, now, uid) => moveCollectionTitle(s, widget.id, tid, now, uid, delta: -1));
                        case 'down':
                          _run('Reorder collection', (s, now, uid) => moveCollectionTitle(s, widget.id, tid, now, uid, delta: 1));
                        case 'bottom':
                          _run('Reorder collection', (s, now, uid) => moveCollectionTitle(s, widget.id, tid, now, uid, toIndex: 1 << 20));
                        case 'remove':
                          _run('Remove from collection', (s, now, uid) => removeCollectionTitles(s, widget.id, {tid}, now, uid));
                      }
                    },
                    itemBuilder: (_) => [
                      if (i > 0) const PopupMenuItem(value: 'top', child: Text('Move to top')),
                      if (i > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
                      if (i < items.length - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
                      if (i < items.length - 1) const PopupMenuItem(value: 'bottom', child: Text('Move to bottom')),
                      const PopupMenuItem(value: 'remove', child: Text('Remove from collection')),
                    ],
                  ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

/// A Library title picker (search, category and status filters, multi-select).
Future<List<String>?> pickLibraryTitles(BuildContext context, AccountView view, {Set<String> exclude = const {}, String title = 'Add titles'}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    builder: (c) => _TitlePicker(view: view, exclude: exclude, title: title),
  );
}

class _TitlePicker extends StatefulWidget {
  const _TitlePicker({required this.view, required this.exclude, required this.title});
  final AccountView view;
  final Set<String> exclude;
  final String title;

  @override
  State<_TitlePicker> createState() => _TitlePickerState();
}

class _TitlePickerState extends State<_TitlePicker> {
  final _search = TextEditingController();
  final Set<String> _picked = {};
  String _cat = '', _status = 'all';
  int _shown = 60;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final q = _search.text.trim().toLowerCase();
    final rows = view.library
        .where((t) => !widget.exclude.contains(t.id))
        .where((t) => _cat.isEmpty || t.categoryId == _cat)
        .where((t) => _status == 'all' || t.status == _status)
        .where((t) => q.isEmpty || t.title.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => compareTitlesNatural(a.title, b.title));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            FilledButton(
              onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.toList()),
              child: Text('Add ${_picked.isEmpty ? '' : '(${_picked.length})'}'),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() => _shown = 60),
            decoration: const InputDecoration(hintText: 'Search your Library', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            CompactDropdown<String>(
              value: _cat,
              items: [('', 'All categories'), for (final c in view.categories) (c.id, c.name)],
              onChanged: (v) => setState(() => _cat = v),
              maxWidth: 200,
            ),
            CompactDropdown<String>(
              value: _status,
              items: [('all', 'All statuses'), ...kStatusChoices],
              onChanged: (v) => setState(() => _status = v),
              maxWidth: 170,
            ),
            TextButton(
              onPressed: () => setState(() => _picked.addAll(rows.take(_shown).map((t) => t.id))),
              child: const Text('Select visible'),
            ),
            if (_picked.isNotEmpty) TextButton(onPressed: () => setState(_picked.clear), child: const Text('Deselect all')),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length > _shown ? _shown + 1 : rows.length,
            itemBuilder: (context, i) {
              if (i == _shown) {
                return TextButton(onPressed: () => setState(() => _shown += 60), child: Text('Show more (${rows.length - _shown} left)'));
              }
              final t = rows[i];
              final cat = view.category(t.categoryId);
              return CheckboxListTile(
                value: _picked.contains(t.id),
                onChanged: (v) => setState(() => v == true ? _picked.add(t.id) : _picked.remove(t.id)),
                secondary: Cover(title: t, category: cat, width: 32),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${cat.name} · ${statusLabel(t.status)}', maxLines: 1),
              );
            },
          ),
        ),
      ]),
    );
  }
}
