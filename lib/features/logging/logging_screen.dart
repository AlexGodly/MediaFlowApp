import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';

/// Native logging workspace preview. Submission remains disabled until the
/// website's XP, history and cloud merge transaction contract is ported.
class LoggingScreen extends StatefulWidget {
  const LoggingScreen({super.key, required this.repository});
  final MediaFlowLibraryRepository repository;
  @override
  State<LoggingScreen> createState() => _LoggingScreenState();
}
class _LoggingScreenState extends State<LoggingScreen> {
  late Future<MediaFlowCatalog> future;
  final search = TextEditingController();
  String query = '', categoryId = '', status = '';
  int limit = 50;
  @override
  void initState() { super.initState(); future = widget.repository.load(); }
  @override
  void dispose() { search.dispose(); super.dispose(); }
  void refresh() => setState(() => future = widget.repository.reload());

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaFlowCatalog>(
    future: future, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: FilledButton(onPressed: refresh,
            child: const Text('Could not load Logging library — retry')));
      }
      final data = snapshot.requireData;
      final matches = data.library.where((title) =>
          (query.isEmpty || title.searchText.contains(query.toLowerCase())) &&
          (categoryId.isEmpty || title.categoryId == categoryId) &&
          (status.isEmpty || title.status == status)).toList(growable: false);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Logging', style: Theme.of(context).textTheme.headlineMedium),
              const Text('Browse Library · Submission not enabled'),
            ])),
          IconButton(onPressed: refresh, tooltip: 'Refresh Logging Library',
              icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 10),
        if (data.sessionActive && data.currentTask != null)
          Card(child: ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(data.categoryById[data.currentTask!.categoryId]?.name ??
                data.currentTask!.categoryId),
            subtitle: Text('Current target: '
                '${data.currentTask!.low.toStringAsFixed(0)}–'
                '${data.currentTask!.high.toStringAsFixed(0)} '
                '${data.currentTask!.unit}'),
          )),
        const SizedBox(height: 10),
        TextField(controller: search,
          decoration: const InputDecoration(
            labelText: 'Search Library titles',
            border: OutlineInputBorder(), prefixIcon: Icon(Icons.search)),
          onChanged: (value) => setState(() { query = value.trim(); limit = 50; }),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(width: 210, child: DropdownButtonFormField<String>(
            value: categoryId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category',
                border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: '', child: Text('All categories')),
              for (final category in data.categories)
                DropdownMenuItem(value: category.id,
                    child: Text(category.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) => setState(() {
              categoryId = value ?? ''; limit = 50;
            }),
          )),
          SizedBox(width: 190, child: DropdownButtonFormField<String>(
            value: status, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status',
                border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: '', child: Text('All statuses')),
              for (final item in data.library.map((title) => title.status).toSet())
                DropdownMenuItem(value: item, child: Text(item,
                    overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) => setState(() {
              status = value ?? ''; limit = 50;
            }),
          )),
        ]),
        const SizedBox(height: 10),
        Text('Showing ${matches.length < limit ? matches.length : limit}'
            ' of ${matches.length} matching titles'),
        const SizedBox(height: 8),
        Expanded(child: matches.isEmpty
          ? const Center(child: Text('No matching titles.'))
          : ListView.builder(
              itemCount: matches.length < limit ? matches.length : limit,
              itemBuilder: (context, index) {
                final title = matches[index];
                return Card(child: ListTile(
                  leading: const Icon(Icons.book_outlined),
                  title: Text(title.title),
                  subtitle: Text('${title.status} · '
                    '${title.progress.toStringAsFixed(0)}/'
                    '${title.total?.toStringAsFixed(0) ?? "?"}'),
                  trailing: const Icon(Icons.visibility_outlined),
                  onTap: () => showModalBottomSheet<void>(
                    context: context, showDragHandle: true,
                    builder: (sheet) => SafeArea(child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(title.title,
                              style: Theme.of(sheet).textTheme.titleLarge),
                          Text('Current progress: ${title.progress.toStringAsFixed(0)}'
                              '/${title.total?.toStringAsFixed(0) ?? "?"}'),
                          Text('Status: ${title.status}'),
                          const SizedBox(height: 12),
                          const Text('Logging edits are disabled until '
                              'cross-device cloud conflict and XP/History '
                              'updates are validated.'),
                        ],
                      ),
                    )),
                  ),
                ));
              },
            )),
        if (limit < matches.length)
          TextButton(
            onPressed: () => setState(() => limit += 50),
            child: const Text('Show 50 more titles'),
          ),
      ]);
    },
  );
}
