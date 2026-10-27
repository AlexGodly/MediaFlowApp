import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_m37_library_plan.dart';

/// Local-only v410-shaped metadata form. It has no cloud transport and never
/// writes account snapshots, sessions, collections, XP, or personal order.
class NativeM37TitleForm extends StatefulWidget {
  const NativeM37TitleForm({
    super.key, required this.plan, required this.catalog, this.titleId,
  });
  final NativeM37LibraryPlan plan;
  final MediaFlowCatalog catalog;
  final String? titleId;
  @override
  State<NativeM37TitleForm> createState() => _NativeM37TitleFormState();
}

class _NativeM37TitleFormState extends State<NativeM37TitleForm> {
  late final TextEditingController name, progress, total, rating, cover,
      description, tags;
  late String category, status, priority;
  String? error;
  bool get editing => widget.titleId != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.titleId == null ? null :
      widget.plan.fieldsFor(widget.titleId!);
    name = TextEditingController(text: existing?.title ?? '');
    category = existing?.categoryId ??
        (widget.catalog.categories.isNotEmpty
          ? widget.catalog.categories.first.id : '');
    status = existing?.status ?? 'planned';
    priority = existing?.priority ?? 'medium';
    progress = TextEditingController(
      text: (existing?.progress ?? 0).toString());
    total = TextEditingController(text: existing?.total?.toString() ?? '');
    rating = TextEditingController(text: existing?.rating?.toString() ?? '');
    cover = TextEditingController(text: existing?.coverUrl ?? '');
    description = TextEditingController(text: existing?.description ?? '');
    tags = TextEditingController(text: existing?.tags.join(', ') ?? '');
  }

  @override
  void dispose() {
    for (final c in [name,progress,total,rating,cover,description,tags]) {
      c.dispose();
    }
    super.dispose();
  }

  void _stage() {
    try {
      double? number(TextEditingController controller) {
        final value = controller.text.trim();
        if (value.isEmpty) { return null; }
        final parsed = double.tryParse(value);
        if (parsed == null || !parsed.isFinite) {
          throw const FormatException('Enter valid finite numbers');
        }
        return parsed;
      }
      final next = NativeM37Fields(
        title: name.text.trim(), categoryId: category,
        status: status, priority: priority,
        progress: number(progress) ?? 0, total: number(total),
        rating: number(rating), coverUrl: cover.text.trim(),
        description: description.text.trim(),
        tags: tags.text.trim().isEmpty ? const [] : tags.text
          .split(',').map((e)=>e.trim()).toList(),
        seasons: widget.titleId == null ? const [] :
          widget.plan.fieldsFor(widget.titleId!).seasons,
        externalIds: widget.titleId == null ? const {} :
          widget.plan.fieldsFor(widget.titleId!).externalIds,
        manualExternalIds: widget.titleId == null ? const {} :
          widget.plan.fieldsFor(widget.titleId!).manualExternalIds,
        seasonSource: widget.titleId == null ? '' :
          widget.plan.fieldsFor(widget.titleId!).seasonSource,
      );
      if (widget.titleId == null) {
        widget.plan.create(next);
      } else {
        widget.plan.edit(widget.titleId!, next);
      }
      Navigator.of(context).pop();
    } on StateError catch (ex) {
      setState(() => error = ex.message);
    } on FormatException catch (ex) {
      setState(() => error = ex.message);
    }
  }

  Widget input(String label, TextEditingController controller, {
    String? keyName, int maxLines = 1, bool numeric = false,
  }) => TextField(
    key: keyName == null ? null : Key('m37-$keyName'),
    controller: controller, maxLines: maxLines,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : maxLines > 1 ? TextInputType.multiline : TextInputType.text,
    decoration: InputDecoration(labelText: label,
      border: const OutlineInputBorder(), isDense: true),
  );

  Widget choice(String label, String value, List<DropdownMenuItem<String>> items,
      ValueChanged<String> update) => DropdownButtonFormField<String>(
    key: ValueKey('m37-field-$label-$value'),
    initialValue: value, isExpanded: true,
    decoration: InputDecoration(labelText: label,
      border: const OutlineInputBorder(),isDense: true),
    items: items, onChanged: (next) {
      if (next != null) { setState(() => update(next)); }
    },
  );

  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: FractionallySizedBox(
      heightFactor: 0.90,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(editing ? 'Edit local Library draft' : 'Create local title draft',
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('DEVICE-ONLY PREVIEW · No Supabase save, '
            'History, XP, Collections or Personal Order changes. '
            'Title status and progress side effects are unverified.'),
          const SizedBox(height: 18),
          input('Title',name,keyName:'title'),
          const SizedBox(height: 10),
          choice('Category',category,[
            for (final c in widget.catalog.categories)
              DropdownMenuItem(value: c.id, child: Text(c.name,
                overflow: TextOverflow.ellipsis)),
          ],(v)=>category=v),
          const SizedBox(height: 10),
          choice('Status',status,[
            for (final v in ['planned','active','paused','dropped','completed'])
              DropdownMenuItem(value:v,child:Text(v)),
          ],(v)=>status=v),
          const SizedBox(height: 10),
          choice('Priority',priority,[
            for (final v in ['low','medium','high'])
              DropdownMenuItem(value:v,child:Text(v)),
          ],(v)=>priority=v),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(width: 130,child: input('Progress',progress,
              numeric:true,keyName:'progress')),
            SizedBox(width: 130,child: input('Total',total,
              numeric:true,keyName:'total')),
            SizedBox(width: 130,child: input('Rating (0–10)',rating,
              numeric:true,keyName:'rating')),
          ]),
          const SizedBox(height: 10),
          input('Cover URL (optional)',cover,keyName:'cover'),
          const SizedBox(height: 10),
          input('Tags (comma-separated)',tags,keyName:'tags'),
          const SizedBox(height: 10),
          input('Description',description,keyName:'description',maxLines:3),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, key:const Key('m37-form-error'),
              style:TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('m37-stage-form'),
            onPressed: widget.plan.stale || category.isEmpty ? null : _stage,
            icon:const Icon(Icons.save_outlined),
            label:Text(editing ? 'Keep edited preview' : 'Stage local creation'),
          ),
          const SizedBox(height: 6),
          Text('Changes disappear after account sign-out or app restart. '
            'Undo/redo and recovery of planned deletions work only '
            'within this signed-in session.',
            style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  ));
}

