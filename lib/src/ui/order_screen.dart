import 'package:flutter/material.dart';

import '../data/account_controller.dart';
import 'widgets.dart';

/// Personal Order (being built for Beta 14).
class OrderScreen extends StatelessWidget {
  const OrderScreen({super.key, required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal Order'), actions: [SyncIndicator(account: account)]),
      body: const EmptyState(icon: Icons.construction_rounded, title: 'Personal Order', body: 'Coming in this update.'),
    );
  }
}
