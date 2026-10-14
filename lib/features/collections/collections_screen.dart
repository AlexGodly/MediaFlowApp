import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_m40_collection_plan.dart';
import 'native_m40_collection_editor.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key, required this.repository, this.plan});
  final MediaFlowLibraryRepository repository;
  final NativeM40CollectionPlan? plan;
  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  late Future<MediaFlowCatalog> future;
  bool _preview = false;
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
    widget.plan?.addListener(_onPlanChange);
  }
  @override
  void dispose() {
    widget.plan?.removeListener(_onPlanChange);
    search.dispose();
    super.dispose();
  }
  @override
  void didUpdateWidget(covariant CollectionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan != widget.plan) {
      oldWidget.plan?.removeListener(_onPlanChange);
      widget.plan?.addListener(_onPlanChange);
      _preview = false;
      opened = null;
      _indexedCatalog = null;
    }
  }

  void _onPlanChange() {
    if (!mounted) return;
    setState(() { _indexedCatalog = null; });
  }

  void refresh() => setState(() {
    _indexedCatalog = null;
    future = widget.repository.reload();
  });

  void _openForm({String? id}) {
    final plan = widget.plan;
    if (plan == null || plan.stale) return;
    showModalBottomSheet<void>(
      context:context, isScrollControlled:true, showDragHandle:true,
      builder:(_) => NativeM40CollectionForm(plan:plan,collectionId:id));
  }

  void _openPicker(String id) {
    final plan = widget.plan;
    if (plan == null || plan.stale) return;
    showModalBottomSheet<void>(
      context:context,isScrollControlled:true,showDragHandle:true,
      builder:(_) => NativeM40AddTitlesSheet(plan:plan,collectionId:id));
  }

  void _reportFailure(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text(e is FormatException ? e.message :
          e is StateError ? e.message : 'Collection action was rejected')));
  }

  Future<void> _confirmRemove(String collectionId, String titleId) async {
    final plan = widget.plan;
    if (plan == null || plan.stale) return;
    final confirmed = await showDialog<bool>(
      context:context,
      builder:(dialog)=>AlertDialog(
        title:const Text('Remove title from this Collection?'),
        content:const Text('Only device-local membership changes. The '
          'Library title, History, XP and cloud data remain untouched.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Cancel')),
          FilledButton(
            key:const Key('m40-confirm-remove'),
            onPressed:()=>Navigator.pop(dialog,true),
            child:const Text('Stage local removal')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try { plan.removeTitles(collectionId,[titleId]); }
    on StateError catch(e) { _reportFailure(e); }
    on FormatException catch(e) { _reportFailure(e); }
  }

  Future<void> _confirmDelete(MediaFlowCollection collection) async {
    final plan = widget.plan;
    if (plan == null || plan.stale) return;
    final confirmed = await showDialog<bool>(
      context:context,
      builder:(dialog)=>AlertDialog(
        title:Text('Stage deletion of ${collection.title}?'),
        content:Text('Device-only preview. This Collection has '
          '${collection.titleIds.length} members. Existing Library titles '
          'remain intact. Personal Order Collection assignments, website '
          'tombstones and XP have NOT been updated.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Cancel')),
          FilledButton(
            key:const Key('m40-confirm-delete'),
            onPressed:()=>Navigator.pop(dialog,true),
            child:const Text('Stage deletion locally')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      plan.stageDelete(collection.id);
      setState(() { opened = null; });
    } on StateError catch(e) { _reportFailure(e); }
      on FormatException catch(e) { _reportFailure(e); }
  }

  void _move(String collectionId,String titleId,int position) {
    final plan = widget.plan;
    if (plan == null || plan.stale) return;
    try { plan.moveTitle(collectionId,titleId,position); }
    on StateError catch(e) { _reportFailure(e); }
    on FormatException catch(e) { _reportFailure(e); }
  }

  void _review() {
    final plan = widget.plan;
    if (plan == null) return;
    showModalBottomSheet<void>(
      context:context,showDragHandle:true,isScrollControlled:true,
      builder:(ctx)=>SafeArea(child:FractionallySizedBox(
        heightFactor:.80,
        child:AnimatedBuilder(animation:plan,
          builder:(context,_)=>ListView(
            padding:const EdgeInsets.all(18),
            children:[
              Text('Local Collection plan',
                style:Theme.of(context).textTheme.titleLarge),
              const SizedBox(height:8),
              const Text('NO CLOUD SAVE · changes expire on sign-out or '
                'restart. Website tombstones, Personal Order, History and '
                'XP are unchanged.'),
              if (plan.stale) const Text(
                'Cloud snapshot changed. Discard quarantined changes first.'),
              Text('${plan.creations} created · ${plan.edits} edited · '
                '${plan.deletions} pending deletion'),
              Wrap(spacing:8,children:[
                TextButton(onPressed:plan.canUndo?plan.undo:null,
                  child:const Text('Undo')),
                TextButton(onPressed:plan.canRedo?plan.redo:null,
                  child:const Text('Redo')),
              ]),
              if (!plan.stale)
                for (final id in plan.changedIds)
                  ListTile(
                    title:Text(plan.isDeleted(id) ? 'Pending deletion: $id' :
                      plan.fieldsFor(id).title),
                    subtitle:Text(plan.isCreated(id) ? 'Local creation' :
                      plan.isDeleted(id) ? 'Locally staged deletion' :
                      'Edited locally'),
                    trailing:plan.isDeleted(id)
                      ? TextButton(
                          onPressed:()=>plan.restore(id),
                          child:const Text('Restore'))
                      : null,
                  ),
              const SizedBox(height:12),
              OutlinedButton.icon(
                key:const Key('m40-discard'),
                onPressed:plan.hasChanges ? () async {
                  final approved=await showDialog<bool>(
                    context:context,
                    builder:(dialog)=>AlertDialog(
                      title:const Text('Discard all local Collection changes?'),
                      content:const Text('This discards only the unsaved '
                        'device plan. Cloud data remains unchanged.'),
                      actions:[
                        TextButton(onPressed:()=>Navigator.pop(dialog,false),
                          child:const Text('Cancel')),
                        FilledButton(onPressed:()=>Navigator.pop(dialog,true),
                          child:const Text('Discard plan')),
                      ],
                    ));
                  if (approved == true) {
                    plan.discard();
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                } : null,
                icon:const Icon(Icons.delete_sweep_outlined),
                label:const Text('Discard entire local plan')),
            ],
          )),
      ))),
    );
  }

  Widget _planControls() {
    final plan = widget.plan!;
    return Card(child:Padding(
      padding:const EdgeInsets.all(10),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('LOCAL COLLECTION CHANGE PLANNER',
          style:Theme.of(context).textTheme.labelLarge),
        Text(plan.stale
          ? 'Source refreshed · Draft quarantined. Discard before editing.'
          : '${plan.creations} create · ${plan.edits} edit · '
            '${plan.deletions} delete · NOT SAVED TO CLOUD',
          key:const Key('m40-plan-count')),
        const SizedBox(height:8),
        Wrap(spacing:8,runSpacing:8,children:[
          FilledButton.icon(
            key:const Key('m40-create'),
            onPressed:plan.stale ? null : ()=>_openForm(),
            icon:const Icon(Icons.add),
            label:const Text('Create local Collection')),
          OutlinedButton.icon(
            key:const Key('m40-review'),
            onPressed:_review,icon:const Icon(Icons.fact_check_outlined),
            label:const Text('Review local plan')),
          OutlinedButton.icon(
            key:const Key('m40-preview'),
            onPressed:plan.stale || !plan.hasChanges ? null : ()=>setState(() {
              _preview = !_preview;
              _indexedCatalog = null;
            }),
            icon:Icon(_preview ? Icons.visibility_off_outlined :
                Icons.visibility_outlined),
            label:Text(_preview ? 'Show cloud source' : 'Preview local changes')),
          OutlinedButton(
            key:const Key('m40-undo'),
            onPressed:plan.canUndo ? plan.undo : null,
            child:const Text('Undo')),
          OutlinedButton(
            key:const Key('m40-redo'),
            onPressed:plan.canRedo ? plan.redo : null,
            child:const Text('Redo')),
        ]),
      ]),
    ));
  }

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
      final authoritative = result.requireData;
      final plan = widget.plan;
      plan?.observe(authoritative);
      final localPreview = _preview && plan != null &&
          plan.hasChanges && !plan.stale;
      final data = localPreview ? plan.previewCatalog() : authoritative;
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
              Text(localPreview
                ? 'DEVICE-ONLY PREVIEW · Never uploaded'
                : 'Cloud Collections · Read-only source',
                key:const Key('m40-source-label')),
            ],
          )),
          IconButton(onPressed: refresh, tooltip: 'Refresh Collections',
              icon: const Icon(Icons.refresh)),
        ]),
        if (plan != null) ...[
          const SizedBox(height:8),
          _planControls(),
        ],
        const SizedBox(height: 12),
        if (selected == null) ...[
          TextField(controller: search, decoration: const InputDecoration(
            border: OutlineInputBorder(), isDense: true,
            prefixIcon: Icon(Icons.search), labelText: 'Find a collection',
          ), onChanged: (value) => setState(() => query = value)),
          const SizedBox(height: 12),
        ] else ...[
          if (plan != null) ...[
            Wrap(spacing:8,runSpacing:8,children:[
              OutlinedButton.icon(
                key:const Key('m40-edit'),
                onPressed:plan.stale ? null :
                  ()=>_openForm(id:selected.id),
                icon:const Icon(Icons.edit_outlined),
                label:const Text('Edit local Collection')),
              OutlinedButton.icon(
                key:const Key('m40-add-titles'),
                onPressed:plan.stale ? null :
                  ()=>_openPicker(selected.id),
                icon:const Icon(Icons.playlist_add),
                label:const Text('Add Library titles')),
              OutlinedButton.icon(
                key:const Key('m40-delete'),
                onPressed:plan.stale ? null :
                  ()=>_confirmDelete(selected),
                icon:const Icon(Icons.delete_outline),
                label:const Text('Stage Collection deletion')),
            ]),
            const SizedBox(height:8),
            const Text('Member ordering/removal below only stages device changes. '
              'No Library titles will be deleted.'),
          ],
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
          ? _titles(_visibleMembers(selected.id),
              collectionId:selected.id, order: selected.titleIds)
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

  Widget _titles(List<MediaFlowTitle> titles, {
      required String collectionId,required List<String> order}) =>
      titles.isEmpty
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
              trailing: widget.plan == null ? null :
                Row(mainAxisSize:MainAxisSize.min,children:[
                  IconButton(
                    key:Key('m40-up-${item.id}'),
                    tooltip:'Move member earlier',
                    onPressed:widget.plan!.stale || memberQuery.isNotEmpty ||
                        memberStatus.isNotEmpty || memberSort != 'saved' ||
                        order.indexOf(item.id) <= 0 ? null :
                      ()=>_move(collectionId,item.id,order.indexOf(item.id)-1),
                    icon:const Icon(Icons.arrow_upward,size:19)),
                  IconButton(
                    key:Key('m40-down-${item.id}'),
                    tooltip:'Move member later',
                    onPressed:widget.plan!.stale || memberQuery.isNotEmpty ||
                        memberStatus.isNotEmpty || memberSort != 'saved' ||
                        order.indexOf(item.id) < 0 ||
                        order.indexOf(item.id) >= order.length-1 ? null :
                      ()=>_move(collectionId,item.id,order.indexOf(item.id)+1),
                    icon:const Icon(Icons.arrow_downward,size:19)),
                  IconButton(
                    key:Key('m40-remove-${item.id}'),
                    tooltip:'Remove member locally',
                    onPressed:widget.plan!.stale ? null :
                      ()=>_confirmRemove(collectionId,item.id),
                    icon:const Icon(Icons.remove_circle_outline,size:19)),
                ]),
            ));
          },
        );
}
