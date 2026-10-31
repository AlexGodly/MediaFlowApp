import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import 'widgets.dart';

/// Statistics (being built for Beta 14).
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics'), actions: [SyncIndicator(account: account)]),
      body: const EmptyState(icon: Icons.construction_rounded, title: 'Statistics', body: 'Coming in this update.'),
    );
  }
}
