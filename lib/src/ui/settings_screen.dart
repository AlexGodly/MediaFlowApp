import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import 'widgets.dart';

/// Settings (being built for Beta 14).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), actions: [SyncIndicator(account: account)]),
      body: const EmptyState(icon: Icons.construction_rounded, title: 'Settings', body: 'Coming in this update.'),
    );
  }
}
