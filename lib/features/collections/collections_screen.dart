import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key, required this.repository});
  final MediaFlowLibraryRepository repository;
  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  late Future<MediaFlowCatalog> future;
  MediaFlowCatalog? _indexedCatalog;
  Map<String, MediaFlowTitle> _byId = const {};
  Map<String, List<MediaFlowTitle>> _resolved = const {};
  Map<String, double> _progress = const {};

  void _index(MediaFlowCatalog catalog) {
    if (identical(_indexedCatalog, catalog)) return;
    _indexedCatalog = catalog;
    _byId = {for (final title in catalog.library) title.id: title};
    _resolved = {
      for (final collection in catalog.collections)
        collection.id: collection.resolvedTitles(_byId),
    };
    _progress = {
      for (final collection in catalog.collections)
        collection.id: collection.progressPercent(_byId),
    };
  }
  final search = TextEditingController();
  String query = '';
  String memberQuery = '';
  String memberStatus = '';
  String memberSort = 'saved';
  String? opened;
  @override
  void initState() {
    super.initState();
    future = widget.repository.load();
  }
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }
  void refresh() => setState(() => future = widget.repository.reload());

  List<MediaFlowTitle> _visibleMembers(String collectionId) {
    final needle = memberQuery.trim().toLowerCase();
    final filtered = [
      for (final title in _resolved[collectionId] ?? const <MediaFlowTitle>[])
        if ((needle.isEmpty || title.title.toLowerCase().contains(needle)) &&
            (memberStatus.isEmpty || title.status == memberStatus))
          title,
    ];
    if (memberSort == 'alphabetical') {
      filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (memberSort == 'progress') {
      filtered.sort((a, b) => b.progress.compareTo(a.progress));
    } else if (memberSort == 'priority') {
      const weights = {'high': 0, 'medium': 1, 'low': 2};
      filtered.sort((a, b) => (weights[a.priority] ?? 3).compareTo(weights[b.priority] ?? 3));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaFlowCatalog>(
    future: future,
    builder: (context, result) {
      if (result.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (result.hasError) {
        return Center(child: FilledButton(onPressed: refresh,
            child: const Text('Could not load Collections — retry')));
      }
      final data = result.requireData;
      _index(data);
      final collections = data.collections.where((item) =>
          item.title.toLowerCase().contains(query.toLowerCase())).toList();
      final selected = opened == null ? null
          : data.collections.where((item) => item.id == opened).firstOrNull;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (selected != null) IconButton(
            tooltip: 'Back to Collections',
            onPressed: () => setState(() { opened = null; memberQuery = ''; memberStatus = ''; memberSort = 'saved'; }),
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(selected?.title ?? 'Collections',
                  style: Theme.of(context).textTheme.headlineMedium,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const Text('Your existing collections · Read-only'),
            ],
          )),
          IconButton(onPressed: refresh, tooltip: 'Refresh Collections',
              icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 12),
        if (selected == null) ...[
          TextField(controller: search, decoration: const InputDecoration(
            border: OutlineInputBorder(), isDense: true,
            prefixIcon: Icon(Icons.search), labelText: 'Find a collection',
          ), onChanged: (value) => setState(() => query = value)),
          const SizedBox(height: 12),
        ] else ...[
          Text(selected.description),
          const SizedBox(height: 8),
          Text('${selected.titleIds.length} saved title references · '
              '${(_resolved[selected.id]?.length ?? 0)} available in Library'),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search titles in this collection',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(), isDense: true,
            ),
            onChanged: (value) => setState(() => memberQuery = value),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 8, children: [
            DropdownButton<String>(
              value: memberStatus,
              items: const [
                DropdownMenuItem(value: '', child: Text('All statuses')),
                DropdownMenuItem(value: 'active', child: Text('In progress')),
                DropdownMenuItem(value: 'paused', child: Text('On hold')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'dropped', child: Text('Dropped')),
                DropdownMenuItem(value: 'planned', child: Text('Planned')),
              ],
              onChanged: (value) => setState(() => memberStatus = value ?? ''),
            ),
            DropdownButton<String>(
              value: memberSort,
              items: const [
                DropdownMenuItem(value: 'saved', child: Text('Saved order')),
                DropdownMenuItem(value: 'alphabetical', child: Text('Title A–Z')),
                DropdownMenuItem(value: 'progress', child: Text('Most progress')),
                DropdownMenuItem(value: 'priority', child: Text('Priority')),
              ],
              onChanged: (value) => setState(() => memberSort = value ?? 'saved'),
            ),
          ]),
          Text('${_visibleMembers(selected.id).length} matching titles',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
        Expanded(child: selected != null
          ? _titles(_visibleMembers(selected.id))
          : collections.isEmpty
            ? Center(child: Text(data.collections.isEmpty
                ? 'No collections yet.' : 'No matching collections.'))
            : ListView.builder(
                itemCount: collections.length,
                itemBuilder: (context, index) {
                  final collection = collections[index];
                  final resolved = _resolved[collection.id] ?? const <MediaFlowTitle>[];
                  return Card(child: ListTile(
                    leading: collection.coverUrl.isNotEmpty
                        ? Image.network(collection.coverUrl, width: 45, height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.collections_bookmark_outlined))
                        : const Icon(Icons.collections_bookmark_outlined),
                    title: Text(collection.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (collection.description.isNotEmpty)
                          Text(collection.description, maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        Text('${resolved.length} titles · '
                            '${(_progress[collection.id] ?? 0).toStringAsFixed(0)}% progress'),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() { opened = collection.id; memberQuery = ''; memberStatus = ''; memberSort = 'saved'; }),
                  ));
                },
              )),
      ]);
    },
  );

  Widget _titles(List<MediaFlowTitle> titles) => titles.isEmpty
      ? const Center(child: Text('No available Library titles in this collection.'))
      : ListView.builder(
          itemCount: titles.length,
          itemBuilder: (context, index) {
            final item = titles[index];
            return Card(child: ListTile(
              leading: item.coverUrl.isNotEmpty
                  ? Image.network(item.coverUrl, width: 42, height: 58,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.book_outlined))
                  : const Icon(Icons.book_outlined),
              title: Text(item.title),
              subtitle: Text('${item.status} · ${item.progress.toStringAsFixed(0)}'
                  '/${item.total?.toStringAsFixed(0) ?? "?"} · ${item.priority}'),
            ));
          },
        );
}
