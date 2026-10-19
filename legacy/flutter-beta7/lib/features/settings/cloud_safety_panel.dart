import 'package:flutter/material.dart';

import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_cas_protocol.dart';

/// Read-only diagnostics: never displays raw user IDs or state payload.
class CloudSafetyPanel extends StatefulWidget {
  const CloudSafetyPanel({super.key, required this.repository});
  final MediaFlowLibraryRepository repository;

  @override
  State<CloudSafetyPanel> createState() => _CloudSafetyPanelState();
}

class _CloudSafetyPanelState extends State<CloudSafetyPanel> {
  late Future<MediaFlowCatalog> _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.repository.load();
  }

  void _refresh() => setState(() {
    _snapshot = widget.repository.reload();
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.shield_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text('Cloud sync safety',
                  style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Check cloud snapshot (read-only)',
              ),
            ]),
            const SizedBox(height: 8),
            _status(
              'Native cloud writes',
              NativeCloudCapabilities.cloudWritesEnabled
                  ? 'Enabled'
                  : 'Disabled — protected',
            ),
            _status(
              'Server-side conflict enforcement',
              NativeCloudCapabilities.hasServerSideCas
                  ? 'Available'
                  : 'Not installed',
            ),
            _status(
              'Offline changes queue',
              NativeCloudCapabilities.offlineWriteQueueEnabled
                  ? 'Enabled'
                  : 'Not enabled',
            ),
            const Divider(height: 24),
            FutureBuilder<MediaFlowCatalog>(
              future: _snapshot,
              builder: (context, result) {
                if (result.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(10),
                    child: LinearProgressIndicator(),
                  );
                }
                if (result.hasError) {
                  return const Text(
                    'Cloud snapshot could not be read. No data was written. '
                    'Check your sign-in and connection before continuing.',
                  );
                }
                final state = result.requireData;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _status('Library records', '${state.library.length}'),
                    _status('History sessions', '${state.sessions.length}'),
                    _status('Collections', '${state.collections.length}'),
                    _status(
                      'Last cloud update',
                      state.updatedAt?.toLocal().toString() ?? 'Not available',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Only the original MediaFlow website currently saves account '
              'changes. The native app can display and refresh your data, '
              'but it cannot edit cloud records until both clients use an '
              'approved conflict-safe synchronization protocol.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _status(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
