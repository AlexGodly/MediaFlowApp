// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_library_index.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_editing_workspace.dart';
import 'native_editing_sheet.dart';
import '../../design_system/mediaflow_theme.dart';

enum NativeLibraryView { list, compact, cards, covers, coversWithTitles }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.repository, this.workspace});
  final MediaFlowLibraryRepository repository;
  final NativeEditingWorkspace? workspace;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<MediaFlowCatalog> _future;
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '', _category = '', _status = '', _priority = '';
  LibrarySort _sort = LibrarySort.alphabetical;
  NativeLibraryView _view = NativeLibraryView.list;
  int _page = 0, _perPage = 50;
  MediaFlowCatalog? _cacheCatalog;
  MediaFlowLibraryIndex? _libraryIndex;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _filterChanged() => setState(() {
    _page = 0;
    // Retain sorted snapshot index while filters change.
  });

  void _refresh() => setState(() {
    _cacheCatalog = null;
    _page = 0;
    _future = widget.repository.reload();
  });

  List<MediaFlowTitle> _results(MediaFlowCatalog catalog) {
    if (!identical(_cacheCatalog, catalog) || _libraryIndex == null) {
      _cacheCatalog = catalog;
      _libraryIndex = MediaFlowLibraryIndex(catalog.library);
    }
    return _libraryIndex!.query(MediaFlowLibraryFilter(
      search: _search,
      categoryId: _category,
      status: _status,
      priority: _priority,
      sort: _sort,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MediaFlowCatalog>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('Could not read your cloud Library. No data was changed.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _refresh, icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]));
        }
        final catalog = snapshot.data!;
        final matched = _results(catalog);
        final pages = matched.isEmpty ? 1 : (matched.length + _perPage - 1) ~/ _perPage;
        final page = _page.clamp(0, pages - 1);
        final start = page * _perPage;
        final visible = matched.skip(start).take(_perPage).toList(growable: false);
        final cats = catalog.categoryById;
        return LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Library', style: Theme.of(context).textTheme.headlineMedium),
                Text(catalog.library.length.toString() + ' saved titles',
                    style: Theme.of(context).textTheme.bodySmall),
              ])),
              IconButton(
                tooltip: 'Refresh from cloud (read-only)',
                onPressed: _refresh, icon: const Icon(Icons.refresh),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search Library',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _debounce?.cancel();
                        _searchController.clear();
                        _search = '';
                        _filterChanged();
                      }),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 220), () {
                  if (!mounted) return;
                  _search = value;
                  _filterChanged();
                });
              },
            ),
            const SizedBox(height: 12),
            _filterBar(context, catalog, width),
            const SizedBox(height: 10),
            Text('Showing ' + (matched.isEmpty ? 0 : start + 1).toString() +
                 '–' + (start + visible.length).toString() +
                 ' of ' + matched.length.toString() + ' · Read-only',
                 style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(child: visible.isEmpty
                ? Center(child: Text(catalog.library.isEmpty
                    ? 'Your Library is empty.' : 'No titles match these filters.'))
                : _titleList(context, visible, cats, width)),
            _pager(context, page, pages),
          ]);
        });
      },
    );
  }

  Widget _filterBar(BuildContext context, MediaFlowCatalog catalog, double width) {
    final unit = width >= 950 ? (width - 40) / 5
        : width >= 620 ? (width - 16) / 3 : (width - 8) / 2;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _selector<String>(unit, 'Category', _category, [
        const DropdownMenuItem(value: '', child: Text('All categories')),
        for (final category in catalog.categories)
          DropdownMenuItem(value: category.id,
            child: Text(category.name, overflow: TextOverflow.ellipsis)),
      ], (next) { _category = next; _filterChanged(); }),
      _selector<String>(unit, 'Status', _status, [
        const DropdownMenuItem(value: '', child: Text('All statuses')),
        for (final s in ['active','paused','completed','dropped','planned'])
          DropdownMenuItem(value: s, child: Text(_statusName(s))),
      ], (next) { _status = next; _filterChanged(); }),
      _selector<String>(unit, 'Priority', _priority, [
        const DropdownMenuItem(value: '', child: Text('All priorities')),
        for (final p in ['high','medium','low'])
          DropdownMenuItem(value: p, child: Text(_capitalize(p))),
      ], (next) { _priority = next; _filterChanged(); }),
      _selector<LibrarySort>(unit, 'Sort', _sort, [
        for (final s in LibrarySort.values)
          DropdownMenuItem(value: s, child: Text(_sortName(s),
            overflow: TextOverflow.ellipsis)),
      ], (next) { _sort = next; _filterChanged(); }),
      _selector<NativeLibraryView>(unit, 'Display', _view, [
        for (final v in NativeLibraryView.values)
          DropdownMenuItem(value: v, child: Text(_viewName(v),
            overflow: TextOverflow.ellipsis)),
      ], (next) => setState(() => _view = next)),
    ]);
  }

  Widget _selector<T>(
    double width, String label, T value, List<DropdownMenuItem<T>> choices,
    ValueChanged<T> change,
  ) => SizedBox(width: width, child: InputDecorator(
    decoration: InputDecoration(
      labelText: label, border: const OutlineInputBorder(),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(
      value: value, isExpanded: true, isDense: true, items: choices,
      onChanged: (next) { if (next != null) change(next); },
    )),
  ));

  Widget _titleList(BuildContext context, List<MediaFlowTitle> titles,
      Map<String, MediaFlowCategory> categories, double width) {
    if (_view == NativeLibraryView.list || _view == NativeLibraryView.compact) {
      return ListView.builder(
        key: ValueKey('library-' + _view.name),
        itemCount: titles.length,
        itemBuilder: (context, index) {
          final title = titles[index];
          final cat = categories[title.categoryId];
          final compact = _view == NativeLibraryView.compact;
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: () => _details(context, title, cat, _cacheCatalog!),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.all(compact ? 8 : 12),
                child: Row(children: [
                  MediaFlowCover(url: title.coverUrl,
                    width: compact ? 38 : 52, height: compact ? 52 : 72),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.title, maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(cat?.name ?? title.categoryId,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                      Text(_statusName(title.status) + ' · ' +
                        _capitalize(title.priority) + ' · ' + _progress(title),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                  )),
                  const Icon(Icons.chevron_right, size: 20),
                ]),
              ),
            ),
          );
        },
      );
    }

    final columns = width >= 1050 ? 6 : width >= 790 ? 5
        : width >= 590 ? 4 : width >= 380 ? 3 : 2;
    final coverOnly = _view == NativeLibraryView.covers;
    return GridView.builder(
      key: ValueKey('library-' + _view.name),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns, crossAxisSpacing: 10, mainAxisSpacing: 10,
        childAspectRatio: coverOnly ? 0.70
          : _view == NativeLibraryView.cards ? 0.62 : 0.55,
      ),
      itemCount: titles.length,
      itemBuilder: (context, index) {
        final title = titles[index];
        return InkWell(
          onTap: () => _details(context, title, categories[title.categoryId], _cacheCatalog!),
          borderRadius: BorderRadius.circular(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: MediaFlowCover(
              url: title.coverUrl, width: double.infinity, height: double.infinity)),
            if (!coverOnly) ...[
              const SizedBox(height: 4),
              Text(title.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              if (_view == NativeLibraryView.cards)
                Text(_progress(title), maxLines: 1,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ]),
        );
      },
    );
  }

  Widget _pager(BuildContext context, int page, int pages) => Row(children: [
    IconButton(
      tooltip: 'Previous page',
      onPressed: page == 0 ? null : () => setState(() => _page = page - 1),
      icon: const Icon(Icons.chevron_left),
    ),
    Expanded(child: Text('Page ' + (page + 1).toString() + ' of ' + pages.toString(),
      textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall)),
    IconButton(
      tooltip: 'Next page',
      onPressed: page + 1 >= pages ? null : () => setState(() => _page = page + 1),
      icon: const Icon(Icons.chevron_right),
    ),
    DropdownButton<int>(
      value: _perPage, isDense: true,
      items: const [
        DropdownMenuItem(value: 20, child: Text('20')),
        DropdownMenuItem(value: 50, child: Text('50')),
        DropdownMenuItem(value: 100, child: Text('100')),
      ],
      onChanged: (next) => setState(() { _perPage = next ?? 50; _page = 0; }),
    ),
  ]);

  void _details(BuildContext context, MediaFlowTitle title,
      MediaFlowCategory? cat, MediaFlowCatalog catalog) {
    widget.workspace?.observe(catalog);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: FractionallySizedBox(
        heightFactor: 0.75,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MediaFlowCover(url: title.coverUrl, width: 90, height: 128),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(cat?.name ?? title.categoryId),
                  Text(_statusName(title.status)),
                  Text('Priority: ' + _capitalize(title.priority)),
                ],
              )),
            ]),
            const SizedBox(height: 20),
            Text('Progress: ' + _progress(title)),
            if (title.rating != null) Text('Rating: ' + title.rating.toString()),
            if (title.tags.isNotEmpty) Text('Tags: ' + title.tags.join(', ')),
            if (title.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(title.description),
            ],
            if (title.seasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Seasons', style: Theme.of(context).textTheme.titleMedium),
              for (final season in title.seasons)
                ListTile(title: Text(season.name),
                  trailing: Text(_number(season.progress) + ' / ' + _number(season.total))),
            ],
            const SizedBox(height: 16),
            if (widget.workspace != null) ...[
              const Text('Cloud Library remains read-only. You can keep '
                  'a temporary on-device draft for review; no save occurs.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.workspace!.stale ? null : () {
                  Navigator.pop(sheetContext);
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => NativeTitleDraftSheet(
                      catalog: catalog, title: title,
                      workspace: widget.workspace!,
                    ),
                  );
                },
                icon: const Icon(Icons.edit_note),
                label: const Text('Draft changes locally'),
              ),
              if (widget.workspace!.titleDraft(title.id) != null)
                const Text('Local draft exists; inspect it in Settings.'),
              if (widget.workspace!.stale)
                const Text('Source changed. Discard stale drafts in Settings.'),
            ] else
              const Text('Read-only preview. Editing requires verified cloud synchronization.'),
          ],
        ),
      )),
    );
  }
}

