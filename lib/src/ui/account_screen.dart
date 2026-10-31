import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/account_controller.dart';
import 'theme.dart';
import 'widgets.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.account});
  final AccountController account;

  Future<void> _signOut(BuildContext context) async {
    if (account.pendingCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Logs not synced yet'),
          content: Text('${account.pendingCount} log${account.pendingCount == 1 ? ' has' : 's have'} not reached your '
              'account yet. Signing out removes ${account.pendingCount == 1 ? 'it' : 'them'} from this device.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep me signed in')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await account.forget();
    await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final view = account.view!;
    final name = view.profileName.isNotEmpty ? view.profileName : account.email;
    final completed = view.library.where((t) => t.isCompleted).length;
    final active = view.library.where((t) => t.status == 'active').length;
    final last = account.lastSynced;
    final statusText = switch (account.status) {
      SyncState.synced => last == null ? 'Synced' : 'Synced at ${TimeOfDay.fromDateTime(last).format(context)}',
      SyncState.syncing => 'Syncing…',
      SyncState.offline => account.message ?? 'Offline',
      SyncState.error => account.message ?? 'Sync problem',
      SyncState.loading => 'Loading…',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Account'), actions: [SyncIndicator(account: account)]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: MF.accentSoft,
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: MF.accent)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    if (account.email.isNotEmpty && account.email != name)
                      Text(account.email, style: const TextStyle(color: MF.textDim)),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _Tile(label: 'Titles', value: fmtNumber(view.library.length)),
            const SizedBox(width: 8),
            _Tile(label: 'In progress', value: fmtNumber(active)),
            const SizedBox(width: 8),
            _Tile(label: 'Completed', value: fmtNumber(completed)),
          ]),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('Sync'),
                subtitle: Text(statusText),
                trailing: account.status == SyncState.syncing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(onPressed: account.sync, child: const Text('Sync now')),
              ),
              if (account.pendingCount > 0)
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined, color: MF.warn),
                  title: Text('${account.pendingCount} log${account.pendingCount == 1 ? '' : 's'} waiting to upload'),
                  subtitle: const Text('Saved on this device. They upload automatically when online.'),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open the MediaFlow website'),
                subtitle: const Text('Dashboard, Collections, Statistics and Settings are coming to the app next'),
                onTap: () => launchUrl(Uri.parse(kWebsiteUrl), mode: LaunchMode.externalApplication),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: MF.bad),
                title: const Text('Sign out'),
                onTap: () => _signOut(context),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text('MediaFlow $kAppVersionLabel', style: TextStyle(color: MF.textDim, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: MF.textDim, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
