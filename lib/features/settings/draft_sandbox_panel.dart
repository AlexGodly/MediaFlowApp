// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';

import '../../services/native_cas_protocol.dart';
import '../../services/native_draft_journal.dart';
import '../../services/native_edit_proposals.dart';
import '../../services/native_snapshot_codec.dart';

/// Explicit synthetic-data playground. Never reads or writes a real account.
class DraftSandboxPanel extends StatefulWidget {
  const DraftSandboxPanel({super.key});

  @override
  State<DraftSandboxPanel> createState() => _DraftSandboxPanelState();
}

class _DraftSandboxPanelState extends State<DraftSandboxPanel> {
  static const _owner = 'synthetic-sandbox-only';
  static const _revision = 'sandbox-revision-1';
  final NativeDraftJournal _journal = NativeDraftJournal(accountId: _owner);
  String _message = 'No drafts staged.';
  bool _cloudChanged = false;
  int _nextId = 1;

  NativeCloudRow _syntheticRow() => NativeCloudRow(
    ownerId: _owner,
    updatedAt: _cloudChanged ? 'sandbox-revision-2' : _revision,
    stateData: {
      'library': [
        {'id': 'demo-title', 'title': 'Demo Title', 'priority': 'low'},
      ],
      'sessions': <Object>[],
      'categories': [
        {'id': 'demo-category', 'name': 'Demo Category'},
      ],
      'settings': {'theme': 'dark'},
      'futureMetadata': {'preserve': true},
    },
  );

  void _stage() {
    try {
      _journal.add(NativeDraftEntry(
        operationId: 'demo-' + _nextId.toString(),
        proposal: NativeEditProposal(
          kind: NativeEditKind.setTitlePriority,
          accountId: _owner,
          baseRevision: _revision,
          createdAt: DateTime.now().toUtc(),
          payload: const {'titleId': 'demo-title', 'value': 'high'},
        ),
      ));
      _nextId++;
      setState(() => _message = 'Synthetic priority draft staged in memory.');
    } on StateError catch (error) {
      setState(() => _message = error.message);
    }
  }

  void _preview() {
    final result = _journal.preview(_syntheticRow());
    setState(() {
      if (!result.isValid) {
        _message = 'Blocked: ' + result.reason;
        return;
      }
      final updated = NativeSnapshotCodec.decode(
        result.plan!.proposedStateData,
      );
      final library = updated['library'] as List;
      final item = library.first as Map;
      _message = 'Local simulation succeeded: Demo Title priority = ' +
          item['priority'].toString() +
          '. No real account or cloud state was changed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Offline draft safety lab',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            const Text(
              'Synthetic sample data only. Drafts live in RAM and disappear '
              'when this screen or app session is discarded. This is NOT '
              'offline account editing or a background sync queue.',
            ),
            const SizedBox(height: 10),
            Text('Drafts in memory: ' + _journal.entries.length.toString()),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: _stage,
                icon: const Icon(Icons.add),
                label: const Text('Stage demo change'),
              ),
              FilledButton.tonalIcon(
                onPressed: _journal.entries.isEmpty ? null : _preview,
                icon: const Icon(Icons.science_outlined),
                label: const Text('Test local preview'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _cloudChanged = !_cloudChanged;
                  _message = _cloudChanged
                      ? 'Simulated another device updating the cloud.'
                      : 'Restored synthetic starting revision.';
                }),
                icon: const Icon(Icons.compare_arrows),
                label: Text(_cloudChanged
                    ? 'Reset demo revision'
                    : 'Simulate cloud conflict'),
              ),
              TextButton.icon(
                onPressed: _journal.entries.isEmpty ? null : () {
                  setState(() {
                    _journal.clear();
                    _message = 'All synthetic drafts discarded.';
                  });
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Discard drafts'),
              ),
            ]),
            const SizedBox(height: 10),
            Text(_message, key: const Key('draft-sandbox-message')),
          ],
        ),
      ),
    );
  }
}
