import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import 'personal_order_browser.dart';
import 'native_m42_mixed_queue_panel.dart';
import '../../services/native_m44_personal_order_plan.dart';
import 'native_m44_assignment_planner.dart';
import 'native_m45_direct_title_planner.dart';

/// Saved sequence is authoritative. Sorting here only affects display.
class PersonalOrderScreen extends StatefulWidget {
  const PersonalOrderScreen({super.key, required this.repository,
    this.plan, this.currentOwnerId = ''});
  final MediaFlowLibraryRepository repository;
  final NativeM44PersonalOrderPlan? plan;
  final String currentOwnerId;

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
  bool localPlanMode = false;
  bool directPlanMode = false;
  bool previewLocalPlan = false;
  bool mixedEditMode = false;

  @override
  void initState() {
    super.initState();
    future = widget.repository.load();
    widget.plan?.addListener(_onPlanChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    widget.plan?.removeListener(_onPlanChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PersonalOrderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(oldWidget.plan!=widget.plan) {
      oldWidget.plan?.removeListener(_onPlanChanged);
      widget.plan?.addListener(_onPlanChanged);
      previewLocalPlan=false;
      localPlanMode=false;
      directPlanMode=false;
      mixedEditMode=false;
    }
  }

  void _onPlanChanged() {
    if(mounted) setState(() {});
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
      widget.plan?.observe(data,currentOwnerId:widget.currentOwnerId);
      final plan=widget.plan;
      final editingMixed=mixedQueueMode && !localPlanMode &&
          !directPlanMode && mixedEditMode && plan?.canEdit==true;
      final showLocalPreview=plan!=null && plan.canEdit &&
          (editingMixed || (previewLocalPlan && plan.hasChanges));
      final displayed=showLocalPreview?plan.previewCatalog():data;
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
              onSelected:(_)=>setState(() {
                mixedQueueMode=false;localPlanMode=false;
                directPlanMode=false;
              })), 
            ChoiceChip(
              key:const Key('m42-mixed-mode'),
              label:const Text('Mixed title & Collection queues'),
              selected:mixedQueueMode,
              onSelected:(_)=>setState(() {
                mixedQueueMode=true;localPlanMode=false;
                directPlanMode=false;
              })),
            if(plan!=null)
              ChoiceChip(
                key:const Key('m44-plan-mode'),
                label:const Text('Manage assignments locally'),
                selected:localPlanMode,
                onSelected:(_)=>setState(() {
                  localPlanMode=true;directPlanMode=false;
                })),
            if(plan!=null)
              ChoiceChip(
                key:const Key('m45-plan-mode'),
                label:const Text('Manage direct titles locally'),
                selected:directPlanMode,
                onSelected:(_)=>setState(() {
                  directPlanMode=true;localPlanMode=false;
                })),  
          ]),
          const SizedBox(height:12),
          if(mixedQueueMode && !localPlanMode && !directPlanMode &&
              plan!=null)
            SwitchListTile(
              key:const Key('m47-edit-toggle'),
              dense:true,
              title:const Text('Edit mixed queue locally'),
              subtitle:const Text('Device-only draft · direct titles and '
                'Collection outer slots · never writes to Supabase'),
              value:editingMixed,
              onChanged:plan.canEdit ? (value)=>setState(() {
                mixedEditMode=value;
                if(value) previewLocalPlan=true;
              }) : null),
          if(mixedQueueMode && !localPlanMode && !directPlanMode &&
              plan!=null && !plan.canEdit)
            Row(children:[
              const Expanded(child:Text('Queue draft quarantined: '
                'owner or authoritative snapshot changed.',
                key:Key('m47-stale-warning'))),
              TextButton(onPressed:plan.discard,
                child:const Text('Discard draft')),
            ]),
          if(mixedQueueMode && !localPlanMode && !directPlanMode &&
              !editingMixed && plan!=null &&
              plan.hasChanges && plan.canEdit)
            SwitchListTile(
              key:const Key('m44-preview-toggle'),
              dense:true,
              title:const Text('View local queue preview'),
              subtitle:const Text('Device only · not saved to cloud'),
              value:showLocalPreview,
              onChanged:(value)=>setState(()=>previewLocalPlan=value)),
          if (directPlanMode && plan!=null)
            Expanded(child:NativeM45DirectTitlePlanner(
              plan:plan,onPreview:()=>setState(() {
                previewLocalPlan=true;
                mixedQueueMode=true;
                directPlanMode=false;
                localPlanMode=false;
              }),
            )),
          if (localPlanMode && plan!=null)
            Expanded(child:NativeM44AssignmentPlanner(
              plan:plan,
              onPreview:()=>setState(() {
                previewLocalPlan=true;
                mixedQueueMode=true;
                localPlanMode=false;
                directPlanMode=false;
              }),
            )),
          if (mixedQueueMode && !localPlanMode && !directPlanMode)
            Expanded(child:NativeM42MixedQueuePanel(
              key:const ValueKey('m47-mixed-queue'),
              catalog:displayed,
              savedCatalog:showLocalPreview ? data : null,
              plan:editingMixed ? plan : null)),
          if (!mixedQueueMode && !localPlanMode && !directPlanMode) ...[
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
