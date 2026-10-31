import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import 'widgets.dart';

/// Extras (being built for Beta 14).
class ExtrasScreen extends StatelessWidget {
  const ExtrasScreen({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Extras'), actions: [SyncIndicator(account: account)]),
      body: const EmptyState(icon: Icons.construction_rounded, title: 'Extras', body: 'Coming in this update.'),
    );
  }
}
