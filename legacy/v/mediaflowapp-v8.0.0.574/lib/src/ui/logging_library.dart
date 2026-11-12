// The Logging Library: the website's title picker for logging (search, category /
// status / priority filters, sorts with direction and shuffle, page size and
// paging, five layouts, always-on multi-select with bulk add, "already added"
// marks, Add recommended title, and new typed titles in Quick).
// Used inline on the Log tab ("Browse Library") and from the "+" button.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_prefs.dart';
import '../logic/library_index.dart';
import '../logic/log_arrange.dart';
import '../state/models.dart';
import '../util/js.dart';
import 'theme.dart';
import 'widgets.dart';

const _layouts = [
  ('list', 'List', Icons.view_list_rounded),
  ('compact', 'Compact', Icons.view_headline_rounded),
  ('cards', 'Cards', Icons.view_agenda_rounded),
  ('covers', 'Covers', Icons.grid_view_rounded),
  ('covers-titles', 'Covers + titles', Icons.view_module_rounded),
];

String statusName(String s) => switch (s) {
      'planned' => 'Planned',
      'active' => 'In progress',
      'paused' => 'Paused',
      'completed' => 'Completed',
      'dropped' => 'Dropped',
      _ => s,
    };

class LoggingLibrary extends StatefulWidget {
  const LoggingLibrary({
    super.key,
    required this.view,
    required this.draft,
    required this.picker,
    required this.onPicker,
    required this.onAdd,
    this.onAddNew,
    this.recommendedId,
    this.onAddRecommended,
    this.onPageSize,
    this.scrollable = false,
    this.onOpenTitle,
  });

  final AccountView view;
  final Map<String, dynamic> draft;
  final PickerState picker;
  final ValueChanged<PickerState> onPicker;

  /// Adds Library titles (one tap, or the selected ones); returns how many were added.
  final int Function(List<String> ids) onAdd;
  final ValueChanged<String>? onAddNew;
  final String? recommendedId;
  final VoidCallback? onAddRecommended;

  /// Changes the website's "Per page" setting for the Logging Library.
  final ValueChanged<int>? onPageSize;

  /// True in the "+" sheet (the picker scrolls by itself).
  final bool scrollable;

  /// v565: view or edit a title from the Logging Library.
  final ValueChanged<String>? onOpenTitle;

  @override
  State<LoggingLibrary> createState() => _LoggingLibraryState();
}

class _LoggingLibraryState extends State<LoggingLibrary> {
  final _search = TextEditingController();
  final Set<String> _selected = {};

  PickerState get st => widget.picker;

  String _query = '';
  Timer? _searchTimer;

