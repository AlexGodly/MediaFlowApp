import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_m37_library_plan.dart';
import 'library_screen.dart' show MediaFlowCover;
import 'native_m37_library_plan_ui.dart';

/// M38 native title inspector. Cloud data remains read-only and all proposed
/// edits use the existing owner-scoped, RAM-only M37 planner.
class NativeM38TitleDetails extends StatelessWidget {
  const NativeM38TitleDetails({
    super.key, required this.title, required this.catalog, this.plan,
  });
  final MediaFlowTitle title;
  final MediaFlowCatalog catalog;
  final NativeM37LibraryPlan? plan;

  String _number(double? value) => value == null ? '?'
      : value == value.roundToDouble()
          ? value.toInt().toString() : value.toStringAsFixed(1);

  String _date(DateTime? date) =>
      date == null ? 'Not recorded' : date.toLocal().toIso8601String().split('T').first;

  Future<void> _edit(BuildContext context) async {
    final p = plan;
    if (p == null || p.stale || p.isDeleted(title.id)) return;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => NativeM37TitleForm(
        plan: p, catalog: catalog, titleId: title.id),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final p = plan;
    if (p == null || p.stale) return;
    final references = p.isTemporary(title.id) ? 0 : p.references(title.id);
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Stage local title deletion?'),
        content: Text('This is a reversible device-only change. Cloud Library, '
            'History, Collections, Personal Order and XP are not changed.'
            '${references > 0 ? " $references related references would need coordinated cleanup." : ""}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(
            key: const Key('m38-confirm-title-delete'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Stage deletion')),
        ],
      ),
    );
    if (yes != true || !context.mounted || p.stale) return;
    try {
      p.stageDelete([title.id]);
      if (context.mounted) Navigator.of(context).pop();
    } on StateError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)));
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: .90,
      child: AnimatedBuilder(
        animation: Listenable.merge([if (plan != null) plan!]),
        builder: (context, _) {
          final p = plan;
          final staged = p != null && !p.stale &&
              (p.isEdited(title.id) || p.isTemporary(title.id));
          final shown = staged ? p.fieldsFor(title.id).preview(
              title.id, original: title) : title;
          final category = catalog.categoryById[shown.categoryId];
          final total = shown.total;
          final fraction = total != null && total.isFinite && total > 0 &&
                  shown.progress.isFinite
              ? (shown.progress / total).clamp(0.0, 1.0) : null;

          return ListView(
            key: const Key('m38-title-details'),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Text('Title details', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(staged ? 'UNSAVED LOCAL PREVIEW · Nothing uploaded'
                : 'CLOUD SOURCE · Read-only',
                key: const Key('m38-detail-source'),
                style: Theme.of(context).textTheme.labelMedium),
              if (p?.stale == true)
                const Text('Snapshot refreshed. Local edits are quarantined.'),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MediaFlowCover(url: shown.coverUrl, width: 104, height: 148),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(shown.title, key: const Key('m38-detail-title'),
                      style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Text(category?.name ?? shown.categoryId),
                    Text('Status: ${shown.status}'),
                    Text('Priority: ${shown.priority}'),
                    if (shown.rating != null)
                      Text('Rating: ${_number(shown.rating)} / 10'),
                  ],
                )),
              ]),
              const SizedBox(height: 20),
              Text('Progress · ${_number(shown.progress)} / ${_number(total)}',
                style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (fraction != null)
                LinearProgressIndicator(value: fraction,
                  minHeight: 7, borderRadius: BorderRadius.circular(6))
              else
                const Text('Progress percentage unavailable (no valid total).'),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 4, children: [
                Chip(label: Text('Added: ${_date(shown.addedAt)}')),
                if (shown.completedAt != null)
                  Chip(label: Text('Completed: ${_date(shown.completedAt)}')),
                Chip(label: Text('${shown.seasons.length} seasons')),
              ]),
              if (shown.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Tags', style: Theme.of(context).textTheme.titleSmall),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final tag in shown.tags) Chip(label: Text(tag)),
                ]),
              ],
              if (shown.description.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Description',style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                SelectableText(shown.description),
              ],
              if (shown.seasons.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Seasons · read-only',
                  style: Theme.of(context).textTheme.titleSmall),
                for (final season in shown.seasons)
                  ListTile(
                    dense: true, contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.format_list_numbered),
                    title: Text(season.name),
                    subtitle: season.number == null ? null
                        : Text('Season ${_number(season.number)}'),
                    trailing: Text(
                      '${_number(season.progress)} / ${_number(season.total)}'),
                  ),
              ],
              const SizedBox(height: 16),
              if (staged && !p!.isTemporary(title.id))
                const Text('This title has an unsaved local metadata edit. '
                  'Unknown website fields and related records have not been modified.'),
              const Text('Native details show the available Library projection; '
                'external provider IDs and other full v410 metadata are not yet '
                'editable here. Status and progress do not trigger website '
                'logging, completion, History or XP side effects.'),
              const SizedBox(height: 14),
              if (p != null)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    key: const Key('m38-edit-title'),
                    onPressed: p.stale || p.isDeleted(title.id) ? null
                        : () => _edit(context),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit local metadata'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('m38-delete-title'),
                    onPressed: p.stale || p.isDeleted(title.id) ? null
                        : () => _delete(context),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Stage local deletion'),
                  ),
                ])
              else
                const Text('Local editing is unavailable in read-only mode.'),
            ],
          );
        },
      ),
    ),
  );
}

