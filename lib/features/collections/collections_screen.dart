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
  final search = TextEditingController();
  String query = '';
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
      final byId = {for (final item in data.library) item.id: item};
      final collections = data.collections.where((item) =>
          item.title.toLowerCase().contains(query.toLowerCase())).toList();
      final selected = opened == null ? null
          : data.collections.where((item) => item.id == opened).firstOrNull;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (selected != null) IconButton(
            tooltip: 'Back to Collections',
            onPressed: () => setState(() => opened = null),
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
              '${selected.resolvedTitles(byId).length} available in Library'),
          const SizedBox(height: 12),
        ],
        Expanded(child: selected != null
          ? _titles(selected.resolvedTitles(byId))
          : collections.isEmpty
            ? Center(child: Text(data.collections.isEmpty
                ? 'No collections yet.' : 'No matching collections.'))
            : ListView.builder(
                itemCount: collections.length,
                itemBuilder: (context, index) {
                  final collection = collections[index];
                  final resolved = collection.resolvedTitles(byId);
                  return Card(child: ListTile(
                    leading: collection.coverUrl.isNotEmpty
                        ? Image.network(collection.coverUrl, width: 45, height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
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
                            '${collection.progressPercent(byId).toStringAsFixed(0)}% progress'),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => opened = collection.id),
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
                      errorBuilder: (_, _, _) => const Icon(Icons.book_outlined))
                  : const Icon(Icons.book_outlined),
              title: Text(item.title),
              subtitle: Text('${item.status} · ${item.progress.toStringAsFixed(0)}'
                  '/${item.total?.toStringAsFixed(0) ?? "?"} · ${item.priority}'),
            ));
          },
        );
}