  // The base order on screen, and the one being worked out in the background.
  LibraryIndex? _shownIndex;
  Int32List? _shownOrder;
  String _shownKey = '';
  String _wantKey = '';

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String _) {
    _searchTimer?.cancel();
    final delay = (_shownIndex?.length ?? 0) >= kLibraryBackgroundThreshold ? 250 : 0;
    _searchTimer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      setState(() {
        _query = _search.text;
        st.page = 0;
      });
    });
    setState(() {}); // the clear button and "Add as a new title"
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _search.clear();
    _query = '';
    st.page = 0;
  }

  /// `pickerCandidates`, fast for 100,000+ titles (see LibraryIndex). The
  /// sort runs in the background for a big Library; the previous order stays
  /// on screen until it's done. Null until the first order is ready.
  List<Map<String, dynamic>>? _rows(LibraryIndex index) {
    // "Log added" puts the titles in this log first; the rest follow by title.
    final logAdded = st.sortBase == 'logAdded';
    final sort = logAdded ? 'title' : st.sortBase;
    final dir = logAdded ? 'asc' : st.sortDir;
    final key = '${identityHashCode(index)}|$sort|$dir|${sort == 'random' ? st.seed : 0}';
    if (key != _wantKey) {
      _wantKey = key;
      var building = true;
      index.pickerOrder(sort, dir, st.seed).then((order) {
        if (!mounted || _wantKey != key) return;
        void take() {
          _shownIndex = index;
          _shownOrder = order;
          _shownKey = key;
        }

        building ? take() : setState(take);
      });
      building = false;
    }
    final shown = _shownIndex, order = _shownOrder;
    if (shown == null || order == null) return null;
    final entries = asList(widget.draft['entries']);
    final addedKey = logAdded
        ? [for (final e in entries) '${jsStr(asMap(e)?['libraryId'])}@${jsStr(asMap(e)?['loggedAt'])}'].join(',')
        : '';
    final filterKey = '$_shownKey|${st.status}|${st.priority}|${st.categories.join(',')}|$_query|${logAdded ? '${st.sortDir}|$addedKey' : ''}';
    final cacheKey = '${identityHashCode(shown)}|$filterKey';
    if (cacheKey == _rowsKey && _rowsCache != null) return _rowsCache;
    Iterable<int> rows = order;
    if (logAdded) rows = _logAddedOrder(shown, order, entries);
    _rowsKey = cacheKey;
    return _rowsCache = shown.pickerRows(rows, status: st.status, priority: st.priority, categories: st.categories, query: _query);
  }

  // The last filtered rows (selecting titles or paging redraws without refiltering).
  String _rowsKey = '';
  List<Map<String, dynamic>>? _rowsCache;

  /// `pickerCandidates` for "Log added": titles in this log first (by when they
  /// were added, in the chosen direction), then every other title by title.
  Iterable<int> _logAddedOrder(LibraryIndex index, Int32List byTitle, List<dynamic> entries) {
    final sign = st.sortDir == 'desc' ? -1 : 1;
    final selected = <int, double>{};
    for (var i = 0; i < entries.length; i++) {
      final e = asMap(entries[i]);
      final pos = index.positionOf(jsStr(e?['libraryId']));
      if (pos < 0) continue;
      final raw = e?['loggedAt'];
      var ts = jsNumOrNull(raw) ?? 0;
      if (ts <= 0 && raw is String) ts = (DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0).toDouble();
      selected[pos] = ts != 0 ? ts : (i + 1).toDouble();
    }
    if (selected.isEmpty) return byTitle;
    final rank = <int, int>{for (var i = 0; i < byTitle.length; i++) if (selected.containsKey(byTitle[i])) byTitle[i]: i};
    final first = selected.keys.toList()
      ..sort((a, b) {
        final d = sign * (selected[a]! - selected[b]!);
        if (d != 0) return d < 0 ? -1 : 1;
        final t = (rank[a] ?? 0) - (rank[b] ?? 0);
        return t != 0 ? t : a - b;
      });
    return [...first, ...byTitle.where((i) => !selected.containsKey(i))];
  }

  void _change(void Function(PickerState s) f) {
    f(st);
    widget.onPicker(st);
    setState(() {});
  }

  String get _layout => AppPrefs.instance.get<String>('loggingLibraryLayout', 'list');

  Set<String> get _added => {
        for (final e in asList(widget.draft['entries']))
          if (jsTruthy(asMap(e)?['libraryId'])) jsStr(asMap(e)!['libraryId']),
      };

  void _add(List<String> ids) {
    final n = widget.onAdd(ids);
    setState(() => _selected.removeAll(ids));
    final m = ScaffoldMessenger.maybeOf(context);
    m?.showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(n == 0
          ? 'No new titles added.'
          : ids.length == 1
              ? 'Title added. Enter consumption before submitting.'
              : '$n title${n == 1 ? '' : 's'} added to Logging. Fill in consumption to log.'),
    ));
  }

  Future<void> _pickCategories() async {
    final cats = widget.view.categories;
    final chosen = {...st.categories};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MF.surface,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                title: const Text('Show categories', style: TextStyle(fontWeight: FontWeight.w800)),
                trailing: TextButton(onPressed: () => set(chosen.clear), child: const Text('All')),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final cat in cats)
                    CheckboxListTile(
                      value: chosen.contains(cat.id),
                      onChanged: (v) => set(() => v == true ? chosen.add(cat.id) : chosen.remove(cat.id)),
                      secondary: CategoryBadge(cat, size: 28),
                      title: Text(cat.name),
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
    if (result != null) {
      _change((s) {
        s.categories = result.toList();
        s.page = 0;
      });
    }
  }

  Widget _dropdown<T>(String label, T value, List<(T, String)> items, ValueChanged<T> on) =>
      CompactDropdown<T>(value: value, items: items, onChanged: on, maxWidth: 220);

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final index = LibraryIndex.of(view.state);
    final ready = _rows(index);
    final loading = ready == null;
    final sorting = _wantKey != _shownKey;
    final rows = ready ?? const <Map<String, dynamic>>[];
    final size = loggingPageSize(view.state);
    final pages = (rows.length / size).ceil().clamp(1, 1 << 30);
    if (st.page > pages - 1) st.page = pages - 1;
    final pageRows = rows.skip(st.page * size).take(size).toList();
    final added = _added;
    final typed = _search.text.trim();
    final exact = typed.isNotEmpty &&
        memoFor(index, 'titleSet', () => {for (final t in index.titles) t.title.toLowerCase()}).contains(typed.toLowerCase());
    final recommendedAt = widget.recommendedId == null ? -1 : index.positionOf(widget.recommendedId!);
    final recommended = recommendedAt < 0 ? null : index.titles[recommendedAt];
    final catLabel = st.categories.isEmpty ? 'All categories' : '${st.categories.length} categories selected';

    final children = <Widget>[
      if (recommended != null && widget.onAddRecommended != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton.icon(
            onPressed: widget.onAddRecommended,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(added.contains(recommended.id) ? 'Show recommended title' : 'Add recommended title · ${recommended.title}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      TextField(
        controller: _search,
        onChanged: _onSearch,
        decoration: InputDecoration(
          hintText: 'Search your Library',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: typed.isEmpty
              ? null
              : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_clearSearch)),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ActionChip(avatar: const Icon(Icons.category_outlined, size: 16), label: Text(catLabel), onPressed: _pickCategories),
        _dropdown<String>('Status', st.status, [('all', 'All statuses'), for (final s in kStatuses) (s, statusName(s))],
            (v) => _change((s) {
                  s.status = v;
                  s.page = 0;
                })),
        _dropdown<String>('Priority', st.priority, [('all', 'All priorities'), for (final p in kPriorities) (p, '${p[0].toUpperCase()}${p.substring(1)}')],
            (v) => _change((s) {
                  s.priority = v;
                  s.page = 0;
                })),
        _dropdown<String>('Sort', st.sortBase, [for (final s in kPickerSorts) s],
            (v) => _change((s) {
                  s.sortBase = v;
                  s.page = 0;
                })),
        if (st.sortBase == 'random')
          ActionChip(
            avatar: const Icon(Icons.shuffle_rounded, size: 16),
            label: const Text('Shuffle'),
            onPressed: () => _change((s) => s.seed = (DateTime.now().millisecondsSinceEpoch % 2147483647).clamp(1, 2147483646)),
          )
        else
          ActionChip(
            avatar: Icon(st.sortDir == 'asc' ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 16),
            label: Text(st.sortDir == 'asc' ? 'Asc' : 'Desc'),
            onPressed: () => _change((s) => s.sortDir = s.sortDir == 'asc' ? 'desc' : 'asc'),
          ),
        if (st.categories.isNotEmpty || st.status != 'all' || st.priority != 'all')
          TextButton(
            onPressed: () => _change((s) {
              s.categories = [];
              s.status = 'all';
              s.priority = 'all';
              s.page = 0;
            }),
            child: const Text('Clear filters'),
          ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Text(
              loading
                  ? 'Sorting ${fmtNumber(index.length)} titles…'
                  : '${fmtNumber(rows.length)} match${rows.length == 1 ? '' : 'es'} · Page ${st.page + 1}/$pages',
              style: TextStyle(color: MF.textDim, fontSize: 12)),
        ),
        for (final l in _layouts)
          IconButton(
            tooltip: l.$2,
            visualDensity: VisualDensity.compact,
            icon: Icon(l.$3, size: 20, color: _layout == l.$1 ? MF.accent : MF.textDim),
            onPressed: () => AppPrefs.instance.set('loggingLibraryLayout', l.$1).then((_) => setState(() {})),
          ),
      ]),
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton(
          onPressed: () => setState(() {
            for (final r in pageRows) {
              final id = jsStr(r['id']);
              if (!added.contains(id) && r['status'] != 'dropped') _selected.add(id);
            }
          }),
          child: const Text('Select visible'),
        ),
        if (_selected.isNotEmpty) TextButton(onPressed: () => setState(_selected.clear), child: const Text('Deselect all')),
        if (_selected.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _add(_selected.toList()),
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text('Add selected (${_selected.length})'),
          ),
      ]),
      if (typed.isNotEmpty && !exact && widget.onAddNew != null)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(Icons.fiber_new_rounded, color: MF.accent),
          title: Text('Add “$typed” as a new title'),
          subtitle: Text('Created when you save the log', style: TextStyle(color: MF.textDim, fontSize: 12)),
          onTap: () {
            widget.onAddNew!(typed);
            setState(_clearSearch);
          },
        ),
      if (sorting) const Padding(padding: EdgeInsets.only(bottom: 6), child: LinearProgressIndicator(minHeight: 2)),
      if (loading)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else
        _results(pageRows, added),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (pages > 1) ...[
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: st.page == 0 ? null : () => _change((s) => s.page -= 1),
            ),
            Text('${st.page + 1} / $pages'),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: st.page >= pages - 1 ? null : () => _change((s) => s.page += 1),
            ),
            const SizedBox(width: 12),
          ],
          SizedBox(
            width: 92,
            child: TextFormField(
              key: ValueKey('pagesize-$size'),
              initialValue: '$size',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Per page', isDense: true),
              onFieldSubmitted: (v) {
                final n = int.tryParse(v) ?? size;
                widget.onPageSize?.call(n.clamp(1, 5000));
              },
            ),
          ),
        ]),
    ];
    if (widget.scrollable) {
      return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: children);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _results(List<Map<String, dynamic>> rows, Set<String> added) {
    final view = widget.view;
    if (rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: Text('No matching titles.', textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
      );
    }
    final layout = _layout;
    Widget check(String id, bool isAdded) => isAdded
        ? const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.check_circle_rounded, color: MF.good))
        : Checkbox(
            value: _selected.contains(id),
            onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
          );
    if (layout == 'covers' || layout == 'covers-titles') {
      return LayoutBuilder(builder: (context, c) {
        final perRow = (c.maxWidth / 96).floor().clamp(3, 10);
        final w = (c.maxWidth - (perRow - 1) * 8) / perRow;
        return Wrap(spacing: 8, runSpacing: 10, children: [
          for (final r in rows)
            () {
              final t = LibraryTitle(r);
              final id = t.id;
              final isAdded = added.contains(id);
              return GestureDetector(
                onTap: isAdded ? null : () => _add([id]),
                onLongPress: isAdded ? null : () => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id)),
                child: SizedBox(
                  width: w,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Stack(children: [
                      Cover(title: t, category: view.category(t.categoryId), width: w),
                      if (isAdded || _selected.contains(id))
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Icon(isAdded ? Icons.check_circle_rounded : Icons.radio_button_checked_rounded,
                              color: isAdded ? MF.good : MF.accent),
                        ),
                    ]),
                    if (layout == 'covers-titles') ...[
                      const SizedBox(height: 4),
                      Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    ],
                  ]),
                ),
              );
            }(),
        ]);
      });
    }
    return Column(children: [
      for (final r in rows)
        () {
          final t = LibraryTitle(r);
          final cat = view.category(t.categoryId);
          final isAdded = added.contains(t.id);
          final subtitle = '${cat.name} · ${progressText(t, cat)} · ${statusName(t.status)}';
          if (layout == 'compact') {
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              leading: check(t.id, isAdded),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(progressText(t, cat), style: TextStyle(color: MF.textDim, fontSize: 12)),
              onTap: isAdded ? null : () => _add([t.id]),
            );
          }
          if (layout == 'cards') {
            final total = t.total;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: isAdded ? null : () => _add([t.id]),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    Cover(title: t, category: cat, width: 54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim, fontSize: 12)),
                        if (total != null && total > 0) ...[
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: (t.progress / total).clamp(0, 1).toDouble(), minHeight: 4, borderRadius: BorderRadius.circular(4)),
                        ],
                      ]),
                    ),
                    if (widget.onOpenTitle != null)
                      IconButton(
                        tooltip: 'View or edit this title',
                        icon: Icon(Icons.info_outline_rounded, color: MF.textDim, size: 20),
                        onPressed: () => widget.onOpenTitle!(t.id),
                      ),
                    check(t.id, isAdded),
                  ]),
                ),
              ),
            );
          }
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Cover(title: t, category: cat, width: 34),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: MF.textDim, fontSize: 12)),
            trailing: widget.onOpenTitle == null
                ? check(t.id, isAdded)
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'View or edit this title',
                      icon: Icon(Icons.info_outline_rounded, color: MF.textDim, size: 20),
                      onPressed: () => widget.onOpenTitle!(t.id),
                    ),
                    check(t.id, isAdded),
                  ]),
            onTap: isAdded ? null : () => _add([t.id]),
          );
        }(),
    ]);
  }
}
