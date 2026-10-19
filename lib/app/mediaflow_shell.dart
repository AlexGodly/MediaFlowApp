// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/mediaflow_library_repository.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/history/history_screen.dart';
import '../features/auth/account_screen.dart';
import '../services/native_preferences.dart';
import '../services/native_m36_dashboard_tools.dart';
import '../services/native_m37_library_plan.dart';
import '../services/native_m40_collection_plan.dart';
import '../services/native_m44_personal_order_plan.dart';
import '../services/native_m51_task_handoff.dart';
import '../features/settings/native_settings_screen.dart';
import '../features/collections/collections_screen.dart';
import '../features/statistics/statistics_screen.dart';
import '../features/personal_order/personal_order_screen.dart';
import '../features/logging/logging_screen.dart';
import '../features/logging/r2_advanced_logging_drafts.dart';
import '../features/logging/r2_advanced_logging_screen.dart';
import '../features/library/library_screen.dart';
import '../features/website/native_website_workspaces.dart';
import '../design_system/mediaflow_theme.dart';
import '../design_system/mediaflow_components.dart';
import '../design_system/mediaflow_ambience.dart';
import '../design_system/mediaflow_cloud_indicator.dart';

enum MediaFlowSection {
  dashboard('Dashboard', Icons.space_dashboard_outlined),
  library('Library', Icons.local_library_outlined),
  logging('Logging', Icons.edit_note_outlined),
  personalOrder('Personal Order', Icons.format_list_numbered_outlined),
  collections('Collections', Icons.collections_bookmark_outlined),
  history('History', Icons.history),
  statistics('Statistics', Icons.bar_chart_outlined),
  account('Account', Icons.person_outline),
  settings('Settings', Icons.settings_outlined),
  oldSystem('Old System', Icons.sync_alt_outlined),
  freshReleases('Fresh Episodes', Icons.live_tv_outlined),
  recovery('Background Processes', Icons.auto_fix_high_outlined),
  themes('Theme Studio', Icons.palette_outlined),
  about('About', Icons.info_outline);
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

class _MediaFlowShellState extends State<MediaFlowShell> with WidgetsBindingObserver {
  MediaFlowSection selected = MediaFlowSection.dashboard;
  int _refreshEpoch = 0;
  DateTime? _lastForegroundRead;
  MediaFlowAppearance appearance = MediaFlowAppearance.dark;
  final NativePreferences preferences = NativePreferences();
  late final MediaFlowLibraryRepository? repository;
  late final NativeM36DashboardToolsController dashboardTools;
  late final NativeM37LibraryPlan? libraryPlan;
  late final NativeM40CollectionPlan? collectionPlan;
  late final NativeM44PersonalOrderPlan? personalOrderPlan;
  late final NativeM51TaskHandoff? taskHandoff;
  late final R2AdvancedLoggingDrafts r2Drafts;

  String? get preferenceUserId => widget.client?.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastForegroundRead = DateTime.now();
    dashboardTools = NativeM36DashboardToolsController();
    r2Drafts = R2AdvancedLoggingDrafts();
    final ownerId = widget.client?.auth.currentUser?.id;
    libraryPlan = ownerId == null ? null
        : NativeM37LibraryPlan(ownerId: ownerId);
    collectionPlan = ownerId == null ? null
        : NativeM40CollectionPlan(ownerId: ownerId);
    personalOrderPlan = ownerId == null ? null
        : NativeM44PersonalOrderPlan(ownerId: ownerId);
    taskHandoff = ownerId == null ? null
        : NativeM51TaskHandoff(ownerId: ownerId);
    repository = widget.client == null
        ? null : SupabaseMediaFlowLibraryRepository(widget.client!);
    unawaited(_restoreAppearance());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final current = repository;
    if (current is SupabaseMediaFlowLibraryRepository) current.dispose();
    dashboardTools.dispose();
    r2Drafts.dispose();
    libraryPlan?.dispose();
    collectionPlan?.dispose();
    personalOrderPlan?.dispose();
    taskHandoff?.dispose();
    super.dispose();
  }

  /// Resume refresh is read-only, bounded and never replaces an active edit
  /// surface. It does not upload drafts or synchronize cloud writes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || repository == null) return;
    final now = DateTime.now();
    if (_lastForegroundRead != null &&
        now.difference(_lastForegroundRead!) < const Duration(minutes: 15)) {
      return;
    }
    _lastForegroundRead = now;
    unawaited(_syncCurrentPage(silent: true));
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

