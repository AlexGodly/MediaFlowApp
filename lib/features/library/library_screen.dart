// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_library_index.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_editing_workspace.dart';
import 'native_editing_sheet.dart';
import '../../services/native_m37_library_plan.dart';
import 'native_m37_library_plan_ui.dart';
import 'native_m38_title_details.dart';
import '../../design_system/mediaflow_theme.dart';
import '../../design_system/mediaflow_components.dart';

enum NativeLibraryView { list, compact, cards, covers, coversWithTitles }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.repository, this.workspace,
    this.changePlan});
  final MediaFlowLibraryRepository repository;
  final NativeEditingWorkspace? workspace;
  final NativeM37LibraryPlan? changePlan;
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
  bool _previewChanges = false, _selecting = false;
  final Set<String> _selectedIds = {};
  void _onPlanChange() {
    if (mounted) {
      setState(() {
      _cacheCatalog = null;
      _page = 0;
      _selectedIds.clear();
      });
    }
  }
  MediaFlowCatalog? _cacheCatalog;
  MediaFlowLibraryIndex? _libraryIndex;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.load();
    widget.changePlan?.addListener(_onPlanChange);
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.changePlan != widget.changePlan) {
      oldWidget.changePlan?.removeListener(_onPlanChange);
      widget.changePlan?.addListener(_onPlanChange);
      _previewChanges = false;
      _selectedIds.clear();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.changePlan?.removeListener(_onPlanChange);
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
    _selectedIds.clear();
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
        final authoritative = snapshot.data!;
        final plan = widget.changePlan;
        plan?.observe(authoritative);
        final previewActive = _previewChanges && plan != null &&
            !plan.stale && plan.hasChanges;
        final catalog = previewActive
            ? plan.previewCatalog() : authoritative;
        final matched = _results(catalog);
        final pages = matched.isEmpty ? 1 : (matched.length + _perPage - 1) ~/ _perPage;
        final page = _page.clamp(0, pages - 1);
        final start = page * _perPage;
        final visible = matched.skip(start).take(_perPage).toList(growable: false);
        final cats = catalog.categoryById;
        return LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MfPageHeader(
              title: 'Library',
              subtitle: catalog.library.length.toString() + ' saved titles',
              trailing: IconButton(
                tooltip: 'Refresh from cloud (read-only)',
                onPressed: _refresh, icon: const Icon(Icons.refresh),
              ),
            ),
            if (plan != null) ...[
              const SizedBox(height: 8),
              _draftControls(authoritative, visible, plan, previewActive),
            ],
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
                 ' of ' + matched.length.toString() +
                 (previewActive ? ' · LOCAL PREVIEW — NOT SAVED'
                     : ' · Cloud source — read-only'),
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
              onTap: () => _openTitle(context, title, cat, _cacheCatalog!),
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
                  if (_selecting)
                    Checkbox(
                      key: Key('m37-select-${title.id}'),
                      value: _selectedIds.contains(title.id),
                      onChanged: (v) => setState(() {
                        if (v == true) { _selectedIds.add(title.id); }
                        else { _selectedIds.remove(title.id); }
                      }),
                    )
                  else
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
          onTap: () => _openTitle(context, title, categories[title.categoryId], _cacheCatalog!),
          borderRadius: BorderRadius.circular(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_selecting)
              Align(alignment: Alignment.centerRight, child: Checkbox(
                key: Key('m37-select-${title.id}'),
                value: _selectedIds.contains(title.id),
                onChanged: (v) => setState(() {
                  if (v == true) { _selectedIds.add(title.id); }
                  else { _selectedIds.remove(title.id); }
                }),
              )),
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


  Widget _draftControls(MediaFlowCatalog source, List<MediaFlowTitle> visible,
      NativeM37LibraryPlan plan, bool previewActive) {
    return Card(child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('LOCAL LIBRARY CHANGE PLANNER',
          style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Text(plan.stale ? 'Snapshot refreshed. Local plan quarantined. '
            'Discard it before any new edit.'
          : '${plan.creationCount} create · ${plan.editCount} edit · '
            '${plan.deletionCount} delete pending · Never uploaded',
          key: const Key('m37-plan-count')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            key: const Key('m37-new-title'),
            onPressed: plan.stale || source.categories.isEmpty ? null
                : () => _openM37Form(source),
            icon: const Icon(Icons.add),
            label: const Text('Create local title')),
          OutlinedButton.icon(
            key: const Key('m37-review-plan'),
            onPressed: () => showModalBottomSheet<void>(
              context: context, showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => NativeM37PlanReview(plan: plan)),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Review local changes')),
          OutlinedButton.icon(
            key: const Key('m37-preview-toggle'),
            onPressed: !plan.hasChanges || plan.stale ? null
              : () => setState(() {
                _previewChanges = !_previewChanges;
                _cacheCatalog = null;
                _selectedIds.clear();
              }),
            icon: Icon(previewActive ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
            label: Text(previewActive ? 'Show cloud source' : 'Preview changes')),
          OutlinedButton.icon(
            key: const Key('m37-undo'),
            onPressed: !plan.stale && plan.canUndo ? plan.undo : null,
            icon: const Icon(Icons.undo),
            label: const Text('Undo')),
          OutlinedButton.icon(
            key: const Key('m37-redo'),
            onPressed: !plan.stale && plan.canRedo ? plan.redo : null,
            icon: const Icon(Icons.redo),
            label: const Text('Redo')),
          OutlinedButton.icon(
            key: const Key('m37-select-mode'),
            onPressed: plan.stale ? null : () => setState(() {
              _selecting = !_selecting;
              _selectedIds.clear();
            }),
            icon: const Icon(Icons.checklist_outlined),
            label: Text(_selecting ? 'Exit selection' : 'Bulk select')),
          if (_selecting) ...[
            TextButton.icon(
              key: const Key('m37-select-visible'),
              onPressed: () => setState(() {
                _selectedIds.addAll(visible.map((e)=>e.id));
              }),
              icon: const Icon(Icons.select_all),
              label: const Text('Select visible')),
            OutlinedButton.icon(
              key: const Key('m37-clear-selection'),
              onPressed: _selectedIds.isEmpty ? null
                : () => setState(() => _selectedIds.clear()),
              icon: const Icon(Icons.deselect_outlined),
              label: const Text('Deselect')),
            OutlinedButton.icon(
              key: const Key('m38-bulk-metadata'),
              onPressed: _selectedIds.isEmpty ? null : () {
                final selected = _selectedIds.toList(growable: false);
                showModalBottomSheet<void>(
                  context: context, showDragHandle: true,
                  isScrollControlled: true,
                  builder: (_) => NativeM38BulkMetadataSheet(
                    plan: plan, catalog: source, ids: selected),
                );
              },
              icon: const Icon(Icons.edit_note_outlined),
              label: Text('Batch edit metadata (${_selectedIds.length})')),
            FilledButton.icon(
              key: const Key('m37-bulk-delete'),
              onPressed: _selectedIds.isEmpty ? null
                : () => _confirmBulkDelete(plan),
              icon: const Icon(Icons.delete_outline),
              label: Text('Stage deletion (${_selectedIds.length})')),
          ],
        ]),
        if (previewActive) const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('PREVIEW ONLY — This is not your saved Library. '
            'Session History, Collections and XP still reflect cloud source.',
            key: Key('m37-preview-warning'))),
      ]),
    ));
  }

  void _openM37Form(MediaFlowCatalog source, {String? titleId}) {
    final plan = widget.changePlan;
    if (plan == null || plan.stale) { return; }
    showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (_) => NativeM37TitleForm(
        plan: plan, catalog: source, titleId: titleId),
    );
  }

  void _openTitle(BuildContext context, MediaFlowTitle title,
      MediaFlowCategory? cat, MediaFlowCatalog catalog) {
    final plan = widget.changePlan;
    if (_selecting) {
      setState(() {
        if (!_selectedIds.add(title.id)) { _selectedIds.remove(title.id); }
      });
      return;
    }
    _details(context, title, cat, catalog);
  }

  Future<void> _confirmBulkDelete(NativeM37LibraryPlan plan) async {
    final ids = _selectedIds.toList(growable: false);
    final referenceCount = ids.fold<int>(0,
      (sum,id)=>sum+plan.references(id));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Stage deletion of ${ids.length} titles?'),
        content: Text('This is only a local preview. Your cloud Library, '
            'History, XP and Personal Order remain unchanged. '
            '${referenceCount > 0 ? "These titles have $referenceCount "
             "related references that would require coordinated cleanup. " : ""}'
            'Undo or Restore can reverse the staged action.'),
        actions: [
          TextButton(onPressed: ()=>Navigator.pop(dialog,false),
            child: const Text('Cancel')),
          FilledButton(onPressed: ()=>Navigator.pop(dialog,true),
            child: const Text('Stage device-only deletion')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        plan.stageDelete(ids);
      } on StateError catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)));
        }
      } on FormatException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)));
        }
      }
    }
  }

  void _details(BuildContext context, MediaFlowTitle title,
      MediaFlowCategory? cat, MediaFlowCatalog catalog) {
    final plan = widget.changePlan;
    if (plan != null) {
      showModalBottomSheet<void>(
        context: context, showDragHandle: true, isScrollControlled: true,
        builder: (_) => NativeM38TitleDetails(
          title: title, catalog: plan.source ?? catalog, plan: plan),
      );
      return;
    }
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