class MediaFlowCover extends StatelessWidget {
  const MediaFlowCover({super.key, required this.url,
    required this.width, required this.height});
  final String url;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url);
    final Widget image;
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      image = Image.network(url, width: width, height: height,
        fit: BoxFit.cover,
        errorBuilder: (context, error, trace) => _placeholder());
    } else {
      image = _placeholder();
    }
    return ClipRRect(borderRadius: BorderRadius.circular(9),
      child: SizedBox(width: width, height: height, child: image));
  }

  Widget _placeholder() => const ColoredBox(
    color: MediaFlowColors.raised,
    child: Center(child: Icon(Icons.movie_outlined, color: MediaFlowColors.muted)),
  );
}

String _number(double? n) => n == null ? '?'
    : n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
String _progress(MediaFlowTitle title) =>
    _number(title.progress) + ' / ' + _number(title.total);
String _capitalize(String value) => value.isEmpty ? ''
    : value[0].toUpperCase() + value.substring(1);
String _statusName(String status) {
  switch (status) {
    case 'active': return 'Watching / Reading';
    case 'paused': return 'On Hold';
    case 'completed': return 'Completed';
    case 'planned': return 'Plan to Watch';
    case 'dropped': return 'Dropped';
    default: return _capitalize(status);
  }
}
String _viewName(NativeLibraryView view) {
  switch (view) {
    case NativeLibraryView.list: return 'List';
    case NativeLibraryView.compact: return 'Compact';
    case NativeLibraryView.cards: return 'Cards';
    case NativeLibraryView.covers: return 'Covers';
    case NativeLibraryView.coversWithTitles: return 'Covers + Titles';
  }
}
String _sortName(LibrarySort sort) {
  switch (sort) {
    case LibrarySort.alphabetical: return 'Title A–Z';
    case LibrarySort.alphabeticalReverse: return 'Title Z–A';
    case LibrarySort.progressHigh: return 'Most progress';
    case LibrarySort.progressLow: return 'Least progress';
    case LibrarySort.ratingHigh: return 'Highest rated';
    case LibrarySort.priorityHigh: return 'Highest priority';
    case LibrarySort.recentlyAdded: return 'Recently added';
  }
}
