import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';
import '../../services/native_m33_offline_queue.dart';

/// M33: user-triggered encrypted offline draft retention and revalidation.
/// NEVER a cloud write/retry worker. Buttons are intentionally not "Sync".
class NativeM33OfflineDraftPanel extends StatefulWidget {
  const NativeM33OfflineDraftPanel({super.key, required this.repository});
  final SupabaseMediaFlowLibraryRepository repository;

  @override
  State<NativeM33OfflineDraftPanel> createState() =>
      _NativeM33OfflineDraftPanelState();
}

class _NativeM33OfflineDraftPanelState
    extends State<NativeM33OfflineDraftPanel> {
  NativeM33OfflineDraftQueue? queue;
  NativeM33CheckResult? result;
  String message = 'Device drafts have not been loaded.';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _act(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; result = null; });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => message =
          'Review unavailable or unsafe. Cloud data was not changed.');
      }
    } finally {
      if (mounted) { setState(() => busy = false); }
    }
  }

  Future<void> _refresh() => _act(() async {
    final restored = await widget.repository.loadOfflineDraftQueue();
    if (mounted) {
      setState(() {
      queue = restored;
      message = restored == null
          ? 'No encrypted offline drafts found.'
          : 'Restored encrypted device drafts. No automatic synchronization.';
      });
    }
  });

  Future<void> _save() => _act(() async {
    final saved = await widget.repository.keepOfflinePriorityDrafts();
    if (mounted) {
      setState(() {
      queue = saved;
      message = 'Priority-only drafts saved securely to this device.';
      });
    }
  });

  Future<void> _inspect() => _act(() async {
    final check = await widget.repository.inspectOfflineDraftQueue();
    if (mounted) {
      setState(() {
      result = check;
      message = check.message;
      });
    }
  });

  Future<void> _discard() async {
    if (busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard encrypted offline drafts?'),
        content: const Text('This deletes the saved device-only priority '
            'intent queue and encryption key. Cloud Library, History, XP '
            'and RAM drafts will not be modified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard saved drafts')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _act(() async {
      await widget.repository.discardOfflineDraftQueue();
      if (mounted) {
        setState(() {
        queue = null;
        message = 'Encrypted device drafts discarded. Nothing uploaded.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Offline priority drafts',
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Keep priority-only Library sketches encrypted across '
            'app restarts, including when displaying a verified offline '
            'device copy. A fresh online check identifies conflicts, but '
            'does not apply or upload changes. Real offline sync is blocked '
            'until the website and native app share a safe write protocol.'),
        const SizedBox(height: 10),
        Text(queue == null
            ? 'No device-only draft queue saved.'
            : '${queue!.entries.length} device-only operation(s) · '
              'Source: ${queue!.source}',
          key: const Key('m33-offline-queue-count')),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Keep offline drafts'),
          ),
          OutlinedButton.icon(
            onPressed: busy || queue == null ? null : _inspect,
            icon: const Icon(Icons.rule_outlined),
            label: const Text('Review against cloud'),
          ),
          TextButton.icon(
            onPressed: busy || queue == null ? null : _discard,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Discard device drafts'),
          ),
        ]),
        if (busy) const Padding(
          padding: EdgeInsets.only(top: 10),
          child: LinearProgressIndicator(),
        ),
        const SizedBox(height: 8),
        Text(message, key: const Key('m33-offline-queue-notice')),
        if (result != null)
          Text('Last check: ${result!.status.name} · Upload: disabled',
              key: const Key('m33-offline-queue-result')),
      ]),
    ),
  );
}
