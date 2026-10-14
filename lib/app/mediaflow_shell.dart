import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/mediaflow_library_repository.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/history/history_screen.dart';
import '../features/auth/account_screen.dart';
import '../services/native_preferences.dart';
import '../features/settings/native_settings_screen.dart';
import '../features/collections/collections_screen.dart';
import '../features/statistics/statistics_screen.dart';
import '../features/personal_order/personal_order_screen.dart';
import '../features/logging/logging_screen.dart';
import '../features/library/library_screen.dart';
import '../design_system/mediaflow_theme.dart';
import '../design_system/mediaflow_components.dart';

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
  const MediaFlowShell({super.key, this.client});
  final SupabaseClient? client;
  @override
  State<MediaFlowShell> createState() => _MediaFlowShellState();
}

class _MediaFlowShellState extends State<MediaFlowShell> {
  MediaFlowSection selected = MediaFlowSection.dashboard;
  MediaFlowAppearance appearance = MediaFlowAppearance.dark;
  final NativePreferences preferences = NativePreferences();
  late final MediaFlowLibraryRepository? repository;

  String? get preferenceUserId => widget.client?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    repository = widget.client == null
        ? null : SupabaseMediaFlowLibraryRepository(widget.client!);
    unawaited(_restoreAppearance());
  }

  @override
  void dispose() {
    final current = repository;
    if (current is SupabaseMediaFlowLibraryRepository) current.dispose();
    super.dispose();
  }

  Future<void> _restoreAppearance() async {
    try {
      final stored = await preferences.loadAppearance(preferenceUserId);
      if (mounted && stored != null) {
        setState(() => appearance = stored);
      }
    } catch (_) {
      // App remains usable even if platform preferences are unavailable.
    }
  }

  Future<void> _changeAppearance(MediaFlowAppearance next) async {
    setState(() => appearance = next);
    try {
      await preferences.saveAppearance(preferenceUserId, next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save the appearance preference.')),
        );
      }
    }
  }

  static const primary = [
    MediaFlowSection.dashboard,
    MediaFlowSection.library,
    MediaFlowSection.logging,
    MediaFlowSection.personalOrder,
  ];

  void navigate(MediaFlowSection section) {
    if (selected == section) return;
    setState(() => selected = section);
  }

  void showMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('MORE IN MEDIAFLOW', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              )),
            ),
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

  Widget _page(BuildContext context) {
    final data = repository;
    // Device appearance and safety information remain usable while signed out.
    if (data == null && selected == MediaFlowSection.settings) {
      return NativeSettingsScreen(
        appearance: appearance,
        onAppearanceChanged: (value) => unawaited(_changeAppearance(value)),
      );
    }
    if (data != null) {
      switch (selected) {
        case MediaFlowSection.dashboard:
          return DashboardScreen(
            repository: data,
            openLibrary: () => navigate(MediaFlowSection.library),
            openHistory: () => navigate(MediaFlowSection.history),
          );
        case MediaFlowSection.library:
          return LibraryScreen(
            repository: data,
            workspace: data is SupabaseMediaFlowLibraryRepository
                ? data.editingWorkspace : null,
          );
        case MediaFlowSection.history:
          return HistoryScreen(repository: data);
        case MediaFlowSection.account:
          return AccountScreen(
            client: widget.client!,
            beforeSignOut: data is SupabaseMediaFlowLibraryRepository
                ? data.prepareSignOut : null,
          );
        case MediaFlowSection.settings:
          return NativeSettingsScreen(
            appearance: appearance,
            repository: data,
            nativeRepository: data is SupabaseMediaFlowLibraryRepository ? data : null,
            onAppearanceChanged: (value) => unawaited(_changeAppearance(value)),
          );
        case MediaFlowSection.collections:
          return CollectionsScreen(repository: data);
        case MediaFlowSection.statistics:
          return StatisticsScreen(repository: data);
        case MediaFlowSection.logging:
          return LoggingScreen(
            repository: data,
            workspace: data is SupabaseMediaFlowLibraryRepository
                ? data.editingWorkspace : null,
          );
        case MediaFlowSection.personalOrder:
          return PersonalOrderScreen(repository: data);
      }
    }
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(selected.label, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(
            data == null && selected == MediaFlowSection.library
                ? 'Sign in to browse your existing MediaFlow Library.'
                : 'Native implementation of this feature is not available yet.',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MediaFlowTheme.build(appearance),
      child: LayoutBuilder(builder: (context, constraints) {
        final desktop = constraints.maxWidth >= MediaFlowBreakpoints.desktop;
        final tablet = constraints.maxWidth >= MediaFlowBreakpoints.tablet && !desktop;
        final narrow = constraints.maxWidth < MediaFlowBreakpoints.compactPhone;
        return Scaffold(
          appBar: AppBar(
            title: Row(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/branding/mediaflow-launcher-512.png', width: 25, height: 25),
              const SizedBox(width: 9),
              const Text('MediaFlow'),
            ]),
            actions: [
              PopupMenuButton<MediaFlowAppearance>(
                tooltip: 'Appearance',
                icon: const Icon(Icons.palette_outlined),
                onSelected: (value) => unawaited(_changeAppearance(value)),
                itemBuilder: (_) => [
                  for (final value in MediaFlowAppearance.values)
                    PopupMenuItem(value: value, child: Text(value.name)),
                ],
              ),
            ],
          ),
          body: Column(children: [
            if (repository is SupabaseMediaFlowLibraryRepository)
              ValueListenableBuilder<NativeSnapshotSource>(
                valueListenable:
                    (repository! as SupabaseMediaFlowLibraryRepository).source,
                builder: (context, status, _) {
                  if (status != NativeSnapshotSource.offline &&
                      status != NativeSnapshotSource.recoveredPrevious) {
                    return const SizedBox.shrink();
                  }
                  return Material(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: Padding(
                      key: const Key('offline-readonly-banner'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8,
                      ),
                      child: Row(children: [
                        const Icon(Icons.cloud_off_outlined, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          status == NativeSnapshotSource.recoveredPrevious
                              ? 'Recovered older device copy — read-only. Refresh when online.'
                              : 'Offline device copy — read-only and possibly outdated.',
                        )),
                      ]),
                    ),
                  );
                },
              ),
            Expanded(child: Row(children: [
            if (desktop)
              SizedBox(
                width: 244,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: MediaFlowTokens.of(context).panel,
                    border: Border(right: BorderSide(
                      color: MediaFlowTokens.of(context).borderSoft)),
                  ),
                  child: ListView(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('ALEX GODLY', style: TextStyle(
                          fontSize: 10, letterSpacing: 2.0, fontWeight: FontWeight.w800,
                          color: MediaFlowTokens.of(context).accent,
                        )),
                        const SizedBox(height: 5),
                        Row(children: [
                          Image.asset('assets/branding/mediaflow-launcher-512.png', width: 26, height: 26),
                          const SizedBox(width: 9),
                          Text('MEDIAFLOW', style: Theme.of(context).textTheme.titleLarge),
                        ]),
                      ]),
                    ),
                    Divider(color: MediaFlowTokens.of(context).borderSoft),
                    const SizedBox(height: 8),
                    for (final section in MediaFlowSection.values)
                      MfNavigationTile(
                        key: ValueKey('nav-${section.name}'),
                        icon: section.icon,
                        label: section.label,
                        selected: selected == section,
                        onTap: () => navigate(section),
                      ),
                  ]),
                ),
              )
            else if (tablet)
              SingleChildScrollView(
                child: IntrinsicHeight(child: NavigationRail(
                key: const Key('tablet-navigation-rail'),
                selectedIndex: MediaFlowSection.values.indexOf(selected),
                onDestinationSelected: (index) =>
                    navigate(MediaFlowSection.values[index]),
                labelType: NavigationRailLabelType.selected,
                destinations: [
                  for (final section in MediaFlowSection.values)
                    NavigationRailDestination(
                      icon: Icon(section.icon),
                      label: Text(section.label),
                    ),
                ],
              ))),
            Expanded(child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: MediaFlowBreakpoints.contentMax),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: MediaFlowBreakpoints.pagePadding(constraints.maxWidth),
                  vertical: narrow ? 10 : 20,
                ),
                child: _page(context),
              ),
            ))),
          ])),
          ]),
          bottomNavigationBar: desktop || tablet ? null : NavigationBar(
            height: narrow ? 70 : 80,
            labelBehavior: narrow
                ? NavigationDestinationLabelBehavior.onlyShowSelected
                : NavigationDestinationLabelBehavior.alwaysShow,
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
