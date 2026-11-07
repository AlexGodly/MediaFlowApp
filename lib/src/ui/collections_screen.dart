// Collections: browse (covers / list), search and sort; each collection is a
// mini Library like the website's (v274): Order view on/off, the website's
// display modes, sorting, filters, select + batch actions, edit and remove;
// Add titles with search and filters (fast for 100,000+ titles); create, edit
// and delete — with the website's Collection XP.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/account_controller.dart';
import '../data/app_prefs.dart';
import '../logic/collections_logic.dart';
import '../logic/library_index.dart';
import '../logic/library_logic.dart' show batchEdit;
import '../logic/log_arrange.dart' show compareTitlesNatural;
import '../state/models.dart';
import '../util/js.dart';
import 'library_screen.dart' show LibraryCoverTile, LibraryTitleRow;
import 'presence.dart';
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
        child: Center(child: Text('◇', style: TextStyle(fontSize: 28, color: MF.textDim))),
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
    return LiveBuilder(
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
                        Text(_summary(view, c), style: TextStyle(color: MF.textDim, fontSize: 12)),
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

// ---- a collection: the website's mini Library (v274) ---------------------------

const _detailViews = [
  ('list', 'List', Icons.view_list_rounded),
  ('compact', 'Compact', Icons.view_headline_rounded),
  ('cards', 'Cards', Icons.view_agenda_rounded),
  ('covers', 'Covers', Icons.grid_view_rounded),
  ('covers-title', 'Covers + Titles', Icons.grid_on_rounded),
];

const _detailSorts = [
  ('order', 'Collection order'),
  ('title', 'Alphabetic'),
  ('priority', 'Priority'),
  ('rating', 'Rating'),
  ('progress', 'Consumed progress'),
  ('total', 'Total progress'),
  ('year', 'Year'),
];

const _ratingFilters = [
  ('all', 'Any rating'),
  ('rated', 'Rated'),
  ('unrated', 'Unrated'),
  ('9+', '9+'),
  ('8+', '8+'),
  ('7+', '7+'),
  ('6+', '6+'),
  ('5+', '5+'),
];

/// `V274_UI.filters`: kept while the app is open, like the website.
class _CollectionFilters {
  String search = '', status = 'all', priority = 'all', rating = 'all', cover = 'all', sort = 'order', dir = 'asc';
  String moderator = 'all';
  Set<String> categories = {};
  final Map<String, String> ranges = {};
  int limit = 0;

  bool get active =>
      search.isNotEmpty ||
      status != 'all' ||
      priority != 'all' ||
      rating != 'all' ||
      cover != 'all' ||
      moderator != 'all' ||
      categories.isNotEmpty ||
      ranges.values.any((v) => v.trim().isNotEmpty) ||
      limit > 0;

  String get key =>
      [search, status, priority, rating, cover, sort, dir, moderator, (categories.toList()..sort()).join(','), ranges.toString(), limit].join('|');
}

double _num(Object? v) => jsNumOrNull(v) ?? 0;

String _coverOf(Map<String, dynamic> i) =>
    [i['coverUrl'], i['cover'], i['imageUrl']].map(jsStr).firstWhere((s) => s.trim().isNotEmpty, orElse: () => '').trim();

/// `v274RuntimeMinutes`, `v274SeasonCount`, `v274EpisodeCount`, `v274ServiceLinked`.
double _runtime(Map<String, dynamic> i) {
  for (final k in ['runtimeMinutes', 'runtime', 'durationMinutes', 'duration', 'minutesPerEpisode']) {
    final n = jsNumOrNull(i[k]);
    if (n != null && n.isFinite && n > 0) return n;
  }
  return 0;
}

double _seasons(Map<String, dynamic> i) => i['seasons'] is List ? (i['seasons'] as List).length.toDouble() : _num(i['seasonCount']);

double _episodes(Map<String, dynamic> i, Category cat) =>
    cat.unit == 'episodes' ? _num(i['total']).clamp(0, double.infinity).toDouble() : _num(i['episodeCount']).clamp(0, double.infinity).toDouble();

bool _serviceLinked(Map<String, dynamic> i) =>
    const ['malId', 'simklId', 'tmdbId', 'tvdbId', 'anilistId', 'kitsuId', 'imdbId', 'mediaServiceId'].any((k) => jsStr(i[k]).trim().isNotEmpty);

bool _ratingMatch(LibraryTitle t, String mode) {
  final r = t.rating ?? 0;
  if (mode == 'rated') return r > 0;
  if (mode == 'unrated') return r <= 0;
  final m = RegExp(r'^(\d+)\+$').firstMatch(mode);
  if (m != null) return r >= int.parse(m[1]!);
  return true;
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
  final _f = _CollectionFilters();
  final _search = TextEditingController();
  Timer? _searchTimer;
  bool _orderView = false;
  int _page = 0;

  // Natural title order (worked out once per Library change, in the background
  // for big Libraries).
  LibraryIndex? _rankFor;
  Int32List? _rank;

  // The last filtered rows (redraws for selection reuse them).
  String _rowsKey = '';
  List<LibraryTitle> _rows = const [];

  AccountController get account => widget.account;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(String label, void Function(Map<String, dynamic> s, int now, String Function() uid) f) =>
      account.edit((s, now) {
        var k = 0;
        f(s, now, () => mediaFlowUid(now + k++));
      }, label: label);

  Map<String, dynamic> _settings(AccountView view) => asMap(asMap(view.state['settings'])?['v274Collections']) ?? const {};

  String _mode(AccountView view) {
    final m = jsStr(_settings(view)['detailView']);
    return _detailViews.any((v) => v.$1 == m) ? m : 'covers-title';
  }

  int _pageSize(AccountView view) => jsNum(_settings(view)['pageSize']).round().clamp(10, 200).toInt();
  bool _toolsVisible(AccountView view) => _settings(view)['toolsVisible'] != false;

  /// Collection display settings are account settings (synced like the website's).
  Future<void> _setSetting(String key, Object value) async {
    await account.setSetting(['v274Collections', key], value);
    await account.setSetting(['v274Collections', 'modifiedAt'], DateTime.now().millisecondsSinceEpoch);
  }

  void _ensureRank(LibraryIndex index) {
    if (identical(_rankFor, index)) return;
    _rankFor = index;
    _rank = null;
    index.rank().then((r) {
      if (!mounted || !identical(_rankFor, index)) return;
      if (_rank == null) {
        _rank = r;
        _rowsKey = '';
        if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) setState(() {});
      }
    });
  }

  void _onSearch(String text) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _f.search = text;
        _page = 0;
      });
    });
  }

  /// `v274CollectionFilteredItems`.
  List<LibraryTitle> _filtered(AccountView view, LibraryIndex index, Map<String, dynamic> c) {
    final ids = collectionTitleIds(c);
    final key = '${identityHashCode(index)}|${identityHashCode(c)}|${ids.length}|${_f.key}|${_rank != null}';
    if (key == _rowsKey) return _rows;
    final manual = <String, int>{for (var i = 0; i < ids.length; i++) ids[i]: i};
    var rows = <LibraryTitle>[];
    for (final id in ids) {
      final at = index.positionOf(id);
      if (at >= 0) rows.add(index.titles[at]);
    }
    final q = _f.search.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows.where((t) {
        final i = t.raw;
        return [
          t.title,
          view.category(t.categoryId).name,
          jsStr(i['status']),
          jsStr(i['priority']),
          jsStr(i['year']),
          ...asList(i['tags']).map(jsStr),
          ...asList(i['genres']).map(jsStr),
        ].join(' ').toLowerCase().contains(q);
      }).toList();
    }
    if (_f.categories.isNotEmpty) rows = rows.where((t) => _f.categories.contains(t.categoryId)).toList();
    if (_f.status != 'all') rows = rows.where((t) => (jsStr(t.raw['status']).isEmpty ? 'planned' : jsStr(t.raw['status'])) == _f.status).toList();
    if (_f.priority != 'all') {
      rows = rows.where((t) => (jsStr(t.raw['priority']).isEmpty ? 'medium' : jsStr(t.raw['priority'])) == _f.priority).toList();
    }
    if (_f.rating != 'all') rows = rows.where((t) => _ratingMatch(t, _f.rating)).toList();
    if (_f.cover == 'has') rows = rows.where((t) => _coverOf(t.raw).isNotEmpty).toList();
    if (_f.cover == 'missing') rows = rows.where((t) => _coverOf(t.raw).isEmpty).toList();
    void range(String name, double Function(LibraryTitle t) get) {
      final min = double.tryParse(_f.ranges['${name}Min']?.trim() ?? '');
      final max = double.tryParse(_f.ranges['${name}Max']?.trim() ?? '');
      if (min != null) rows = rows.where((t) => get(t) >= min).toList();
      if (max != null) rows = rows.where((t) => get(t) <= max).toList();
    }

    range('year', (t) => _num(t.raw['year']));
    range('runtime', (t) => _runtime(t.raw));
    range('season', (t) => _seasons(t.raw));
    range('episode', (t) => _episodes(t.raw, view.category(t.categoryId)));
    if (_f.moderator == 'imported') {
      rows = rows.where((t) => jsStr(t.raw['source']).trim().isNotEmpty && jsStr(t.raw['source']).toLowerCase() != 'manual').toList();
    } else if (_f.moderator == 'manual') {
      rows = rows.where((t) => jsStr(t.raw['source']).isEmpty || jsStr(t.raw['source']).toLowerCase() == 'manual').toList();
    } else if (_f.moderator == 'service') {
      rows = rows.where((t) => _serviceLinked(t.raw)).toList();
    }
    const rank = {'low': 0, 'medium': 1, 'high': 2};
    final titleRank = _rank;
    int titleCmp(LibraryTitle a, LibraryTitle b) {
      if (titleRank != null) {
        final x = index.positionOf(a.id), y = index.positionOf(b.id);
        if (x >= 0 && y >= 0) return titleRank[x] - titleRank[y];
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }

    final dir = _f.dir == 'desc' ? -1 : 1;
    int sign(double d) => d < 0 ? -1 : (d > 0 ? 1 : 0);
    rows.sort((a, b) {
      final d = switch (_f.sort) {
        'order' => (manual[a.id] ?? 999999) - (manual[b.id] ?? 999999),
        'title' => titleCmp(a, b),
        'priority' => (rank[jsStr(a.raw['priority']).isEmpty ? 'medium' : jsStr(a.raw['priority'])] ?? 1) -
            (rank[jsStr(b.raw['priority']).isEmpty ? 'medium' : jsStr(b.raw['priority'])] ?? 1),
        'rating' => sign(_num(a.raw['rating']) - _num(b.raw['rating'])),
        'progress' => sign(_num(a.raw['progress']) - _num(b.raw['progress'])),
        'total' => sign(_num(a.raw['total']) - _num(b.raw['total'])),
        'year' => sign(_num(a.raw['year']) - _num(b.raw['year'])),
        _ => 0,
      };
      return (d != 0 ? d : titleCmp(a, b)) * dir;
    });
    if (_f.limit > 0 && rows.length > _f.limit) rows = rows.sublist(0, _f.limit);
    _rowsKey = key;
    return _rows = rows;
  }

  Future<void> _addTitles(AccountView view, Map<String, dynamic> c) async {
    final ids = await pickLibraryTitles(context, view, exclude: collectionTitleIds(c).toSet(), title: 'Add titles to ${jsStr(c['title'])}');
    if (ids == null || ids.isEmpty) return;
    var n = 0;
    await _run('Add titles to collection', (s, now, uid) => n = addCollectionTitles(s, widget.id, ids, now, uid));
    if (mounted) _toast(context, '$n title${n == 1 ? '' : 's'} added ✓');
  }

  Future<void> _remove(Set<String> ids) async {
    var n = 0;
    await _run('Remove from collection', (s, now, uid) => n = removeCollectionTitles(s, widget.id, ids, now, uid));
    setState(() => _selected.removeAll(ids));
    if (mounted) _toast(context, n == 1 ? 'Removed from collection' : '$n titles removed from collection');
  }

  /// The Library's batch status / priority change for the selected titles.
  Future<void> _batch(String kind, String value, String label) async {
    final ids = {..._selected};
    if (ids.isEmpty) return;
    var changed = 0;
    await account.edit((s, now) {
      var k = 0;
      String uid() => mediaFlowUid(now + k++);
      changed = batchEdit(s, ids, kind, value, now, uid);
    }, label: 'Batch $kind');
    setState(_selected.clear);
    if (mounted) {
      _toast(context, kind == 'status' ? '$changed ${changed == 1 ? 'title' : 'titles'} changed to $label ✓' : '$changed ${changed == 1 ? 'title' : 'titles'} priority changed to $label ✓');
    }
  }

  void _edit(String id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TitleEditor(account: account, id: id)));

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

  Widget _titleMenu(String id, {bool compact = false}) {
    final menu = PopupMenuButton<String>(
        tooltip: 'Title actions',
        icon: Icon(Icons.more_vert_rounded, size: compact ? 18 : 22, color: compact ? Colors.white : null),
        padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
        onSelected: (v) {
          if (v == 'open') openTitle(context, account, id);
          if (v == 'edit') _edit(id);
          if (v == 'remove') _remove({id});
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'open', child: Text('Open')),
          PopupMenuItem(value: 'edit', child: Text('Edit title')),
          PopupMenuItem(value: 'remove', child: Text('Remove from collection')),
        ],
      );
    if (!compact) return menu;
    return Container(
      margin: const EdgeInsets.all(4),
      width: 30,
      height: 30,
      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
      child: menu,
    );
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      listenable: account,
      builder: (context, _) {
        final view = account.view;
        final c = view == null ? null : collectionById(view.state, widget.id);
        if (view == null || c == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Collection not found'));
        }
        final index = LibraryIndex.of(view.state);
        _ensureRank(index);
        final ids = collectionTitleIds(c);
        final p = collectionProgress(view.state, c);
        final mode = _mode(view);
        final rows = _orderView ? const <LibraryTitle>[] : _filtered(view, index, c);
        final size = _pageSize(view);
        final pages = rows.isEmpty ? 1 : (rows.length / size).ceil();
        if (_page > pages - 1) _page = pages - 1;
        final shown = rows.skip(_page * size).take(size).toList();
        return PresenceScope(info: PresenceInfo(situation: 'collection', values: {'collection': cleanTitle(c['title']), 'count': '${ids.length}'}), child: Scaffold(
          appBar: AppBar(
            title: Text(jsStr(c['title'])),
            actions: [
              IconButton(
                tooltip: _orderView ? 'Turn Order view off' : 'Order view: drag to reorder',
                isSelected: _orderView,
                icon: const Icon(Icons.swap_vert_rounded),
                onPressed: () => setState(() {
                  _orderView = !_orderView;
                  _selected.clear();
                }),
              ),
              IconButton(tooltip: 'Edit collection', icon: const Icon(Icons.edit_rounded), onPressed: () => editCollection(context, account, widget.id)),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'delete') _delete(c);
                  if (v == 'tools') _setSetting('toolsVisible', !_toolsVisible(view));
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'tools', child: Text(_toolsVisible(view) ? 'Hide Collection Tools' : 'Show Collection Tools')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete collection', style: TextStyle(color: MF.bad))),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: null,
            onPressed: () => _addTitles(view, c),
            icon: const Icon(Icons.playlist_add_rounded),
            label: const Text('Add titles'),
          ),
          body: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _hero(view, c, p)),
            if (_orderView)
              ..._orderSlivers(view, index, c, ids)
            else ...[
              SliverToBoxAdapter(child: _tools(view, c, rows.length, ids.length, mode)),
              if (_selected.isNotEmpty) SliverToBoxAdapter(child: _selectionBar(rows)),
              if (ids.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No titles yet. Tap Add titles.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
                  ),
                )
              else if (shown.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No titles match the current Collection Tools filters.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
                  ),
                )
              else if (mode == 'covers' || mode == 'covers-title')
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 130, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: mode == 'covers' ? 0.66 : 0.52),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => LibraryCoverTile(
                      title: shown[i],
                      category: view.category(shown[i].categoryId),
                      selected: _selected.contains(shown[i].id),
                      showTitle: mode == 'covers-title',
                      trailing: _titleMenu(shown[i].id, compact: true),
                      onTap: () => _selected.isNotEmpty ? _toggle(shown[i].id) : openTitle(context, account, shown[i].id),
                      onLongPress: () => _toggle(shown[i].id),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) => LibraryTitleRow(
                      title: shown[i],
                      category: view.category(shown[i].categoryId),
                      layout: mode,
                      selected: _selected.contains(shown[i].id),
                      onSelect: () => _toggle(shown[i].id),
                      onTap: () => openTitle(context, account, shown[i].id),
                      trailing: _titleMenu(shown[i].id),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  child: pages <= 1
                      ? const SizedBox.shrink()
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: _page == 0 ? null : () => setState(() => _page--)),
                          Text('Page ${_page + 1} / $pages · ${fmtNumber(rows.length)} matching titles'),
                          IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: _page >= pages - 1 ? null : () => setState(() => _page++)),
                        ]),
                ),
              ),
            ],
          ]),
        ));
      },
    );
  }

  Widget _hero(AccountView view, Map<String, dynamic> c, ({int pct, int done, int total}) p) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CollectionCover(view: view, collection: c, size: 96),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('COLLECTION', style: TextStyle(color: MF.textDim, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
              Text(jsStr(c['title']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text(jsStr(c['description']).isEmpty ? 'No description yet.' : jsStr(c['description']), style: TextStyle(color: MF.textDim)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: p.pct / 100, minHeight: 6, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 4),
              Text('${p.pct}% complete · ${p.done}/${p.total} titles completed', style: TextStyle(color: MF.textDim, fontSize: 12)),
            ]),
          ),
        ]),
      );

  Widget _tools(AccountView view, Map<String, dynamic> c, int visible, int total, String mode) {
    final count = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Text('${fmtNumber(visible)} visible of ${fmtNumber(total)} titles', style: TextStyle(color: MF.textDim, fontSize: 12)),
    );
    if (!_toolsVisible(view)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextButton.icon(
            onPressed: () => _setSetting('toolsVisible', true),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Show Collection Tools'),
          ),
        ),
        count,
      ]);
    }
    final cats = view.categories;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: MF.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _search,
          onChanged: _onSearch,
          decoration: InputDecoration(
            hintText: 'Search titles…',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      _onSearch('');
                    }),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ActionChip(
            avatar: const Icon(Icons.category_rounded, size: 16),
            label: Text(_f.categories.isEmpty ? 'All categories' : '${_f.categories.length} categories selected'),
            onPressed: () async {
              final picked = await showDialog<Set<String>>(
                context: context,
                builder: (d) => _CategoryPicker(categories: cats, selected: _f.categories),
              );
              if (picked != null) {
                setState(() {
                  _f.categories = picked;
                  _page = 0;
                });
              }
            },
          ),
          CompactDropdown<String>(
              value: _f.status, items: [('all', 'All statuses'), ...kStatusChoices], onChanged: (v) => setState(() => _set(() => _f.status = v)), maxWidth: 170),
          CompactDropdown<String>(
              value: _f.priority,
              items: [('all', 'All priorities'), ...kPriorityChoices],
              onChanged: (v) => setState(() => _set(() => _f.priority = v)),
              maxWidth: 170),
          CompactDropdown<String>(value: _f.rating, items: _ratingFilters, onChanged: (v) => setState(() => _set(() => _f.rating = v)), maxWidth: 150),
          CompactDropdown<String>(
              value: _f.cover,
              items: const [('all', 'Any cover'), ('has', 'Has cover'), ('missing', 'Missing cover')],
              onChanged: (v) => setState(() => _set(() => _f.cover = v)),
              maxWidth: 160),
          CompactDropdown<String>(value: _f.sort, items: _detailSorts, onChanged: (v) => setState(() => _set(() => _f.sort = v)), maxWidth: 190),
          OutlinedButton(
            onPressed: () => setState(() => _set(() => _f.dir = _f.dir == 'asc' ? 'desc' : 'asc')),
            child: Text(_f.dir == 'asc' ? 'ASC ↑' : 'DESC ↓'),
          ),
          if (_f.active || _f.sort != 'order' || _f.dir != 'asc')
            TextButton(
              onPressed: () => setState(() {
                _search.clear();
                _f
                  ..search = ''
                  ..status = 'all'
                  ..priority = 'all'
                  ..rating = 'all'
                  ..cover = 'all'
                  ..moderator = 'all'
                  ..categories = {}
                  ..limit = 0
                  ..sort = 'order'
                  ..dir = 'asc';
                _f.ranges.clear();
                _page = 0;
              }),
              child: const Text('Clear filters'),
            ),
        ]),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('More filters', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          children: [
            _rangeRow('Year', 'year', '1900', '2030'),
            _rangeRow('Running time (min)', 'runtime', '0', '300'),
            _rangeRow('Season count', 'season', '0', '50'),
            _rangeRow('Episode count', 'episode', '0', '2000'),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Limit items', style: TextStyle(color: MF.textDim)),
                for (final n in const [0, 5, 10, 100, 500, 1000, 10000])
                  ChoiceChip(
                    label: Text(n == 0 ? 'All' : fmtNumber(n)),
                    selected: _f.limit == n,
                    onSelected: (_) => setState(() => _set(() => _f.limit = n)),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CompactDropdown<String>(
                value: _f.moderator,
                items: const [
                  ('all', 'All titles'),
                  ('imported', 'Imported only'),
                  ('manual', 'Manual only'),
                  ('service', 'Has media-service ID'),
                ],
                onChanged: (v) => setState(() => _set(() => _f.moderator = v)),
                maxWidth: 220,
              ),
            ),
          ],
        ),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Display', style: TextStyle(color: MF.textDim)),
          for (final v in _detailViews)
            ChoiceChip(
              avatar: Icon(v.$3, size: 16),
              label: Text(v.$2),
              selected: mode == v.$1,
              onSelected: (_) {
                setState(() => _page = 0);
                _setSetting('detailView', v.$1);
              },
            ),
          const SizedBox(width: 6),
          CompactDropdown<int>(
            value: _pageSize(view),
            items: [for (final n in const [10, 25, 50, 100, 200]) (n, '$n per page')],
            onChanged: (v) {
              setState(() => _page = 0);
              _setSetting('pageSize', v);
            },
            maxWidth: 150,
          ),
        ]),
        const SizedBox(height: 4),
        count,
      ]),
    );
  }

  void _set(VoidCallback change) {
    change();
    _page = 0;
  }

  Widget _rangeRow(String label, String key, String a, String b) {
    Widget box(String which, String hint) => SizedBox(
          width: 92,
          child: TextFormField(
            initialValue: _f.ranges['$key$which'] ?? '',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: hint, isDense: true),
            onChanged: (v) {
              _f.ranges['$key$which'] = v;
              _searchTimer?.cancel();
              _searchTimer = Timer(const Duration(milliseconds: 300), () {
                if (mounted) setState(() => _page = 0);
              });
            },
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(label)),
        box('Min', a),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('to')),
        box('Max', b),
      ]),
    );
  }

  Widget _selectionBar(List<LibraryTitle> rows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('${_selected.length} selected', style: const TextStyle(fontWeight: FontWeight.w800)),
        TextButton(onPressed: () => setState(() => _selected.addAll(rows.map((t) => t.id))), child: const Text('Select all')),
        TextButton(onPressed: () => setState(_selected.clear), child: const Text('Deselect')),
        CompactDropdown<String>(
          value: '',
          items: [('', 'Set status…'), ...kStatusChoices],
          onChanged: (v) {
            if (v.isNotEmpty) _batch('status', v, kStatusChoices.firstWhere((s) => s.$1 == v).$2);
          },
          maxWidth: 160,
        ),
        CompactDropdown<String>(
          value: '',
          items: [('', 'Set priority…'), ...kPriorityChoices],
          onChanged: (v) {
            if (v.isNotEmpty) _batch('priority', v, kPriorityChoices.firstWhere((s) => s.$1 == v).$2);
          },
          maxWidth: 160,
        ),
        FilledButton.tonalIcon(
          onPressed: () => _remove({..._selected}),
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
          label: const Text('Remove selected'),
        ),
      ]),
    );
  }

  /// Order view: the collection's own order; drag (or ↑ ↓) to change it.
  /// Turning it off keeps the order as the collection's default.
  List<Widget> _orderSlivers(AccountView view, LibraryIndex index, Map<String, dynamic> c, List<String> ids) {
    final items = <LibraryTitle>[];
    for (final id in ids) {
      final at = index.positionOf(id);
      if (at >= 0) items.add(index.titles[at]);
    }
    return [
      SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: MF.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: MF.border)),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Order view  ', style: TextStyle(fontWeight: FontWeight.w900)),
            TextSpan(
                text: 'Drag titles or use the menu. Turning Order view off keeps this manual order as the collection’s default order.',
                style: TextStyle(color: MF.textDim)),
          ])),
        ),
      ),
      if (items.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(24), child: Text('Add titles before ordering this collection.', textAlign: TextAlign.center)),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
          sliver: SliverReorderableList(
            itemCount: items.length,
            onReorder: (from, to) {
              final tid = items[from].id;
              final target = to > from ? to - 1 : to;
              _run('Reorder collection', (s, now, uid) => moveCollectionTitle(s, widget.id, tid, now, uid, toIndex: target));
            },
            itemBuilder: (context, i) {
              final t = items[i];
              final cat = view.category(t.categoryId);
              return Material(
                key: ValueKey(t.id),
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    ReorderableDragStartListener(
                      index: i,
                      child: Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_indicator_rounded, color: MF.textDim)),
                    ),
                    SizedBox(width: 30, child: Text('${i + 1}', style: TextStyle(color: MF.textDim, fontWeight: FontWeight.w800))),
                    Cover(title: t, category: cat, width: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${cat.name} · ${statusLabel(t.status)}', maxLines: 1, style: TextStyle(color: MF.textDim, fontSize: 12)),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        final at = switch (v) { 'top' => 0, 'up' => i - 1, 'down' => i + 1, _ => items.length - 1 };
                        _run('Reorder collection', (s, now, uid) => moveCollectionTitle(s, widget.id, t.id, now, uid, toIndex: at));
                      },
                      itemBuilder: (_) => [
                        if (i > 0) const PopupMenuItem(value: 'top', child: Text('Move to top')),
                        if (i > 0) const PopupMenuItem(value: 'up', child: Text('Move up')),
                        if (i < items.length - 1) const PopupMenuItem(value: 'down', child: Text('Move down')),
                        if (i < items.length - 1) const PopupMenuItem(value: 'bottom', child: Text('Move to bottom')),
                      ],
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
    ];
  }
}

