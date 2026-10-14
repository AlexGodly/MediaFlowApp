import 'package:flutter/material.dart';

import '../../services/native_cas_protocol.dart';
import '../../services/native_draft_journal.dart';
import '../../services/native_edit_proposals.dart';
import '../../services/native_sync_review.dart';

/// All inputs are synthetic and kept in memory. NO authenticated real data.
class SyncSafetyLabPanel extends StatefulWidget {
  const SyncSafetyLabPanel({super.key});
  @override
  State<SyncSafetyLabPanel> createState() => _SyncSafetyLabPanelState();
}

class _SyncSafetyLabPanelState extends State<SyncSafetyLabPanel> {
  static const owner = 'synthetic-sync-lab-only';
  static const revision = 'synthetic-revision-1';
  late NativeSimulatedAtomicServer _server = _newServer();
  NativeReviewBatch? _batch;
  String message = 'No pending synthetic review.';

  NativeSimulatedAtomicServer _newServer() => NativeSimulatedAtomicServer(
    NativeCloudRow(
      ownerId: owner,
      updatedAt: revision,
      stateData: {
        'library': [
          {'id': 'sample-a', 'title': 'Sample A', 'priority': 'low'},
          {'id': 'sample-b', 'title': 'Sample B', 'priority': 'medium'},
        ],
        'sessions': <Object>[],
        'categories': [
          {'id': 'sample-category', 'name': 'Example'},
        ],
        'settings': {'theme': 'dark'},
        'xpLedger': {'total': 0},
        'futureField': {'preserve': true},
      },
    ),
  );

  void _stage() {
    try {
      final row = _server.current!;
      final journal = NativeDraftJournal(accountId: owner);
      journal.add(NativeDraftEntry(
        operationId: 'demo-priority',
        proposal: NativeEditProposal(
          kind: NativeEditKind.setTitlePriority,
          accountId: owner,
          baseRevision: row.updatedAt,
          createdAt: DateTime.now().toUtc(),
          payload: const {'titleId': 'sample-a', 'value': 'high'},
        ),
      ));
      final batch = NativeReviewBatch.stage(
        batchId: 'demo-batch-1', base: row, journal: journal,
      );
      setState(() {
        _batch = batch;
        message = 'Synthetic review staged with full-payload fingerprint.';
      });
    } catch (_) {
      setState(() => message = 'Could not stage synthetic review.');
    }
  }

  void _inspect() {
    final batch = _batch;
    if (batch == null) return;
    final result = NativeSyncReview.inspect(
      batch: batch, cloudRow: _server.current,
      signedInOwnerId: owner,
    );
    setState(() => message = '${result.status.name}: ${result.message}');
  }

  void _simulateOtherDevice() {
    final old = _server.current!;
    final changed = old.stateData;
    (changed['xpLedger'] as Map)['total'] = 400;
    _server.simulateForeignWrite(NativeCloudRow(
      ownerId: owner,
      updatedAt: old.updatedAt, // Deliberately same timestamp.
      stateData: changed,
    ));
    setState(() => message =
        'Another simulated device changed XP while keeping updated_at identical.');
  }

  void _commit() {
    final batch = _batch;
    if (batch == null) return;
    final receipt = _server.commitForTest(
      batch: batch, signedInOwnerId: owner,
    );
    setState(() => message = receipt.alreadyApplied
        ? 'Duplicate simulation ignored: ${receipt.result}'
        : 'Local CAS result: ${receipt.result}. No cloud writes.');
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Atomic sync safety lab',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Synthetic data only. Demonstrates offline pending-review '
            'anchoring, timestamp-collision detection, simulated atomic '
            'conflicts and duplicate-operation handling. '
            'No actual account is edited, and no Supabase writes exist.'),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _batch == null ? _stage : null,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Stage demo review'),
          ),
          FilledButton.tonalIcon(
            onPressed: _batch == null ? null : _inspect,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Check conflict'),
          ),
          OutlinedButton.icon(
            onPressed: _simulateOtherDevice,
            icon: const Icon(Icons.devices_outlined),
            label: const Text('Simulate another device'),
          ),
          OutlinedButton.icon(
            onPressed: _batch == null ? null : _commit,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Simulate atomic save'),
          ),
          TextButton.icon(
            onPressed: () => setState(() {
              _batch = null;
              _server = _newServer();
              message = 'Synthetic lab reset.';
            }),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset lab'),
          ),
        ]),
        const SizedBox(height: 10),
        Text(message, key: const Key('native-sync-lab-message')),
      ]),
    ),
  );
}
