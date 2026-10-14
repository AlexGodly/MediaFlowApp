import 'package:flutter/material.dart';
import '../../design_system/mediaflow_theme.dart';
import '../../data/mediaflow_library_repository.dart';
import 'cloud_safety_panel.dart';
import 'account_health_panel.dart';
import 'offline_snapshot_panel.dart';
import 'sync_safety_lab_panel.dart';
import 'native_editing_review_panel.dart';
import 'draft_sandbox_panel.dart';

/// These settings are device-local. The original MediaFlow cloud preference
/// schema remains untouched until full settings parity is tested.
class NativeSettingsScreen extends StatelessWidget {
  const NativeSettingsScreen({
    super.key,
    required this.appearance,
    required this.onAppearanceChanged,
    this.repository,
    this.nativeRepository,
  });

  final MediaFlowAppearance appearance;
  final ValueChanged<MediaFlowAppearance> onAppearanceChanged;
  final MediaFlowLibraryRepository? repository;
  final SupabaseMediaFlowLibraryRepository? nativeRepository;

  @override
  Widget build(BuildContext context) => ListView(children: [
    Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 4),
    Text('Native application preferences',
        style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(height: 16),
    Card(child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('Choose how MediaFlow looks on this device. '
            'This does not change the website theme.'),
        const SizedBox(height: 15),
        Wrap(spacing: 9, runSpacing: 9, children: [
          for (final mode in MediaFlowAppearance.values)
            ChoiceChip(
              label: Text(_label(mode)),
              avatar: Icon(_icon(mode), size: 18),
              selected: appearance == mode,
              onSelected: (_) => onAppearanceChanged(mode),
            ),
        ]),
      ]),
    )),
    const SizedBox(height: 12),
    if (repository != null) ...[
      CloudSafetyPanel(repository: repository!),
      const SizedBox(height: 12),
      AccountHealthPanel(repository: repository!),
      const SizedBox(height: 12),
    ],
    if (nativeRepository != null) ...[
      NativeEditingReviewPanel(workspace: nativeRepository!.editingWorkspace),
      const SizedBox(height: 12),
      OfflineSnapshotPanel(repository: nativeRepository!),
      const SizedBox(height: 12),
    ],
    const DraftSandboxPanel(),
    const SizedBox(height: 12),
    const SyncSafetyLabPanel(),
    const SizedBox(height: 12),
    Card(child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Account data', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Library, Dashboard and History currently use read-only '
            'access to your existing Supabase account. Refreshing a view '
            'reloads the original cloud snapshot.'),
        const SizedBox(height: 8),
        const Text('Local title and logging drafts are available, but '
            'saving them to cloud, awarding XP and updating History, '
            'automatic offline synchronization, imports and backup '
            'restoration are not enabled yet. 
            'The original MediaFlow website remains authoritative.'),
      ]),
    )),
  ]);
}

String _label(MediaFlowAppearance mode) {
  switch (mode) {
    case MediaFlowAppearance.dark: return 'Dark';
    case MediaFlowAppearance.light: return 'Light';
    case MediaFlowAppearance.amoled: return 'AMOLED';
  }
}

IconData _icon(MediaFlowAppearance mode) {
  switch (mode) {
    case MediaFlowAppearance.dark: return Icons.dark_mode_outlined;
    case MediaFlowAppearance.light: return Icons.light_mode_outlined;
    case MediaFlowAppearance.amoled: return Icons.contrast_outlined;
  }
}