/// One atomic multi-title operation, with an explicit review + confirmation.
/// Each chosen property is optional; untouched properties stay as they were.
class NativeM38BulkMetadataSheet extends StatefulWidget {
  const NativeM38BulkMetadataSheet({
    super.key, required this.plan, required this.catalog, required this.ids,
  });
  final NativeM37LibraryPlan plan;
  final MediaFlowCatalog catalog;
  final List<String> ids;

  @override
  State<NativeM38BulkMetadataSheet> createState() =>
      _NativeM38BulkMetadataSheetState();
}

class _NativeM38BulkMetadataSheetState extends State<NativeM38BulkMetadataSheet> {
  String category = '', status = '', priority = '';
  final tags = TextEditingController();
  String? error;

  @override
  void dispose() { tags.dispose(); super.dispose(); }

  Future<void> _stage() async {
    final added = tags.text.split(',').map((t) => t.trim())
        .where((t) => t.isNotEmpty).toList();
    if (category.isEmpty && status.isEmpty && priority.isEmpty &&
        added.isEmpty) {
      setState(() => error = 'Select a change before continuing.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Apply to ${widget.ids.length} titles?'),
        content: const Text('This stages one reversible LOCAL metadata edit. '
          'No server save, related-record changes, XP or logging side effects.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel')),
          FilledButton(
            key: const Key('m38-confirm-bulk'),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Stage local batch edit')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      widget.plan.batchEdit(widget.ids,
        categoryId: category.isEmpty ? null : category,
        status: status.isEmpty ? null : status,
        priority: priority.isEmpty ? null : priority,
        addTags: added);
      if (mounted) Navigator.pop(context);
    } on StateError catch (e) {
      if (mounted) setState(() => error = e.message);
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Widget selector(String label, String value,
      List<DropdownMenuItem<String>> options, ValueChanged<String> changed,
      String keyName) => DropdownButtonFormField<String>(
    key: Key('m38-bulk-$keyName'), initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label,
      isDense: true, border: const OutlineInputBorder()),
    items: options,
    onChanged: widget.plan.stale ? null
        : (next) { if (next != null) setState(() => changed(next)); },
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .83,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text('Batch metadata · ${widget.ids.length} titles',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('LOCAL ONLY · Keep unchanged for fields you do not '
              'want to modify. Tags are added without deleting existing tags. '
              'One Undo reverses the entire batch.'),
            const SizedBox(height: 16),
            selector('Category', category, [
              const DropdownMenuItem(value: '', child: Text('Keep existing')),
              for (final c in widget.catalog.categories)
                DropdownMenuItem(value: c.id, child: Text(c.name)),
            ], (v) => category = v, 'category'),
            const SizedBox(height: 12),
            selector('Status', status, [
              const DropdownMenuItem(value: '', child: Text('Keep existing')),
              for (final s in ['planned','active','paused','dropped','completed'])
                DropdownMenuItem(value: s, child: Text(s)),
            ], (v) => status = v, 'status'),
            const SizedBox(height: 12),
            selector('Priority', priority, [
              const DropdownMenuItem(value: '', child: Text('Keep existing')),
              for (final p in ['low','medium','high'])
                DropdownMenuItem(value: p, child: Text(p)),
            ], (v) => priority = v, 'priority'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('m38-bulk-tags'),
              controller: tags,
              enabled: !widget.plan.stale,
              decoration: const InputDecoration(
                labelText: 'Add tags (comma-separated, optional)',
                border: OutlineInputBorder()),
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, key: const Key('m38-bulk-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              key: const Key('m38-stage-bulk'),
              onPressed: widget.plan.stale ? null : _stage,
              icon: const Icon(Icons.edit_note),
              label: const Text('Review and stage batch edit'),
            ),
            const SizedBox(height: 8),
            const Text('Changes expire on app restart or sign-out. '
              'No cloud write will be attempted.'),
          ],
        ),
      ),
    ),
  );
}