  Future<void> _syncCurrentPage({bool silent = false}) async {
    final data = repository;
    if (data == null) return;
    try {
      await data.reload();
      if (!mounted) return;
      // Never unmount an in-progress form during an automatic foreground read.
      final draftSurface = selected == MediaFlowSection.logging ||
          selected == MediaFlowSection.library ||
          selected == MediaFlowSection.collections ||
          selected == MediaFlowSection.personalOrder ||
          selected == MediaFlowSection.settings;
      if (!silent || !draftSurface) setState(() => _refreshEpoch++);
      if (silent) return;
      final cloud = data is SupabaseMediaFlowLibraryRepository &&
          nativeCloudSourceOnline(data.source.value);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(cloud
            ? 'Latest cloud snapshot loaded (read-only).'
            : 'Cloud unavailable; showing a protected device copy.'),
      ));
    } catch (_) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cloud refresh failed; no account data was overwritten.')));
    }
  }

  void navigate(MediaFlowSection section) {
    if (selected == section) return;
    setState(() => selected = section);
  }

  Future<void> _openWorkspaceSearch() async {
    final destination = await showSearch<MediaFlowSection?>(
      context: context, delegate: _MediaFlowNavigationSearch());
    if (mounted && destination != null) navigate(destination);
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
            ListTile(
              leading: const Icon(Icons.manage_search_outlined),
              title: const Text('Find any workspace'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openWorkspaceSearch();
              },
            ),
            if (repository is SupabaseMediaFlowLibraryRepository)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Align(alignment: Alignment.centerLeft,
                  child: MfCloudIndicator(
                    repository: repository! as SupabaseMediaFlowLibraryRepository,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      navigate(MediaFlowSection.settings);
                    },
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
            dashboardTools: dashboardTools,
            personalOrderPlan: personalOrderPlan,
            openPersonalOrder: () => navigate(MediaFlowSection.personalOrder),
            onReviewTaskInLogging: taskHandoff==null ? null : (catalog) {
              try {
                taskHandoff!.request(catalog,
                  currentOwnerId:preferenceUserId??'');
                navigate(MediaFlowSection.logging);
              } on StateError {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:Text('Task handoff unavailable. '
                    'Refresh the Dashboard and verify the Library ID.')));
              }
            },
          );
        case MediaFlowSection.library:
          return LibraryScreen(
            repository: data,
            changePlan: libraryPlan,
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
            onCloudRefresh: () => unawaited(_syncCurrentPage()),
            onAppearanceChanged: (value) => unawaited(_changeAppearance(value)),
          );
        case MediaFlowSection.collections:
          return CollectionsScreen(repository: data, plan: collectionPlan);
        case MediaFlowSection.statistics:
          return StatisticsScreen(repository: data);
        case MediaFlowSection.logging:
          return R2AdvancedLoggingScreen(
            repository: data,
            drafts: r2Drafts,
            openLegacyBrowser: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Logging Library Browser')),
                body: Padding(
                  padding: const EdgeInsets.all(12),
                  child: LoggingScreen(
                    repository: data,
                    workspace: data is SupabaseMediaFlowLibraryRepository
                        ? data.editingWorkspace : null,
                    taskHandoff:taskHandoff,
                    currentOwnerId:preferenceUserId ?? '',
                  ),
                ),
              )),
            ),
          );
        case MediaFlowSection.oldSystem:
          return NativeWebsiteCatalogWorkspace(
            repository: data, kind: WebsiteWorkspaceKind.oldSystem);
        case MediaFlowSection.freshReleases:
          return NativeWebsiteCatalogWorkspace(
            repository: data, kind: WebsiteWorkspaceKind.freshReleases);
        case MediaFlowSection.recovery:
          return NativeWebsiteCatalogWorkspace(
            repository: data, kind: WebsiteWorkspaceKind.recovery);
        case MediaFlowSection.themes:
          return NativeWebsiteThemeScreen(
            appearance: appearance,
            onChanged: (value) => unawaited(_changeAppearance(value)));
        case MediaFlowSection.about:
          return const NativeWebsiteAboutScreen();
        case MediaFlowSection.personalOrder:
          return PersonalOrderScreen(
            repository: data,plan: personalOrderPlan,
            currentOwnerId: preferenceUserId ?? '');
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
        final narrow = constraints.maxWidth < MediaFlowBreakpoints.compactPhone;
        return Scaffold(
          appBar: desktop ? null : AppBar(
            title: Row(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/branding/mediaflow-launcher-512.png', width: 25, height: 25),
              const SizedBox(width: 9),
              const Text('MediaFlow'),
            ]),
            actions: [
              IconButton(
                key: const ValueKey('workspace-search-mobile'),
                tooltip: 'Find a workspace',
                onPressed: _openWorkspaceSearch,
                icon: const Icon(Icons.search),
              ),
              if (repository != null)
                IconButton(
                  tooltip: 'Refresh cloud data (read-only)',
                  onPressed: _syncCurrentPage,
                  icon: const Icon(Icons.cloud_sync_outlined),
                ),
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
          body: MfAmbientBackdrop(child: Column(children: [
            if (repository is SupabaseMediaFlowLibraryRepository)
              ValueListenableBuilder<NativeSnapshotSource>(
                valueListenable:
                    (repository! as SupabaseMediaFlowLibraryRepository).source,
                builder: (context, status, _) {
                  if (status != NativeSnapshotSource.offline &&
                      status != NativeSnapshotSource.recoveredPrevious &&
                      status != NativeSnapshotSource.offlineMemory &&
                      status != NativeSnapshotSource.invalidCloud &&
                      status != NativeSnapshotSource.cloudNotCached) {
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
                              : status == NativeSnapshotSource.offlineMemory
                                  ? 'Offline in-memory copy — read-only; not saved to device.'
                                  : status == NativeSnapshotSource.invalidCloud
                                      ? 'Cloud snapshot missing or invalid — recovery blocked.'
                                      : status == NativeSnapshotSource.cloudNotCached
                                          ? 'Cloud loaded, but encrypted offline caching failed.'
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
                        Text('CONSUMPTION ROTATION', style: TextStyle(
                          fontSize: 10, letterSpacing: 2.0, fontWeight: FontWeight.w800,
                          color: MediaFlowTokens.of(context).accent,
                        )),
                        const SizedBox(height: 5),
                        Row(children: [
                          Image.asset('assets/branding/mediaflow-launcher-512.png', width: 26, height: 26),
                          const SizedBox(width: 9),
                          Expanded(child: Text('MEDIAFLOW', maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: MediaFlowTokens.of(context).text,
                              fontWeight: FontWeight.w800, fontSize: 17))),
                        ]),
                      ]),
                    ),
                    Divider(color: MediaFlowTokens.of(context).borderSoft),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: OutlinedButton.icon(
                        key: const ValueKey('workspace-search-desktop'),
                        onPressed: _openWorkspaceSearch,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Find workspace'),
                      ),
                    ),
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
              ),
            Expanded(child: Column(children: [
              if (desktop) Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: MediaFlowTokens.of(context).panel,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: MediaFlowTokens.of(context).border)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 8),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: MediaFlowTokens.of(context).accent
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10)),
                        child: Icon(selected.icon,
                          color: MediaFlowTokens.of(context).accent, size: 19)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selected.label, style: const TextStyle(
                            fontWeight: FontWeight.w700)),
                          Text('MediaFlow · native website workspace',
                            style: Theme.of(context).textTheme.bodySmall),
                        ])),
                      if (repository is SupabaseMediaFlowLibraryRepository) ...[
                        MfCloudIndicator(
                          repository: repository! as SupabaseMediaFlowLibraryRepository,
                          compact: true,
                          onTap: () => navigate(MediaFlowSection.settings),
                        ),
                        const SizedBox(width: 10),
                      ],
                      OutlinedButton.icon(
                        onPressed: _syncCurrentPage,
                        icon: const Icon(Icons.sync, size: 17),
                        label: const Text('Refresh Cloud')),
                    ]),
                  ),
                )),
              Expanded(child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: MediaFlowBreakpoints.contentMax),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaFlowBreakpoints.pagePadding(
                      constraints.maxWidth),
                    vertical: narrow ? 10 : 20),
                  child: KeyedSubtree(
                    key: ValueKey(selected.name + '_' + _refreshEpoch.toString()),
                    child: _page(context)),
                ),
              ))),
            ])),
          ])),
          ])),
          bottomNavigationBar: desktop ? null : NavigationBar(
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

/// Search all native destinations without requiring the user to hunt through
/// the mobile More sheet or the full-height desktop sidebar.
class _MediaFlowNavigationSearch extends SearchDelegate<MediaFlowSection?> {
  _MediaFlowNavigationSearch() : super(searchFieldLabel: 'Find a MediaFlow workspace');

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear search',
        icon: const Icon(Icons.close),
        onPressed: () => query = '',
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: 'Close search',
    icon: const Icon(Icons.arrow_back),
    onPressed: () => close(context, null),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final matches = MediaFlowSection.values.where((section) =>
        normalized.isEmpty ||
        section.label.toLowerCase().contains(normalized)).toList();
    if (matches.isEmpty) {
      return const MfEmptyState(
        title: 'No matching workspace',
        message: 'Try Library, Logging, Collections, Theme Studio or Settings.',
        icon: Icons.search_off_outlined,
      );
    }
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final section = matches[index];
        return ListTile(
          key: ValueKey('search-${section.name}'),
          leading: Icon(section.icon),
          title: Text(section.label),
          trailing: const Icon(Icons.arrow_outward, size: 17),
          onTap: () => close(context, section),
        );
      },
    );
  }
}
