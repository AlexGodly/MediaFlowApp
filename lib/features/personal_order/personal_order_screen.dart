import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import 'personal_order_browser.dart';
import 'native_m42_mixed_queue_panel.dart';

/// Saved sequence is authoritative. Sorting here only affects display.
class PersonalOrderScreen extends StatefulWidget {
  const PersonalOrderScreen({super.key, required this.repository});
  final MediaFlowLibraryRepository repository;

  @override
  State<PersonalOrderScreen> createState() => _PersonalOrderScreenState();
}

class _PersonalOrderScreenState extends State<PersonalOrderScreen> {
  late Future<MediaFlowCatalog> future;
  MediaFlowCatalog? _indexedCatalog;
  PersonalOrderBrowser? _browser;
  final search = TextEditingController();
  Timer? _debounce;
  String query = '', categoryId = '', status = '', priority = '';
  PersonalOrderDisplaySort sort = PersonalOrderDisplaySort.saved;
  int page = 0;
  bool mixedQueueMode = false;

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

  void _changed() => setState(() => page = 0);
  void refresh() => setState(() {
    page = 0;
    future = widget.repository.reload();
  });

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
          child: const Text('Could not load Personal Order — retry'),
        ));
      }
      final data = snapshot.requireData;
      if (!identical(_indexedCatalog, data) || _browser == null) {
        _indexedCatalog = data;
        _browser = PersonalOrderBrowser(data);
      }
      final browser = _browser!;
      final filtered = browser.browse(
        search: query, categoryId: categoryId,
        status: status, priority: priority, sort: sort,
      );
      const perPage = 50;
      final pages = filtered.isEmpty ? 1 :
          (filtered.length + perPage - 1) ~/ perPage;
      final current = page.clamp(0, pages - 1);
      final visible = filtered.skip(current * perPage)
          .take(perPage).toList(growable: false);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Personal Order',
                    style: Theme.of(context).textTheme.headlineMedium),
                const Text('Saved title sequence · Read-only display'),
              ],
            )),
            IconButton(
              onPressed: refresh,
              tooltip: 'Refresh Personal Order',
              icon: const Icon(Icons.refresh),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing:8,runSpacing:8,children:[
            ChoiceChip(
              key:const Key('m42-direct-mode'),
              label:const Text('Direct ordered titles'),
              selected:!mixedQueueMode,
              onSelected:(_)=>setState(()=>mixedQueueMode=false)),
            ChoiceChip(
              key:const Key('m42-mixed-mode'),
              label:const Text('Mixed title & Collection queues'),
              selected:mixedQueueMode,
              onSelected:(_)=>setState(()=>mixedQueueMode=true)),
          ]),
          const SizedBox(height:12),
          if (mixedQueueMode)
            Expanded(child:NativeM42MixedQueuePanel(
              key:ValueKey(data),
              catalog:data)),
          if (!mixedQueueMode) ...[
          TextField(
            key: const Key('personal-order-search'),
            controller: search,
            decoration: const InputDecoration(
              labelText: 'Search your ordered titles',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 180), () {
                if (!mounted) return;
                query = value;
                _changed();
              });
            },
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 740
                ? (constraints.maxWidth - 24) / 4
                : constraints.maxWidth >= 450
                    ? (constraints.maxWidth - 8) / 2
                    : constraints.maxWidth;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              _dropdown<String>(
                width, 'Category', categoryId,
                [
                  const DropdownMenuItem(
                      value: '', child: Text('All categories')),
                  for (final category in data.categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                (value) { categoryId = value; _changed(); },
              ),
              _dropdown<String>(
                width, 'Status', status,
                const [
                  DropdownMenuItem(value: '', child: Text('All statuses')),
                  DropdownMenuItem(value: 'active', child: Text('In progress')),
                  DropdownMenuItem(value: 'paused', child: Text('On hold')),
                  DropdownMenuItem(value: 'completed', child: Text('Completed')),
                  DropdownMenuItem(value: 'planned', child: Text('Planned')),
                  DropdownMenuItem(value: 'dropped', child: Text('Dropped')),
                ],
                (value) { status = value; _changed(); },
              ),
              _dropdown<String>(
                width, 'Priority', priority,
                const [
                  DropdownMenuItem(value: '', child: Text('All priorities')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                ],
                (value) { priority = value; _changed(); },
              ),
              _dropdown<PersonalOrderDisplaySort>(
                width, 'Display sort', sort,
                const [
                  DropdownMenuItem(
                    value: PersonalOrderDisplaySort.saved,
                    child: Text('Saved order'),
                  ),
                  DropdownMenuItem(
                    value: PersonalOrderDisplaySort.alphabetical,
                    child: Text('Title A–Z'),
                  ),
                  DropdownMenuItem(
                    value: PersonalOrderDisplaySort.progress,
                    child: Text('Most progress'),
                  ),
                  DropdownMenuItem(
                    value: PersonalOrderDisplaySort.priority,
                    child: Text('Priority'),
                  ),
                ],
                (value) { sort = value; _changed(); },
              ),
            ]);
          }),
          const SizedBox(height: 10),
          Text(
            '${filtered.length} of ${browser.availableCount} available titles'
            ' · ${data.personalOrderIds.length} saved references'
            '${browser.missingReferences > 0 ? " · ${browser.missingReferences} missing from Library" : ""}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Expanded(child: filtered.isEmpty
              ? Center(child: Text(browser.availableCount == 0
                  ? 'No available titles in your Personal Order yet.'
                  : 'No titles match the current filters.'))
              : ListView.builder(
                  key: const Key('personal-order-entries'),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final entry = visible[index];
                    final title = entry.title;
                    return Card(child: ListTile(
                      leading: CircleAvatar(
                          child: Text('${entry.position}')),
                      title: Text(title.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${data.categoryById[title.categoryId]?.name ?? title.categoryId}'
                        ' · ${title.status} · ${title.priority}'
                        ' · ${title.progress.toStringAsFixed(0)}'
                        '/${title.total?.toStringAsFixed(0) ?? "?"}',
                      ),
                    ));
                  },
                )),
          if (filtered.isNotEmpty)
            Row(children: [
              IconButton(
                tooltip: 'Previous Personal Order page',
                onPressed: current == 0 ? null :
                    () => setState(() => page = current - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(child: Text('Page ${current + 1} of $pages',
                  textAlign: TextAlign.center)),
              IconButton(
                tooltip: 'Next Personal Order page',
                onPressed: current + 1 >= pages ? null :
                    () => setState(() => page = current + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
          const Text(
            'This view never modifies your saved order. Reordering and '
            'cloud editing remain disabled until synchronization is safe.',
            textAlign: TextAlign.center,
          ),
          ],
        ],
      );
    },
  );

  Widget _dropdown<T>(double width, String label, T value,
      List<DropdownMenuItem<T>> items, ValueChanged<T> changed) =>
      SizedBox(width: width, child: DropdownButtonFormField<T>(
        key: ValueKey('personal-order-${label.toLowerCase().replaceAll(" ", "-")}'),
        initialValue: value,
        isExpanded: true,
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
