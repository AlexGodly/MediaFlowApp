import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import 'widgets.dart';

/// Collections (being built for Beta 14).
class CollectionsScreen extends StatelessWidget {
  const CollectionsScreen({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collections'), actions: [SyncIndicator(account: account)]),
      body: const EmptyState(icon: Icons.construction_rounded, title: 'Collections', body: 'Coming in this update.'),
    );
  }
}
