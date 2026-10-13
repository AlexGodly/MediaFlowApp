import 'package:flutter/material.dart';
import '../design_system/mediaflow_theme.dart';

enum MediaFlowSection {
  dashboard('Dashboard', Icons.space_dashboard_outlined),
  library('Library', Icons.local_library_outlined),
  logging('Logging', Icons.edit_note_outlined),
  personalOrder('Personal Order', Icons.format_list_numbered_outlined),
  collections('Collections', Icons.collections_bookmark_outlined),
  history('History', Icons.history),
  statistics('Statistics', Icons.bar_chart_outlined),
  account('Account', Icons.person_outline),
  settings('Settings', Icons.settings_outlined);
  const MediaFlowSection(this.label, this.icon);
  final String label;
  final IconData icon;
}

class MediaFlowShell extends StatefulWidget {
  const MediaFlowShell({super.key});
  @override
  State<MediaFlowShell> createState() => _MediaFlowShellState();
}

class _MediaFlowShellState extends State<MediaFlowShell> {
  MediaFlowSection selected = MediaFlowSection.dashboard;
  MediaFlowAppearance appearance = MediaFlowAppearance.dark;
  static const primary = [
    MediaFlowSection.dashboard,
    MediaFlowSection.library,
    MediaFlowSection.logging,
    MediaFlowSection.personalOrder,
  ];

  void navigate(MediaFlowSection section) => setState(() => selected = section);

  void showMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final section in MediaFlowSection.values.where((s) => !primary.contains(s)))
              ListTile(
                leading: Icon(section.icon),
                title: Text(section.label),
                selected: selected == section,
                onTap: () {
                  Navigator.pop(sheetContext);
                  navigate(section);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MediaFlowTheme.build(appearance),
      child: LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth > 860;
        return Scaffold(
          appBar: AppBar(
            title: const Text('MediaFlow'),
            actions: [
              PopupMenuButton<MediaFlowAppearance>(
                tooltip: 'Appearance',
                icon: const Icon(Icons.palette_outlined),
                onSelected: (value) => setState(() => appearance = value),
                itemBuilder: (_) => [
                  for (final value in MediaFlowAppearance.values)
                    PopupMenuItem(value: value, child: Text(value.name)),
                ],
              ),
            ],
          ),
          body: Row(children: [
            if (desktop)
              SizedBox(
                width: 236,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: ListView(children: [
                    const SizedBox(height: 16),
                    for (final section in MediaFlowSection.values)
                      ListTile(
                        leading: Icon(section.icon),
                        title: Text(section.label),
                        selected: selected == section,
                        onTap: () => navigate(section),
                      ),
                  ]),
                ),
              ),
            Expanded(child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selected.label, style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 12),
                      const Text('Native interface scaffold. This section is not yet connected to MediaFlow data.'),
                    ],
                  ),
                ),
              ),
            ))),
          ]),
          bottomNavigationBar: desktop ? null : NavigationBar(
            selectedIndex: primary.contains(selected) ? primary.indexOf(selected) : 4,
            onDestinationSelected: (index) {
              if (index == 4) { showMore(); } else { navigate(primary[index]); }
            },
            destinations: [
              for (final section in primary)
                NavigationDestination(icon: Icon(section.icon), label: section.label),
              const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
            ],
          ),
        );
      }),
    );
  }
}
