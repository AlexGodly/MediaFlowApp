// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_library_index.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_editing_workspace.dart';
import '../library/native_editing_sheet.dart';

/// Multi-title selection workspace. It is intentionally a read-only
/// preview: selections never create sessions, XP, cloud writes, or drafts.
class LoggingScreen extends StatefulWidget {
  const LoggingScreen({super.key, required this.repository, this.workspace});
  final MediaFlowLibraryRepository repository;
  final NativeEditingWorkspace? workspace;

  @override
  State<LoggingScreen> createState() => _LoggingScreenState();
}

class _LoggingScreenState extends State<LoggingScreen> {
  late Future<MediaFlowCatalog> future;
  final search = TextEditingController();
  Timer? _debounce;
  MediaFlowCatalog? _indexedCatalog;
  MediaFlowLibraryIndex? _index;
  final Set<String> _selectedIds = <String>{};
  String query = '', categoryId = '', status = '', priority = '';
  LibrarySort sort = LibrarySort.alphabetical;
  int limit = 50;

  @override
  void initState() {
    super.initState();
    future = widget.repository.load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void _filterChanged() => setState(() => limit = 50);
  void refresh() => setState(() {
    limit = 50;
    future = widget.repository.reload();
  });

  void _selectionChanged(String id, bool chosen) => setState(() {
    if (chosen) {
      _selectedIds.add(id);
    } else {
      _selectedIds.remove(id);
    }
  });

  void _reviewSelection(MediaFlowCatalog data) {
    final byId = {for (final item in data.library) item.id: item};
    final titles = [
      for (final id in _selectedIds)
        if (byId[id] != null) byId[id]!,
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.72,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Selection preview',
                      style: Theme.of(sheet).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text('${titles.length} selected Library titles'),
                  const SizedBox(height: 8),
                  const Text(
                    'Review only — this does not record progress, '
                    'update History or award XP. Cloud writing is disabled.',
                  ),
                ],
              ),
            ),
            Expanded(child: ListView.builder(
              itemCount: titles.length,
              itemBuilder: (context, index) {
                final item = titles[index];
                return ListTile(
                  title: Text(item.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${item.status} · ${item.progress.toStringAsFixed(0)}'
                      '/${item.total?.toStringAsFixed(0) ?? "?"}'),
                );
              },
            )),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton(
                onPressed: () => Navigator.pop(sheet),
                child: const Text('Close preview'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _details(BuildContext context, MediaFlowTitle title,
      MediaFlowCatalog catalog) {
    widget.workspace?.observe(catalog);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title.title, style: Theme.of(sheet).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Current progress: ${title.progress.toStringAsFixed(0)}'
                '/${title.total?.toStringAsFixed(0) ?? "?"}'),
            Text('Status: ${title.status}'),
            Text('Priority: ${title.priority}'),
            const SizedBox(height: 12),
            const Text(
              'Cloud logging, History writes and XP awards remain disabled '
              'until cross-device safety and website side effects are verified.',
            ),
            if (widget.workspace != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: widget.workspace!.stale ? null : () {
                  Navigator.pop(sheet);
                  showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => NativeLogDraftSheet(
                      catalog: catalog, title: title,
                      workspace: widget.workspace!,
                    ),
                  );
                },
                icon: const Icon(Icons.playlist_add_outlined),
                label: const Text('Draft logging locally'),
              ),
              if (widget.workspace!.logDraft(title.id) != null)
                const Text('Local logging draft exists. See Settings.'),
              if (widget.workspace!.stale)
                const Text('Snapshot changed. Discard stale drafts in Settings.'),
            ],
          ],
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaFlowCatalog>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: FilledButton(
          onPressed: refresh,
          child: const Text('Could not load Logging Library — retry'),
        ));
      }
      final data = snapshot.requireData;
      if (!identical(_indexedCatalog, data) || _index == null) {
        _indexedCatalog = data;
        _index = MediaFlowLibraryIndex(data.library);
        final availableIds = {for (final item in data.library) item.id};
        _selectedIds.removeWhere((id) => !availableIds.contains(id));
      }
      final matches = _index!.query(MediaFlowLibraryFilter(
        search: query, categoryId: categoryId, status: status,
        priority: priority, sort: sort,
      ));
      final visible = matches.take(limit).toList(growable: false);
      final allVisibleSelected = visible.isNotEmpty &&
          visible.every((item) => _selectedIds.contains(item.id));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Logging', style: Theme.of(context).textTheme.headlineMedium),
                const Text('Native title selection · Source-derived History previews (no submission)'),
              ],
            )),
            IconButton(
              onPressed: refresh,
              tooltip: 'Refresh Logging Library',
              icon: const Icon(Icons.refresh),
            ),
          ]),
          if (widget.workspace != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Local drafts: ${widget.workspace!.logCount} log plans '
                  '· History entries submitted: 0 · XP awarded: 0',
                key: const Key('logging-local-draft-summary')),
            ),
          if (data.sessionActive && data.currentTask != null) ...[
            const SizedBox(height: 8),
            Card(child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(
                data.categoryById[data.currentTask!.categoryId]?.name ??
                    data.currentTask!.categoryId,
              ),
              subtitle: Text(
                'Current target: '
                '${data.currentTask!.low.toStringAsFixed(0)}–'
                '${data.currentTask!.high.toStringAsFixed(0)} '
                '${data.currentTask!.unit}',
              ),
            )),
          ],
          const SizedBox(height: 10),
          TextField(
            key: const Key('logging-library-search'),
            controller: search,
            decoration: const InputDecoration(
              labelText: 'Search Library titles',
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 180), () {
                if (!mounted) return;
                query = value;
                _filterChanged();
              });
            },
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth >= 850
                ? (constraints.maxWidth - 24) / 4
                : constraints.maxWidth >= 470
                    ? (constraints.maxWidth - 8) / 2
                    : constraints.maxWidth;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              _dropdown<String>(w, 'Category', categoryId, [
                const DropdownMenuItem(value: '', child: Text('All categories')),
                for (final category in data.categories)
                  DropdownMenuItem(value: category.id, child: Text(
                    category.name, overflow: TextOverflow.ellipsis,
                  )),
              ], (v) { categoryId = v; _filterChanged(); }),
              _dropdown<String>(w, 'Status', status, [
                const DropdownMenuItem(value: '', child: Text('All statuses')),
                for (final value in data.library.map((t) => t.status).toSet())
                  DropdownMenuItem(value: value, child: Text(value,
                      overflow: TextOverflow.ellipsis)),
              ], (v) { status = v; _filterChanged(); }),
              _dropdown<String>(w, 'Priority', priority, const [
                DropdownMenuItem(value: '', child: Text('All priorities')),
                DropdownMenuItem(value: 'high', child: Text('High')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'low', child: Text('Low')),
              ], (v) { priority = v; _filterChanged(); }),
              _dropdown<LibrarySort>(w, 'Display sort', sort, [
                for (final value in LibrarySort.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_sortLabel(value),
                        overflow: TextOverflow.ellipsis),
                  ),
              ], (v) { sort = v; _filterChanged(); }),
            ]);
          }),
          const SizedBox(height: 8),
          Text('Showing ${visible.length} of ${matches.length} titles '
              '· ${_selectedIds.length} selected'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              onPressed: visible.isEmpty ? null : () => setState(() {
                if (allVisibleSelected) {
                  _selectedIds.removeAll(visible.map((item) => item.id));
                } else {
                  _selectedIds.addAll(visible.map((item) => item.id));
                }
              }),
              icon: Icon(allVisibleSelected
                  ? Icons.deselect : Icons.select_all),
              label: Text(allVisibleSelected
                  ? 'Deselect visible' : 'Select visible'),
            ),
            OutlinedButton.icon(
              onPressed: _selectedIds.isEmpty ? null : () =>
                  setState(() => _selectedIds.clear()),
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear selection'),
            ),
            FilledButton.tonalIcon(
              onPressed: _selectedIds.isEmpty ? null :
                  () => _reviewSelection(data),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview selection'),
            ),
          ]),
          const SizedBox(height: 6),
          Expanded(child: matches.isEmpty
              ? const Center(child: Text('No matching titles.'))
              : ListView.builder(
                  key: const Key('logging-browser-titles'),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final title = visible[index];
                    return Card(child: ListTile(
                      leading: Checkbox(
                        value: _selectedIds.contains(title.id),
                        onChanged: (value) =>
                            _selectionChanged(title.id, value ?? false),
                      ),
                      title: Text(title.title, maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${title.status} · ${title.priority} · '
                        '${title.progress.toStringAsFixed(0)}'
                        '/${title.total?.toStringAsFixed(0) ?? "?"}',
                      ),
                      trailing: IconButton(
                        tooltip: 'View title details',
                        icon: const Icon(Icons.info_outline),
                        onPressed: () => _details(context, title, data),
                      ),
                      onTap: () => _selectionChanged(
                          title.id, !_selectedIds.contains(title.id)),
                    ));
                  },
                )),
          if (limit < matches.length)
            TextButton(
              onPressed: () => setState(() => limit += 50),
              child: const Text('Show 50 more titles'),
            ),
          const Text(
            'Selections and local logging drafts are temporary and are not saved or synchronized.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    },
  );

  Widget _dropdown<T>(
    double width, String label, T value,
    List<DropdownMenuItem<T>> items, ValueChanged<T> changed,
  ) => SizedBox(width: width, child: DropdownButtonFormField<T>(
    initialValue: value, isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
    items: items,
    onChanged: (next) {
      if (next != null) changed(next);
    },
  ));
}

String _sortLabel(LibrarySort sort) {
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