class _CategoryPicker extends StatefulWidget {
  const _CategoryPicker({required this.categories, required this.selected});
  final List<Category> categories;
  final Set<String> selected;

  @override
  State<_CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<_CategoryPicker> {
  late final Set<String> _picked = {...widget.selected};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Show categories'),
        content: SizedBox(
          width: 360,
          child: ListView(shrinkWrap: true, children: [
            for (final c in widget.categories)
              CheckboxListTile(
                value: _picked.contains(c.id),
                title: Text(c.name),
                secondary: CategoryBadge(c, size: 24),
                onChanged: (v) => setState(() => v == true ? _picked.add(c.id) : _picked.remove(c.id)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => setState(_picked.clear), child: const Text('All categories')),
          FilledButton(onPressed: () => Navigator.pop(context, _picked), child: const Text('Apply')),
        ],
      );
}

// ---- Add titles: a fast Library picker -------------------------------------------

/// A Library title picker (search, category and status filters, multi-select).
/// Uses the Library's prepared index: no re-sorting on each keystroke or tap.
Future<List<String>?> pickLibraryTitles(BuildContext context, AccountView view, {Set<String> exclude = const {}, String title = 'Add titles'}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: MF.surface,
    builder: (c) => PresenceScope(
      info: const PresenceInfo(situation: 'collections'),
      child: _TitlePicker(view: view, exclude: exclude, title: title),
    ),
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
  String _cat = '', _status = 'all', _query = '';
  int _shown = 60;
  Timer? _timer;
  Int32List? _order;
  String _rowsKey = '';
  List<LibraryTitle> _rows = const [];
  late final LibraryIndex _index = LibraryIndex.of(widget.view.state);

  @override
  void initState() {
    super.initState();
    // Natural title order: ready at once for small Libraries, in the
    // background for big ones.
    _index.libraryOrder('title', 'asc', 0).then((o) {
      if (!mounted) return;
      if (_order == null) {
        _order = o;
        if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) setState(() {});
      }
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
    final delay = _index.length >= kLibraryBackgroundThreshold ? 250 : 120;
    _timer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      setState(() {
        _query = text.trim().toLowerCase();
        _shown = 60;
      });
    });
  }

  List<LibraryTitle> _filtered() {
    final order = _order;
    if (order == null) return const [];
    final key = '$_cat|$_status|$_query';
    if (key == _rowsKey) return _rows;
    final search = _query.isEmpty ? null : _index.titleSearch;
    final out = <LibraryTitle>[];
    for (final i in order) {
      final t = _index.titles[i];
      if (widget.exclude.contains(t.id)) continue;
      if (_cat.isNotEmpty && t.categoryId != _cat) continue;
      if (_status != 'all' && t.status != _status) continue;
      if (search != null && !search[i].contains(_query)) continue;
      out.add(t);
    }
    _rowsKey = key;
    return _rows = out;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final rows = _filtered();
    final loading = _order == null;
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
            onChanged: _onSearch,
            decoration: InputDecoration(hintText: 'Search ${fmtNumber(_index.length)} titles', prefixIcon: const Icon(Icons.search_rounded)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            CompactDropdown<String>(
              value: _cat,
              items: [('', 'All categories'), for (final c in view.categories) (c.id, c.name)],
              onChanged: (v) => setState(() {
                _cat = v;
                _shown = 60;
              }),
              maxWidth: 200,
            ),
            CompactDropdown<String>(
              value: _status,
              items: [('all', 'All statuses'), ...kStatusChoices],
              onChanged: (v) => setState(() {
                _status = v;
                _shown = 60;
              }),
              maxWidth: 170,
            ),
            TextButton(
              onPressed: () => setState(() => _picked.addAll(rows.take(_shown).map((t) => t.id))),
              child: const Text('Select visible'),
            ),
            if (_picked.isNotEmpty) TextButton(onPressed: () => setState(_picked.clear), child: const Text('Deselect all')),
            Text(loading ? 'Sorting…' : '${fmtNumber(rows.length)} titles', style: TextStyle(color: MF.textDim, fontSize: 12)),
          ]),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: rows.length > _shown ? _shown + 1 : rows.length,
                  itemBuilder: (context, i) {
                    if (i == _shown) {
                      return TextButton(onPressed: () => setState(() => _shown += 60), child: Text('Show more (${fmtNumber(rows.length - _shown)} left)'));
                    }
                    final t = rows[i];
                    final cat = view.category(t.categoryId);
                    return CheckboxListTile(
                      key: ValueKey(t.id),
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
