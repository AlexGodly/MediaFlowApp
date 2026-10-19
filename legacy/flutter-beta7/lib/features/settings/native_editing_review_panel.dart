// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';

import '../../services/native_editing_workspace.dart';

/// Review/discard of RAM-only sketches scoped to current signed-in shell.
class NativeEditingReviewPanel extends StatelessWidget {
  const NativeEditingReviewPanel({super.key, required this.workspace});
  final NativeEditingWorkspace workspace;

  Future<void> _discard(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard all local drafts?'),
        content: const Text('This only removes the temporary title and '
            'logging sketches on this device. Nothing has been submitted '
            'to MediaFlow cloud, History, XP, or other devices.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard drafts'),
          ),
        ],
      ),
    );
    if (confirmed == true) workspace.discardAll();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: workspace,
    builder: (context, _) => Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Native editing drafts',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text('Temporary previews for your currently signed-in '
                'account. Not submitted, not an offline sync queue, and '
                'not restored after closing the app or signing out.'),
            if (workspace.stale) ...[
              const SizedBox(height: 8),
              Text('The Library snapshot changed. These drafts are stale '
                  'and cannot be edited further. Review or discard them.',
                key: const Key('native-drafts-stale-warning'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 8),
            Text(
              'Title drafts: ' + workspace.titleCount.toString() +
              ' · Logging drafts: ' + workspace.logCount.toString() +
              ' · History submitted: 0 · XP awarded: 0',
              key: const Key('native-draft-counts'),
            ),
            for (final edit in workspace.titleDrafts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_note_outlined),
                title: Text(edit.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text('Status: ' + edit.status +
                  ' · Priority: ' + edit.priority +
                  ' · Progress: ' + edit.progress.toString() +
                  ' · Rating: ' + (edit.rating?.toString() ?? '-') +
                  (edit.statusSideEffectsUnverified
                      ? ' · Side effects not verified' : ''),
                ),
                trailing: IconButton(
                  tooltip: 'Discard title draft',
                  onPressed: () => workspace.discardTitle(edit.titleId),
                  icon: const Icon(Icons.close),
                ),
              ),
            for (final log in workspace.logDrafts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.playlist_add_outlined),
                title: Text(log.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                subtitle: Text('Planned ' + log.units.toString() +
                  ' units · ' + log.minutes.toString() + ' minutes · '
                  'Preview progress ' + log.startingProgress.toString() +
                  ' to ' + log.projectedProgress.toString() +
                  ' · ' + (log.mode.name == 'lastProgress' ? 'Last progress' : 'Amount') +
                  (log.repeat ? ' · Repeat' : '') +
                  ' · Hypothetical streak ' + log.prospectiveStreak.toString() +
                  ' · No History/XP changes',
                ),
                trailing: IconButton(
                  tooltip: 'Discard logging draft',
                  onPressed: () => workspace.discardLog(log.titleId),
                  icon: const Icon(Icons.close),
                ),
              ),
            for (final entry in workspace.itemizedDrafts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.format_list_numbered),
                title: Text('Itemized · ' + entry.seasonName),
                subtitle: Text(
                  entry.unitNumbers.join(', ') +
                  ' · season progress ' +
                  entry.beforeSeasonProgress.toString() +
                  ' → ' + entry.afterSeasonProgress.toString() +
                  ' · title progress ' +
                  entry.afterTitleProgress.toString() +
                  (entry.repeat ? ' · repeat' : '') +
                  ' · History/XP submitted: 0',
                ),
                trailing: IconButton(
                  tooltip: 'Discard itemized draft',
                  onPressed: () => workspace.discardItemizedLog(entry.titleId),
                  icon: const Icon(Icons.close),
                ),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: workspace.hasDrafts
                  ? () => _discard(context) : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Discard all local drafts'),
            ),
          ],
        ),
      ),
    ),
  );
}
