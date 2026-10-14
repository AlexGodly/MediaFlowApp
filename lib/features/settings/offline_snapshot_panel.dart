import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';

/// Explicit local-copy controls. No Supabase mutations or write queue.
class OfflineSnapshotPanel extends StatefulWidget {
  const OfflineSnapshotPanel({super.key, required this.repository});
  final SupabaseMediaFlowLibraryRepository repository;

  @override
  State<OfflineSnapshotPanel> createState() => _OfflineSnapshotPanelState();
}

class _OfflineSnapshotPanelState extends State<OfflineSnapshotPanel> {
  bool busy = false;
  String? notice;

  Future<void> _refresh() async {
    if (busy) return;
    setState(() { busy = true; notice = null; });
    try {
      await widget.repository.reload();
      if (mounted) {
        setState(() => notice = 'Snapshot refreshed or recovered safely.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
          notice = 'No usable snapshot. Sign in and reconnect to refresh.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _clear() async {
    if (busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove offline copy?'),
        content: const Text('Only device-local read-only snapshots for this '
            'account will be deleted. Your MediaFlow cloud data is unchanged. '
            'You will need a connection to reload after leaving this view.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove device copy'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() { busy = true; notice = null; });
    try {
      await widget.repository.clearOfflineCache();
      if (mounted) {
        setState(() => notice =
          'Offline copies removed. Current open view remains in memory.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
          notice = 'Could not remove every local copy on this device.');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Offline recovery', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('When the cloud cannot be reached, MediaFlow may show '
            'the last verified device copy for this signed-in account. '
            'Offline views are read-only and may be outdated.'),
        const SizedBox(height: 10),
        ValueListenableBuilder<NativeSnapshotSource>(
          valueListenable: widget.repository.source,
          builder: (_, status, __) => Text(
            _describe(status),
            key: const Key('offline-snapshot-status'),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh cloud'),
          ),
          TextButton.icon(
            onPressed: busy ? null : _clear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear device copy'),
          ),
        ]),
        if (notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(notice!, key: const Key('offline-cache-notice')),
          ),
        const SizedBox(height: 8),
        Text('Device copies are stored in the app-private directory, '
            'but are not encrypted. They are never cloud backups or sync '
            'authorities. Signing out removes this account’s local copies.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    ),
  );
}

String _describe(NativeSnapshotSource status) {
  switch (status) {
    case NativeSnapshotSource.idle: return 'Not loaded yet.';
    case NativeSnapshotSource.checkingCloud: return 'Checking cloud…';
    case NativeSnapshotSource.cloud: return 'Displaying current cloud data.';
    case NativeSnapshotSource.cloudNotCached:
      return 'Displaying cloud data; device cache could not be saved.';
    case NativeSnapshotSource.offline:
      return 'Offline — displaying verified device copy (read-only).';
    case NativeSnapshotSource.recoveredPrevious:
      return 'Offline — recovered previous verified device copy (read-only).';
    case NativeSnapshotSource.unavailable:
      return 'Neither a current cloud snapshot nor a valid offline copy is available.';
  }
}
