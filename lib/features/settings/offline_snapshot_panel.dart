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
        const Text('A verified read-only snapshot is encrypted on this '
            'device using AES-256-GCM. A separate account key is stored '
            'through the operating system’s protected storage. '
            'If cloud access fails, the latest authenticated device '
            'copy may be shown, but it can be outdated.'),
        const SizedBox(height: 10),
        ValueListenableBuilder<NativeSnapshotSource>(
          valueListenable: widget.repository.source,
          builder: (_, status, __) => Text(
            _describe(status),
            key: const Key('offline-snapshot-status'),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: widget.repository.refreshing,
          builder: (_, active, __) => active
              ? const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Checking for a fresh cloud snapshot…',
                      key: Key('offline-refreshing-notice')),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 5),
        ValueListenableBuilder<DateTime?>(
          valueListenable: widget.repository.offlineSavedAt,
          builder: (_, savedAt, __) => savedAt == null
              ? const SizedBox.shrink()
              : Text('Device copy saved: ${savedAt.toLocal()}',
                  key: const Key('offline-copy-saved-at')),
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
        Text('Milestone 17 unencrypted caches are discarded after upgrade. '
            'Reconnect to create a new encrypted offline copy. '
            'Loss of the protected key makes its snapshot unreadable. '
            'Device copies are never cloud backups or synchronization '
            'authorities. Signing out removes copies and their keys.',
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
    case NativeSnapshotSource.offlineMemory:
      return 'Offline — last authenticated data in RAM only, not saved to device. Read-only.';
    case NativeSnapshotSource.invalidCloud:
      return 'Cloud account snapshot missing or invalid. Device recovery was blocked; no data changed.';
    case NativeSnapshotSource.unavailable:
      return 'Neither a current cloud snapshot nor a valid offline copy is available.';
  }
}
