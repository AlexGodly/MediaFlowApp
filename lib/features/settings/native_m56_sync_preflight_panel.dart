import 'package:flutter/material.dart';
import '../../design_system/mediaflow_components.dart';
import '../../services/native_m56_sync_inventory.dart';

/// M56 staging preparation: read-only source audit, never a setup or
/// production-migration tool. No keys, URLs, network or mutation callbacks.
class NativeM56SyncPreflightPanel extends StatelessWidget {
  const NativeM56SyncPreflightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MfPanel(child: Column(
      key: const Key('m56-sync-preflight-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Icon(Icons.account_tree_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 9),
          Expanded(child: Text('Synchronization staging preflight',
            style: theme.textTheme.titleLarge)),
        ]),
        const SizedBox(height: 7),
        Text('Milestone 56 · website v410 source audit',
          style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('Staging & production cutover: BLOCKED',
          key: const Key('m56-sync-cutover-blocked'),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(NativeM56SyncInventory.warning,
          style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(label: Text(
            '${NativeM56SyncInventory.writerSurfaces} writer-related surfaces')),
          Chip(label: Text(
            '${NativeM56SyncInventory.rehearsalScenarios} synthetic cases')),
          Chip(label: Text(
            '${NativeM56SyncInventory.unresolvedStagingChecks} staging blockers')),
        ]),
        const SizedBox(height: 7),
        const Text('The synthetic rehearsal runs only in CI, against an '
          'in-memory model. It cannot check a real database or authorize '
          'editing your existing MediaFlow account.'),
        ExpansionTile(
          key: const Key('m56-writer-surfaces'),
          title: const Text('Source-backed write path inventory'),
          subtitle: const Text('Cloud writer, callers, local exports & previews'),
          tilePadding: EdgeInsets.zero,
          children: [
            for (final surface in NativeM56SyncInventory.sources)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(surface.entrypoint),
                subtitle: Text(
                  '${surface.client} · ${surface.kind}\n'
                  '${surface.sourcePath}'),
                trailing: Icon(
                  surface.risk == 'critical'
                      ? Icons.warning_amber_outlined
                      : Icons.info_outline,
                  size: 18),
              ),
          ],
        ),
        ExpansionTile(
          key: const Key('m56-staging-checks'),
          title: const Text('Blocked staging prerequisites'),
          subtitle: const Text('No staging project has been provisioned'),
          tilePadding: EdgeInsets.zero,
          children: [
            for (final check in NativeM56SyncInventory.stagingChecks)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline,
                  color: theme.colorScheme.error, size: 19),
                title: Text(check.id.replaceAll('-', ' ')),
                subtitle: Text(check.reason),
              ),
          ],
        ),
        ExpansionTile(
          key: const Key('m56-discovery-list'),
          title: const Text('Remaining writer discovery'),
          subtitle: const Text('Not safe to call the inventory exhaustive'),
          tilePadding: EdgeInsets.zero,
          children: [
            for (final item in NativeM56SyncInventory.outstandingDiscovery)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.search_outlined, size: 18),
                title: Text(item),
              ),
          ],
        ),
        Text('No cloud save, migration, staging deployment, restore, '
          'or release operation is available here.',
          key: const Key('m56-no-write-action'),
          style: theme.textTheme.bodySmall),
      ],
    ));
  }
}
