import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import 'account_screen.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'log_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.account});
  final AccountController account;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _destinations = [
    (Icons.video_library_outlined, Icons.video_library, 'Library'),
    (Icons.history_rounded, Icons.history_rounded, 'History'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Account'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.account,
      builder: (context, _) {
        final account = widget.account;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final pages = [
          LibraryScreen(account: account),
          HistoryScreen(account: account),
          AccountScreen(account: account),
        ];
        final body = !account.hasData
            ? _Loading(account: account)
            : IndexedStack(index: _tab, children: pages);
        final fab = account.hasData && _tab < 2
            ? FloatingActionButton.extended(
                onPressed: () => showLogSheet(context, account),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Log', style: TextStyle(fontWeight: FontWeight.w800)),
              )
            : null;
        if (wide) {
          return Scaffold(
            floatingActionButton: fab,
            body: Row(children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset('assets/branding/mediaflow-launcher-512.png', width: 40, height: 40),
                  ),
                ),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ]),
          );
        }
        return Scaffold(
          floatingActionButton: fab,
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              for (final d in _destinations)
                NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
            ],
          ),
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
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
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Loading your MediaFlow…', style: TextStyle(color: MF.textDim)),
      ]),
    );
  }
}