/// Review/restore of queued local CRUD changes with explicit wipe.
/// No underlying v410 state is ever changed by an undo or restore operation.
class NativeM37PlanReview extends StatelessWidget {
  const NativeM37PlanReview({super.key,required this.plan});
  final NativeM37LibraryPlan plan;
  @override
  Widget build(BuildContext context) => SafeArea(child: FractionallySizedBox(
    heightFactor:.78,
    child: AnimatedBuilder(
      animation: plan,
      builder: (context,_) => ListView(
        padding:const EdgeInsets.all(18),
        children:[
          Text('Local Library change plan',
            style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:6),
          const Text('NO CLOUD SUBMISSION · Review locally staged '
            'creations, edits, and deletions. Original Library, History, '
            'XP, Collections and Personal Order remain untouched.'),
          if (plan.stale)
            const Padding(padding:EdgeInsets.only(top:8),
              child:Text('Cloud source changed. '
                'Discard this plan before staging anything new.')),
          const SizedBox(height:12),
          Text('${plan.creationCount} created · ${plan.editCount} edited · '
            '${plan.deletionCount} pending deletion'),
          const SizedBox(height:10),
          Wrap(spacing:8,runSpacing:8,children:[
            OutlinedButton.icon(
              onPressed:!plan.stale && plan.canUndo ? plan.undo : null,
              icon:const Icon(Icons.undo),
              label:const Text('Undo')),
            OutlinedButton.icon(
              onPressed:!plan.stale && plan.canRedo ? plan.redo : null,
              icon:const Icon(Icons.redo),
              label:const Text('Redo')),
          ]),
          if (plan.stale) const Text(
            'Pending change details cannot be rebased automatically.'),
          if (!plan.stale)
            for (final id in plan.changedIds)
              ListTile(
                dense:true,
                leading:Icon(plan.isDeleted(id)
                  ? Icons.delete_outline : plan.isTemporary(id)
                    ? Icons.add_circle_outline : Icons.edit_outlined),
                title:Text(plan.isDeleted(id) ? 'Pending deletion: $id'
                  : plan.fieldsFor(id).title,
                  maxLines:1,overflow:TextOverflow.ellipsis),
                subtitle:Text(plan.isDeleted(id) ? 'Device-only removal'
                  : plan.isTemporary(id) ? 'Locally created only'
                  : 'Locally edited; original cloud fields preserved'),
                trailing: plan.isDeleted(id)
                  ? TextButton.icon(
                    onPressed:()=>plan.restoreDeleted(id),
                    icon:const Icon(Icons.restore_outlined),
                    label:const Text('Restore'))
                  : null,
              ),
          const SizedBox(height:12),
          OutlinedButton.icon(
            key:const Key('m37-discard-plan'),
            onPressed:plan.hasChanges ? () async {
              final yes=await showDialog<bool>(context:context,
                builder:(dialog)=>AlertDialog(
                  title:const Text('Discard all local Library changes?'),
                  content:const Text('Your source Library stays unchanged. '
                    'Only this device-only draft plan is discarded.'),
                  actions:[
                    TextButton(onPressed:()=>Navigator.pop(dialog,false),
                      child:const Text('Cancel')),
                    FilledButton(onPressed:()=>Navigator.pop(dialog,true),
                      child:const Text('Discard local plan')),
                  ],
                ));
              if (yes == true) { plan.discard(); }
            } : null,
            icon:const Icon(Icons.delete_sweep_outlined),
            label:const Text('Discard entire local plan'),
          ),
        ],
      ),
    ),
  ));
}
