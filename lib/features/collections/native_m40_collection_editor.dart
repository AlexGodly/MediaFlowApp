import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_m40_collection_plan.dart';

class NativeM40CollectionForm extends StatefulWidget {
  const NativeM40CollectionForm({
    super.key, required this.plan, this.collectionId,
  });
  final NativeM40CollectionPlan plan;
  final String? collectionId;

  @override
  State<NativeM40CollectionForm> createState() => _NativeM40CollectionFormState();
}

class _NativeM40CollectionFormState extends State<NativeM40CollectionForm> {
  late final TextEditingController name, description, cover;
  String? error;

  @override
  void initState() {
    super.initState();
    final original = widget.collectionId == null ? null
        : widget.plan.fieldsFor(widget.collectionId!);
    name = TextEditingController(text: original?.title ?? '');
    description = TextEditingController(text: original?.description ?? '');
    cover = TextEditingController(text: original?.coverUrl ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    cover.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final current = widget.collectionId == null ? null
          : widget.plan.fieldsFor(widget.collectionId!);
      final next = NativeM40CollectionFields(
        title: name.text.trim(), description: description.text.trim(),
        coverUrl: cover.text.trim(), titleIds: current?.titleIds ?? const [],
      );
      if (widget.collectionId == null) {
        widget.plan.create(next);
      } else {
        widget.plan.edit(widget.collectionId!, next);
      }
      Navigator.pop(context);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    } on StateError catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .75,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(widget.collectionId == null
              ? 'Create local Collection' : 'Edit Collection locally',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('LOCAL PLAN ONLY · No cloud save, Collection XP, '
              'Personal Order updates or tombstones.'),
            const SizedBox(height: 18),
            TextField(
              key: const Key('m40-collection-title'),
              controller: name,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Collection title'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('m40-collection-description'),
              controller: description, maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('m40-collection-cover'),
              controller: cover,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Cover URL (optional)'),
            ),
            if (error != null) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(error!, key: const Key('m40-form-error'),
                style: TextStyle(color:Theme.of(context).colorScheme.error))),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('m40-save-collection'),
              onPressed: widget.plan.stale ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Stage local Collection change'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Local-only v392 Direct Add + optional multi-select. The picker stays open
/// after each addition and never touches Library, History or account state.
class NativeM40AddTitlesSheet extends StatefulWidget {
  const NativeM40AddTitlesSheet({
    super.key, required this.plan, required this.collectionId,
  });
  final NativeM40CollectionPlan plan;
  final String collectionId;

  @override
  State<NativeM40AddTitlesSheet> createState() =>
      _NativeM40AddTitlesSheetState();
}

class _NativeM40AddTitlesSheetState extends State<NativeM40AddTitlesSheet> {
  String query = '', membership = 'available';
  bool multi = false;
  final Set<String> picked = {};
  String? error;

  void _add(Iterable<String> ids) {
    try {
      widget.plan.addTitles(widget.collectionId, ids);
      setState(() { picked.clear(); error = null; });
    } on StateError catch (e) {
      setState(() => error = e.message);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.plan.source;
    if (source == null) { return const Center(child: Text('No source snapshot.')); }
    return SafeArea(child: FractionallySizedBox(
      heightFactor: .90,
      child: AnimatedBuilder(
        animation: widget.plan,
        builder: (context, _) {
          if (widget.plan.stale) {
            return const Center(child: Text('Cloud snapshot changed. '
              'Discard the quarantined Collection plan before editing.'));
          }
          final existing = widget.plan.fieldsFor(widget.collectionId)
              .titleIds.toSet();
          final seenIds = <String>{};
          final duplicate = <String>{};
          for (final t in source.library) {
            if (!seenIds.add(t.id)) { duplicate.add(t.id); }
          }
          final needle = query.trim().toLowerCase();
          final matches = <MediaFlowTitle>[];
          var total = 0;
          for (final title in source.library) {
            if (title.id.isEmpty || duplicate.contains(title.id) ||
                (needle.isNotEmpty &&
                  !(title.title.toLowerCase().contains(needle) ||
                  title.tags.any((tag) => tag.toLowerCase().contains(needle)))) ||
                (membership == 'available' && existing.contains(title.id)) ||
                (membership == 'added' && !existing.contains(title.id))) {
              continue;
            }
            total++;
            if (matches.length < 75) { matches.add(title); }
          }
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Add Library titles · LOCAL ONLY',
                    style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('m40-picker-search'),
                    decoration: const InputDecoration(
                      labelText: 'Search Library',prefixIcon:Icon(Icons.search),
                      border:OutlineInputBorder(), isDense:true),
                    onChanged: (value) => setState(() => query = value),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 12, runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center, children: [
                      DropdownButton<String>(
                        key: const Key('m40-picker-membership'),
                        value: membership, items: const [
                          DropdownMenuItem(value:'available',
                            child:Text('Not added')),
                          DropdownMenuItem(value:'all',
                            child:Text('All titles')),
                          DropdownMenuItem(value:'added',
                            child:Text('Already added')),
                        ],
                        onChanged: (v) => setState(() {
                          membership = v ?? 'available'; picked.clear();
                        }),
                      ),
                      FilterChip(
                        key: const Key('m40-picker-multi'),
                        label: const Text('Multi-Select'),
                        selected:multi, onSelected:(v)=>setState(() {
                          multi = v; picked.clear();
                        }),
                      ),
                      Text('$total matches · first 75 shown'),
                    ],
                  ),
                  if (error != null)
                    Text(error!,key:const Key('m40-picker-error'),
                      style:TextStyle(color:Theme.of(context).colorScheme.error)),
                  if (multi)
                    FilledButton.icon(
                      key: const Key('m40-add-selected'),
                      onPressed: picked.isEmpty ? null : () => _add(picked),
                      icon: const Icon(Icons.playlist_add_check),
                      label: Text('Add selected (${picked.length})'),
                    ),
                ],
              ),
            ),
            Expanded(child: ListView.builder(
              itemCount:matches.length,
              itemBuilder:(context,i) {
                final t=matches[i], added=existing.contains(t.id);
                return ListTile(
                  key:Key('m40-picker-title-${t.id}'),
                  title:Text(t.title,maxLines:2,overflow:TextOverflow.ellipsis),
                  subtitle:Text(t.categoryId),
                  trailing: multi && !added
                    ? Checkbox(
                        key:Key('m40-pick-${t.id}'),
                        value:picked.contains(t.id),
                        onChanged:(v)=>setState(() {
                          if (v == true) { picked.add(t.id); }
                          else { picked.remove(t.id); }
                        }),
                      )
                    : TextButton.icon(
                        key:Key('m40-direct-add-${t.id}'),
                        onPressed: added ? null : ()=>_add([t.id]),
                        icon:Icon(added ? Icons.check : Icons.add),
                        label:Text(added ? 'Added' : 'Add'),
                      ),
                );
              },
            )),
          ]);
        },
      ),
    ));
  }
}
