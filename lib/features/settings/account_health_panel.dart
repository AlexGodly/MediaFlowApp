import 'package:flutter/material.dart';
import '../../data/mediaflow_library_repository.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_account_health.dart';

/// Displays counts only. Never exposes title names, account IDs or raw JSON.
class AccountHealthPanel extends StatefulWidget {
  const AccountHealthPanel({super.key, required this.repository});
  final MediaFlowLibraryRepository repository;

  @override
  State<AccountHealthPanel> createState() => _AccountHealthPanelState();
}

class _AccountHealthPanelState extends State<AccountHealthPanel> {
  late Future<MediaFlowCatalog> snapshot;
  @override
  void initState() {
    super.initState();
    snapshot = widget.repository.load();
  }

  void refresh() => setState(() {
    snapshot = widget.repository.reload();
  });

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.fact_check_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text('Account data health',
                style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
              key: const Key('account-health-refresh'),
              tooltip: 'Refresh account health (read-only)',
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
            ),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Checks references in your current snapshot without editing, '
            'repairing, uploading, or sharing any records.',
          ),
          const SizedBox(height: 12),
          FutureBuilder<MediaFlowCatalog>(
            future: snapshot,
            builder: (context, result) {
              if (result.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (result.hasError) {
                return const Text('Could not inspect the cloud snapshot. '
                    'No data was changed. Try refreshing.');
              }
              final health = NativeAccountHealth.inspect(result.requireData);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Icon(health.hasWarnings
                        ? Icons.info_outline : Icons.check_circle_outline),
                    const SizedBox(width: 8),
                    Expanded(child: Text(health.hasWarnings
                        ? 'Review the reference counts below'
                        : 'No reference issues detected in supported fields',
                        key: const Key('account-health-status'))),
                  ]),
                  const SizedBox(height: 12),
                  _metric('Library titles', health.libraryTitles),
                  _metric('History sessions', health.historySessions),
                  _metric('Collections', health.collections),
                  _metric('Categories', health.categories),
                  _metric('Personal Order references',
                      health.personalOrderReferences),
                  const Divider(height: 24),
                  _metric('Missing category references',
                      health.missingCategoryReferences),
                  _metric('Missing Personal Order titles',
                      health.missingPersonalOrderReferences),
                  _metric('Missing collection titles',
                      health.missingCollectionReferences),
                  _metric('Unresolved History title links',
                      health.missingHistoryTitleReferences),
                  _metric('Duplicate Library IDs',
                      health.duplicateLibraryIds),
                  _metric('Empty Library IDs', health.emptyLibraryIds),
                  _metric('Repeated Personal Order IDs',
                      health.duplicatePersonalOrderReferences),
                  _metric('Repeated collection member IDs',
                      health.duplicateCollectionReferences),
                  const SizedBox(height: 10),
                  Text(
                    'Historical entries may intentionally reference deleted '
                    'titles. These are informational checks, not proof of '
                    'corruption. No automatic fixes are performed.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _metric(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Expanded(child: Text(label)),
      const SizedBox(width: 12),
      Text('$value', style: const TextStyle(fontWeight: FontWeight.w600)),
    ]),
  );
}
