import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';

/// The native planner mirrors the saved ordering, without mutating it.
class PersonalOrderScreen extends StatefulWidget {
  const PersonalOrderScreen({super.key, required this.repository});
  final MediaFlowLibraryRepository repository;
  @override
  State<PersonalOrderScreen> createState() => _PersonalOrderScreenState();
}
class _PersonalOrderScreenState extends State<PersonalOrderScreen> {
  late Future<MediaFlowCatalog> future;
  final search = TextEditingController();
  String query = '';
  String categoryId = '';
  @override
  void initState() { super.initState(); future = widget.repository.load(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }
  void refresh() => setState(() => future = widget.repository.reload());
  @override
  Widget build(BuildContext context) => FutureBuilder<MediaFlowCatalog>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: FilledButton(onPressed: refresh,
            child: const Text('Could not load Personal Order — retry')));
      }
      final data = snapshot.requireData;
      final byId = {for (final title in data.library) title.id: title};
      final ordered = [
        for (final id in data.personalOrderIds)
          if (byId[id] != null) byId[id]!,
      ];
      final filtered = ordered.where((title) =>
          (categoryId.isEmpty || title.categoryId == categoryId) &&
          (query.isEmpty || title.searchText.contains(query.toLowerCase())))
          .toList(growable: false);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Personal Order', style: Theme.of(context).textTheme.headlineMedium),
              const Text('Saved title sequence · Read-only'),
            ])),
          IconButton(onPressed: refresh, tooltip: 'Refresh Personal Order',
              icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 12),
        TextField(controller: search,
          decoration: const InputDecoration(
            labelText: 'Search your ordered titles',
            prefixIcon: Icon(Icons.search), border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => query = value.trim()),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: categoryId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Category', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: '', child: Text('All categories')),
            for (final category in data.categories)
              DropdownMenuItem(value: category.id,
                child: Text(category.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (value) => setState(() => categoryId = value ?? ''),
        ),
        const SizedBox(height: 10),
        Text('${filtered.length} of ${ordered.length} available titles'
            ' · ${data.personalOrderIds.length} saved references'),
        const SizedBox(height: 8),
        Expanded(child: filtered.isEmpty
            ? Center(child: Text(ordered.isEmpty
                ? 'No titles in your Personal Order yet.'
                : 'No titles match these filters.'))
            : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final title = filtered[index];
                  final position = data.personalOrderIds.indexOf(title.id) + 1;
                  return Card(child: ListTile(
                    leading: CircleAvatar(child: Text('$position')),
                    title: Text(title.title),
                    subtitle: Text(
                      '${data.categoryById[title.categoryId]?.name ?? title.categoryId}'
                      ' · ${title.status} · ${title.progress.toStringAsFixed(0)}'
                      '/${title.total?.toStringAsFixed(0) ?? "?"}'),
                  ));
                },
              )),
      ]);
    },
  );
}
