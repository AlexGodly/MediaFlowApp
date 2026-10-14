import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';
import '../../services/native_m33_offline_queue.dart';
import '../../services/native_m34_conflict_review.dart';

enum _ManualChoice { keep, discard, recreate }

/// Inert, explicit offline-draft reconciliation. Never calls a cloud
/// mutation, has no apply-to-cloud button and requires fresh SELECT on
/// every user-approved recreation of a device-only priority operation.
class NativeM34ConflictCenterPanel extends StatefulWidget {
  const NativeM34ConflictCenterPanel({super.key, required this.repository});
  final SupabaseMediaFlowLibraryRepository repository;

  @override
  State<NativeM34ConflictCenterPanel> createState() =>
      _NativeM34ConflictCenterPanelState();
}

class _NativeM34ConflictCenterPanelState
    extends State<NativeM34ConflictCenterPanel> {
  NativeM34ReviewReport? _review;
  NativeM33OfflineDraftQueue? _queue;
  final Map<String, _ManualChoice> _choices = {};
  String _message = 'Load saved drafts, then manually review fresh cloud data.';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _execute(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (_) {
      if (mounted) {
        setState(() => _message =
          'This review is outdated or unavailable. No cloud data changed. '
          'Refresh the review before trying again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _execute(() async {
    final saved = await widget.repository.loadOfflineDraftQueue();
    if (!mounted) return;
    setState(() {
      _queue = saved;
      _review = null;
      _choices.clear();
      _message = saved == null
          ? 'No encrypted offline priority drafts on this device.'
          : 'Found ${saved.entries.length} encrypted draft(s). '
            'No cloud data has been checked yet.';
    });
  });

  Future<void> _reviewCloud() => _execute(() async {
    final report = await widget.repository.reviewOfflineDraftConflicts();
    final stored = await widget.repository.loadOfflineDraftQueue();
    if (!mounted) return;
    setState(() {
      _review = report;
      _queue = stored;
      _choices.clear();
      _message = report?.message ?? 'No encrypted drafts remain.';
    });
  });

  Future<void> _resolve() async {
    final report = _review;
    if (_busy || report == null) return;
    final discarded = _choices.entries
        .where((e) => e.value == _ManualChoice.discard)
        .map((e) => e.key).toSet();
    final recreated = _choices.entries
        .where((e) => e.value == _ManualChoice.recreate)
        .map((e) => e.key).toSet();
    if (discarded.isEmpty && recreated.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm device-only decisions'),
        content: Text('Discard ${discarded.length} and recreate '
          '${recreated.length} encrypted priority draft(s)? '
          'Recreation checks fresh cloud values again and saves a NEW '
          'local intent. It does NOT change or synchronize the cloud.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Update device drafts')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _execute(() async {
      final saved = await widget.repository.resolveOfflineDraftConflicts(
        reviewed: report, discardOperationIds: discarded,
        recreateOperationIds: recreated,
      );
      if (!mounted) return;
      setState(() {
        _queue = saved;
        _review = null; // Any old cloud report is invalid after modification.
        _choices.clear();
        _message = saved == null
          ? 'Selected device drafts deleted. Nothing uploaded.'
          : 'Updated ${saved.entries.length} encrypted device draft(s). '
            'Review fresh cloud again before further decisions.';
      });
    });
  }

  String _status(NativeM34ItemStatus value) => switch (value) {
    NativeM34ItemStatus.unchanged => 'Original priority still matches',
    NativeM34ItemStatus.alreadyDesired =>
      'Cloud already matches your desired priority (origin unknown)',
    NativeM34ItemStatus.changedElsewhere =>
      'Conflict: cloud priority changed elsewhere',
    NativeM34ItemStatus.missing => 'Missing from cloud Library',
    NativeM34ItemStatus.duplicated => 'Duplicate cloud Library ID',
    NativeM34ItemStatus.invalidCloudPriority => 'Unrecognized cloud priority',
    NativeM34ItemStatus.unknownOffline => 'Cloud unavailable or unchecked',
  };

  @override
  Widget build(BuildContext context) {
    final report = _review;
    final selected = _choices.values
        .where((value) => value != _ManualChoice.keep).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Conflict Resolution Center',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 7),
            const Text('Review the original priority, your offline draft '
              'and the current cloud priority independently for each title. '
              'Keep, discard, or recreate LOCAL encrypted drafts. '
              'No cloud updates, uploads, or automatic merges.'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Load device drafts'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _reviewCloud,
                icon: const Icon(Icons.compare_arrows_outlined),
                label: const Text('Review fresh cloud'),
              ),
            ]),
            if (_busy) const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
            const SizedBox(height: 8),
            Text(_message, key: const Key('m34-conflict-message')),
            if (_queue != null) Text(
              'Encrypted local drafts: ${_queue!.entries.length}',
              key: const Key('m34-local-draft-count'),
            ),
            if (report != null) ...[
              const SizedBox(height: 8),
              if (report.anchorChanged)
                Text('The full cloud snapshot differs from the draft '
                  'baseline. Old revisions cannot authorize uploads.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  key: const Key('m34-cloud-drift-warning')),
              Text('Conflicts: ${report.conflicts} · '
                'Cloud checked: ${report.hasFreshCloud ? "yes" : "no"} '
                '· Upload permission: none',
                key: const Key('m34-conflict-count')),
              const SizedBox(height: 8),
              for (final item in report.items)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(item.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(_status(item.status),
                          key: Key('m34-status-${item.operationId}')),
                        const SizedBox(height: 5),
                        Wrap(spacing: 14, runSpacing: 4, children: [
                          Text('Before: ${item.beforePriority}'),
                          Text('Your draft: ${item.desiredPriority}'),
                          Text('Cloud: ${item.cloudPriority ?? "Unknown"}'),
                        ]),
                        const SizedBox(height: 8),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Manual decision (device only)',
                            border: OutlineInputBorder(), isDense: true,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<_ManualChoice>(
                          key: Key('m34-choice-${item.operationId}'),
                          value: _choices[item.operationId] ??
                              _ManualChoice.keep,
                          isExpanded: true,
                          isDense: true,
                          items: [
                            const DropdownMenuItem(
                              value: _ManualChoice.keep,
                              child: Text('Keep existing local draft'),
                            ),
                            const DropdownMenuItem(
                              value: _ManualChoice.discard,
                              child: Text('Discard this local draft'),
                            ),
                            if (report.hasFreshCloud && item.mayRecreate)
                              const DropdownMenuItem(
                                value: _ManualChoice.recreate,
                                child: Text('Recreate vs current cloud (local)'),
                              ),
                          ],
                          onChanged: _busy ? null : (next) {
                            if (next != null) {
                              setState(() => _choices[item.operationId] = next);
                            }
                          },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: !_busy && selected > 0 ? _resolve : null,
                icon: const Icon(Icons.security_update_good_outlined),
                label: Text('Confirm ${selected} device-only decision(s)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
