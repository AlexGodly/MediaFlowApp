import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import '../platform/app_shortcuts.dart';
import 'account_screen.dart';
import 'app_nav.dart';
import 'collections_screen.dart';
import 'extras_screen.dart';
import 'floating_dock.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'log_screen.dart';
import 'log_sheet.dart' show showLogSheet;
import 'order_screen.dart';
import 'old_system_screen.dart';
import 'presence.dart';
import 'recovery_screen.dart' show RecoveryScreen, openRecovery;
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'theme.dart';
import 'theme_controller.dart' show CoverBackdrop;
import 'title_screen.dart' show TitleEditor;
import 'widgets.dart';

/// The app's sections. Phones show the dock pages + More, wide screens list
/// every section in a side rail; both are arranged in Settings → Navigation
/// (app_nav.dart). The lists below are the defaults.
enum Section {
  log(Icons.edit_note_outlined, Icons.edit_note_rounded, 'Log'),
  library(Icons.video_library_outlined, Icons.video_library, 'Library'),
  history(Icons.history_rounded, Icons.history_rounded, 'History'),
  extras(Icons.timer_outlined, Icons.timer_rounded, 'Extras'),
  collections(Icons.collections_bookmark_outlined, Icons.collections_bookmark_rounded, 'Collections'),
  order(Icons.format_list_numbered_rounded, Icons.format_list_numbered_rounded, 'Personal Order'),
  oldSystem(Icons.swap_horiz_rounded, Icons.swap_horiz_rounded, 'Old System'),
  recovery(Icons.healing_outlined, Icons.healing_rounded, 'Recovery Workspace'),
  rate(Icons.star_outline_rounded, Icons.star_rounded, 'Rate Your Library'),
  covers(Icons.image_not_supported_outlined, Icons.image_not_supported_rounded, 'Missing Covers'),
  stats(Icons.insights_outlined, Icons.insights_rounded, 'Statistics'),
  settings(Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  account(Icons.person_outline_rounded, Icons.person_rounded, 'Account');

  const Section(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  static const phoneTabs = [Section.log, Section.library, Section.history, Section.extras];
  static const more = [
    Section.collections,
    Section.order,
    Section.oldSystem,
    Section.recovery,
    Section.rate,
    Section.covers,
    Section.stats,
    Section.settings,
    Section.account,
  ];
}

Widget sectionPage(Section s, AccountController account) => switch (s) {
      Section.log => LogScreen(account: account),
      Section.library => LibraryScreen(account: account),
      Section.history => HistoryScreen(account: account),
      Section.extras => ExtrasScreen(account: account),
      Section.collections => CollectionsScreen(account: account),
      Section.order => OrderScreen(account: account),
      Section.oldSystem => OldSystemScreen(account: account),
      Section.recovery => RecoveryScreen(account: account),
      Section.rate => RateLibraryScreen(account: account),
      Section.covers => MissingCoversScreen(account: account),
      Section.stats => StatsScreen(account: account),
      Section.settings => SettingsScreen(account: account),
      Section.account => AccountScreen(account: account),
    };

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.account, this.start = Section.log});
  final AccountController account;
  final Section start;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late Section _section = widget.start;
  bool _moreOpen = false;

  // Each page is built once and kept (with its scroll position and filters);
  // only the page on screen listens to account changes.
  final Map<Section, Widget> _pages = {};
  final Set<Section> _visited = {};

  Widget _page(Section s) => _pages[s] ??= sectionPage(s, widget.account);

  @override
  void dispose() {
    AppShortcuts.instance.request.removeListener(_onShortcut);
    if (RecoveryScreen.goToPage == _goRecovery) RecoveryScreen.goToPage = null;
    LibraryScreen.showCategory.removeListener(_goLibrary);
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeShell old) {
    super.didUpdateWidget(old);
    if (!identical(old.account, widget.account)) _pages.clear();
  }

  void _goLibrary() {
    if (mounted && LibraryScreen.showCategory.value != null) _go(Section.library);
  }

  void _goRecovery() {
    if (mounted) _go(Section.recovery);
  }

  void _go(Section s) => setState(() {
        _section = s;
        _moreOpen = false;
      });

  // App-icon shortcuts and the home-screen widget.
  @override
  void initState() {
    super.initState();
    AppShortcuts.instance.request.addListener(_onShortcut);
    RecoveryScreen.goToPage = _goRecovery;
    LibraryScreen.showCategory.addListener(_goLibrary);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShortcut());
  }

  int _shortcutSeen = 0;
  void _onShortcut() {
    final r = AppShortcuts.instance.request.value;
    if (r == null || r.$2 <= _shortcutSeen || !mounted) return;
    _shortcutSeen = r.$2;
    final account = widget.account;
    switch (r.$1) {
      case 'log':
        _go(Section.log);
      case 'library':
        _go(Section.library);
      case 'add':
        if (account.hasData) Navigator.of(context).push(MaterialPageRoute(builder: (_) => TitleEditor(account: account)));
      case 'recovery':
        if (account.hasData) openRecovery(context, account);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.account,
      builder: (context, _) {
        final account = widget.account;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final nav = AppNav.of(account.view?.state['settings'] as Map<String, dynamic>?);
        final dock = nav.dock;
        final showMore = !wide && _moreOpen;
        // Discord Rich Presence follows the section on screen.
        PresenceHub.instance.setSection(_section, account.view);
        final visible = Section.values;
        if (!showMore) _visited.add(_section);
        final body = !account.hasData
            ? _Loading(account: account)
            : IndexedStack(
                index: showMore ? visible.length : visible.indexOf(_section),
                children: [
                  for (final s in visible)
                    _visited.contains(s) ? _PageGate(active: !showMore && s == _section, child: _page(s)) : const SizedBox.shrink(),
                  MoreScreen(onOpen: _go, sections: nav.more),
                ],
              );
        // The website's floating + (v397 dock) on every main screen.
        final fab = account.hasData && !showMore
            ? DockButton(
                account: account,
                extras: _section == Section.log,
                commands: DockCommands(
                  openLogging: () {
                    _go(Section.log);
                    FloatingDock.openLoggingLibrary.value++;
                  },
                  openCollections: () => _go(Section.collections),
                  openBatchLog: () => showLogSheet(context, account),
                ),
                onAddTitle: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TitleEditor(account: account))),
                onAddCollection: () async {
                  final before = (account.view?.state['collections'] as List?)?.length ?? 0;
                  await editCollection(context, account, null);
                  final after = (account.view?.state['collections'] as List?)?.length ?? 0;
                  if (after > before) _go(Section.collections);
                },
                onRecovery: (mode) => openRecovery(context, account, tab: mode == 'metadata' ? 1 : 0, combined: mode == 'both'),
              )
            : null;
        final withWidget = account.hasData
            ? Stack(fit: StackFit.expand, children: [
                body,
                BackgroundProcesses(
                  account: account,
                  onOpen: (mode) => openRecovery(context, account, tab: mode == 'metadata' ? 1 : 0),
                  onSettings: () => openRecovery(context, account, tab: 2),
                ),
              ])
            : body;
        if (wide) {
          return Scaffold(
            floatingActionButton: fab,
            body: CoverBackdrop(
              child: Row(children: [
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: nav.desktop.indexOf(_section),
                      onDestinationSelected: (i) => _go(nav.desktop[i]),
                      labelType: NavigationRailLabelType.all,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset('assets/branding/mediaflow-launcher-512.png', width: 40, height: 40),
                        ),
                      ),
                      destinations: [
                        for (final d in nav.desktop)
                          NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
                      ],
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: withWidget),
              ]),
            ),
          );
        }
        final tabIndex = showMore || !dock.contains(_section) ? dock.length : dock.indexOf(_section);
        return PopScope(
          canPop: !showMore && dock.contains(_section),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            setState(() => _moreOpen = !_moreOpen && !dock.contains(_section));
          },
          child: Scaffold(
            floatingActionButton: fab,
            body: CoverBackdrop(child: withWidget),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tabIndex,
              onDestinationSelected: (i) {
                if (i == dock.length) {
                  setState(() => _moreOpen = true);
                } else {
                  _go(dock[i]);
                }
              },
              destinations: [
                for (final d in dock)
                  NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
                const NavigationDestination(icon: Icon(Icons.menu_rounded), selectedIcon: Icon(Icons.menu_open_rounded), label: 'More'),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tells a kept page whether it is on screen (pauses its tickers when not).
class _PageGate extends StatefulWidget {
  const _PageGate({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_PageGate> createState() => _PageGateState();
}

class _PageGateState extends State<_PageGate> {
  late final ValueNotifier<bool> _active = ValueNotifier(widget.active);

  @override
  void didUpdateWidget(_PageGate old) {
    super.didUpdateWidget(old);
    _active.value = widget.active;
  }

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      PageActivity(active: _active, child: TickerMode(enabled: widget.active, child: widget.child));
}

/// The "More" tab on phones.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.onOpen, this.sections = Section.more});
  final ValueChanged<Section> onOpen;
  final List<Section> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final s in sections)
            ListTile(
              leading: Icon(s.icon, color: MF.accent),
              title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onOpen(s),
            ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    if (account.missingAccountData) return _NewAccount(account: account);
    if (account.status == SyncState.error || account.status == SyncState.offline) {
      return SafeArea(
        child: Column(children: [
          const Spacer(),
          EmptyState(
            icon: account.status == SyncState.offline ? Icons.cloud_off_outlined : Icons.error_outline_rounded,
            title: account.status == SyncState.offline ? 'You are offline' : 'Could not load your MediaFlow',
            body: account.message,
          ),
          FilledButton(onPressed: account.sync, child: const Text('Try again')),
          const Spacer(),
        ]),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Loading your MediaFlow…', style: TextStyle(color: MF.textDim)),
      ]),
    );
  }
}

/// A new account (signed up, never opened): create its MediaFlow data the way
/// the website does on its first visit.
class _NewAccount extends StatefulWidget {
  const _NewAccount({required this.account});
  final AccountController account;

  @override
  State<_NewAccount> createState() => _NewAccountState();
}

class _NewAccountState extends State<_NewAccount> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.auto_awesome_rounded, size: 48, color: MF.accent),
              const SizedBox(height: 12),
              const Text('Welcome to MediaFlow', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('Your account is ready. Set up your MediaFlow with the default categories and settings; '
                  'you can change everything later, here or on the website.',
                  textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                          _error = null;
                        });
                        final e = await widget.account.createAccountData();
                        if (mounted) {
                          setState(() {
                            _busy = false;
                            _error = e;
                          });
                        }
                      },
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('Set up my MediaFlow', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: MF.bad))),
            ]),
          ),
        ),
      ),
    );
  }
}
