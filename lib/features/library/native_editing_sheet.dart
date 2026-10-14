import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_editing_workspace.dart';

/// A deliberate local-only editor. It never receives a Supabase client or a
/// full cloud snapshot, and can neither create History nor award XP.
class NativeTitleDraftSheet extends StatefulWidget {
  const NativeTitleDraftSheet({
    super.key,
    required this.catalog,
    required this.title,
    required this.workspace,
  });
  final MediaFlowCatalog catalog;
  final MediaFlowTitle title;
  final NativeEditingWorkspace workspace;

  @override
  State<NativeTitleDraftSheet> createState() => _NativeTitleDraftSheetState();
}

class _NativeTitleDraftSheetState extends State<NativeTitleDraftSheet> {
  late String priority, status;
  late TextEditingController progress, rating;
  String? error;

  @override
  void initState() {
    super.initState();
    final original = widget.workspace.titleDraft(widget.title.id);
    priority = original?.priority ?? widget.title.priority;
    status = original?.status ?? widget.title.status;
    progress = TextEditingController(
      text: (original?.progress ?? widget.title.progress).toString(),
    );
    rating = TextEditingController(
      text: (original?.rating ?? widget.title.rating)?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    progress.dispose();
    rating.dispose();
    super.dispose();
  }

  void _stage() {
    try {
      final parsedProgress = double.tryParse(progress.text.trim());
      if (parsedProgress == null) {
        throw const FormatException('Enter a numeric progress value');
      }
      final parsedRating = rating.text.trim().isEmpty
          ? null : double.tryParse(rating.text.trim());
      if (rating.text.trim().isNotEmpty && parsedRating == null) {
        throw const FormatException('Enter a numeric rating or leave it blank');
      }
      widget.workspace.stageTitle(
        catalog: widget.catalog,
        titleId: widget.title.id,
        priority: priority,
        status: status,
        progress: parsedProgress,
        rating: parsedRating,
      );
      Navigator.of(context).pop();
    } on FormatException catch (failure) {
      setState(() => error = failure.message);
    } on StateError catch (failure) {
      setState(() => error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonLocked = widget.title.seasons.isNotEmpty;
    return SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(
        20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Draft title changes',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 5),
          Text(widget.title.title, maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          const Text('Local preview only. Cloud Library and History remain '
              'unchanged. Status and progress side effects need verified '
              'website parity before saving can be enabled.'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: priority,
            decoration: const InputDecoration(
              labelText: 'Priority', border: OutlineInputBorder(),
            ),
            items: [
              for (final value in ['low', 'medium', 'high'])
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setState(() => priority = value ?? priority),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: status,
            decoration: const InputDecoration(
              labelText: 'Status', border: OutlineInputBorder(),
            ),
            items: [
              for (final value in [
                'active', 'planned', 'completed', 'paused', 'dropped',
              ])
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setState(() => status = value ?? status),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('native-title-draft-progress'),
            controller: progress,
            enabled: !seasonLocked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Progress',
              border: const OutlineInputBorder(),
              helperText: seasonLocked
                  ? 'Per-season progress editor not yet implemented' : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('native-title-draft-rating'),
            controller: rating,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Rating (0–10, blank to clear)',
              border: OutlineInputBorder(),
            ),
          ),
          if (error != null) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(error!, key: const Key('native-title-draft-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          const SizedBox(height: 15),
          FilledButton.icon(
            onPressed: widget.workspace.stale ? null : _stage,
            icon: const Icon(Icons.edit_note),
            label: const Text('Keep local title draft'),
          ),
          if (widget.workspace.stale)
            const Text('Snapshot changed. Discard stale drafts in Settings.'),
        ],
      )),
    ));
  }
}

class NativeLogDraftSheet extends StatefulWidget {
  const NativeLogDraftSheet({
    super.key,
    required this.catalog,
    required this.title,
    required this.workspace,
  });
  final MediaFlowCatalog catalog;
  final MediaFlowTitle title;
  final NativeEditingWorkspace workspace;

  @override
  State<NativeLogDraftSheet> createState() => _NativeLogDraftSheetState();
}

class _NativeLogDraftSheetState extends State<NativeLogDraftSheet> {
  late TextEditingController amount, minutes, note;
  String? error;

  @override
  void initState() {
    super.initState();
    final previous = widget.workspace.logDraft(widget.title.id);
    amount = TextEditingController(text: previous?.units.toString() ?? '1');
    minutes = TextEditingController(text: previous?.minutes.toString() ?? '0');
    note = TextEditingController(text: previous?.note ?? '');
  }

  @override
  void dispose() {
    amount.dispose();
    minutes.dispose();
    note.dispose();
    super.dispose();
  }

  void _stage() {
    try {
      final units = double.tryParse(amount.text.trim());
      final runtime = double.tryParse(minutes.text.trim());
      if (units == null || runtime == null) {
        throw const FormatException('Enter numeric units and minutes');
      }
      widget.workspace.stageLog(
        catalog: widget.catalog,
        titleId: widget.title.id,
        amount: units,
        minutes: runtime,
        note: note.text,
      );
      Navigator.of(context).pop();
    } on FormatException catch (failure) {
      setState(() => error = failure.message);
    } on StateError catch (failure) {
      setState(() => error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
    padding: EdgeInsets.fromLTRB(
      20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Draft logging entry',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(widget.title.title),
        const SizedBox(height: 8),
        const Text('This is a local plan, not a submitted session. '
            'It does not create a History entry, update progress, '
            'award XP, advance a streak or synchronize to cloud.'),
        const SizedBox(height: 15),
        TextField(
          key: const Key('native-log-draft-units'),
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Units consumed', border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('native-log-draft-minutes'),
          controller: minutes,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Minutes', border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('native-log-draft-note'),
          controller: note,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notes', border: OutlineInputBorder(),
          ),
        ),
        if (widget.title.seasons.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 9),
            child: Text('Season-based logging is locked until the '
                'website conversion and XP side effects are matched.'),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Text(error!, key: const Key('native-log-draft-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        const SizedBox(height: 15),
        FilledButton.icon(
          onPressed: widget.workspace.stale ? null : _stage,
          icon: const Icon(Icons.playlist_add_outlined),
          label: const Text('Keep local logging draft'),
        ),
      ],
    )),
  ));
}
