import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/account_controller.dart';
import '../util/js.dart';
import 'account_identity.dart';
import 'app.dart';
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
          content: Text('${account.pendingCount} change${account.pendingCount == 1 ? ' has' : 's have'} not reached your '
              'account yet. Signing out removes ${account.pendingCount == 1 ? 'it' : 'them'} from this device.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep me signed in')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await AuthGate.signOut(account);
  }

  @override
  Widget build(BuildContext context) {
    final view = account.view!;
    final name = accountDisplayName(account); // v565: the name, not the email, when there is one
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
                AccountAvatar(account: account),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    if (account.email.isNotEmpty && account.email != name)
                      Text(account.email, style: TextStyle(color: MF.textDim)),
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
          _AccountDetails(account: account),
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
                  title: Text('${account.pendingCount} change${account.pendingCount == 1 ? '' : 's'} waiting to upload'),
                  subtitle: const Text('Saved on this device. They upload automatically when online.'),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open the MediaFlow website'),
                subtitle: const Text('Same account, same data as the app'),
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
          Center(
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
            Text(label, style: TextStyle(color: MF.textDim, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

/// v565: everything the website's Account page edits (same Supabase calls):
/// name (display_name), profile picture link (the account's profilePicture),
/// email (confirmed by email), password, and deleting the account.
class _AccountDetails extends StatefulWidget {
  const _AccountDetails({required this.account});
  final AccountController account;

  @override
  State<_AccountDetails> createState() => _AccountDetailsState();
}

class _AccountDetailsState extends State<_AccountDetails> {
  late final _name = TextEditingController(text: jsStr(_auth.currentUser?.userMetadata?['display_name']));
  late final _picture = TextEditingController(text: jsStr(widget.account.view?.state['profilePicture']).startsWith('data:') ? '' : jsStr(widget.account.view?.state['profilePicture']));
  late final _email = TextEditingController(text: widget.account.email);
  final _password = TextEditingController(), _confirm = TextEditingController();
  String _busy = '';

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  void dispose() {
    for (final c in [_name, _picture, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _say(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(String what, Future<String> Function() action) async {
    setState(() => _busy = what);
    try {
      _say(await action());
    } on AuthException catch (e) {
      _say(e.message);
    } catch (e) {
      _say('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _saveName() => _run('name', () async {
        final name = _name.text.trim();
        await _auth.updateUser(UserAttributes(data: {'display_name': name.isEmpty ? null : name}));
        return name.isEmpty ? 'Name removed. Your email will be shown instead.' : 'Name updated successfully.';
      });

  Future<void> _savePicture() => _run('picture', () async {
        final url = _picture.text.trim();
        if (url.isNotEmpty && !(Uri.tryParse(url)?.hasScheme ?? false)) throw Exception('Enter a full image link (https://…).');
        await widget.account.edit((s, now) {
          if (url.isEmpty) {
            s.remove('profilePicture');
          } else {
            s['profilePicture'] = url;
          }
        }, label: 'Profile picture');
        return url.isEmpty ? 'Profile picture removed.' : 'Profile picture saved.';
      });

  Future<void> _saveEmail() => _run('email', () async {
        final email = _email.text.trim();
        if (email.isEmpty || !email.contains('@')) throw Exception('Enter a valid email address.');
        if (email == widget.account.email.trim()) throw Exception('That is already your current email.');
        await _auth.updateUser(UserAttributes(email: email));
        return 'Email update requested. Check your email and follow the confirmation link.';
      });

  Future<void> _savePassword() => _run('password', () async {
        final password = _password.text, confirm = _confirm.text;
        if (password.length < 6) throw Exception('Password must be at least 6 characters.');
        if (password != confirm) throw Exception('Passwords do not match.');
        await _auth.updateUser(UserAttributes(password: password));
        _password.clear();
        _confirm.clear();
        return 'Password updated successfully.';
      });

  Future<void> _delete() async {
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Delete your account?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This permanently deletes your MediaFlow account and all its cloud data: Library, History, '
                'Collections, settings and XP, on the website and in every app. It cannot be undone.'),
            const SizedBox(height: 12),
            const Text('Type DELETE to confirm.'),
            TextField(controller: typed, autofocus: true, onChanged: (_) => set(() {})),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep my account')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: MF.bad),
              onPressed: typed.text.trim() == 'DELETE' ? () => Navigator.pop(d, true) : null,
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );
    typed.dispose();
    if (ok != true) return;
    setState(() => _busy = 'delete');
    try {
      await Supabase.instance.client.rpc('delete_my_account');
      await AuthGate.signOut(widget.account);
    } catch (e) {
      _say('Account deletion was not completed. Your account was not deleted. ($e)');
      if (mounted) setState(() => _busy = '');
    }
  }

  Widget _row(TextEditingController c, String label, String key, VoidCallback save,
          {TextInputType? type, bool obscure = false, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: c,
              keyboardType: type,
              obscureText: obscure,
              decoration: InputDecoration(labelText: label, hintText: hint),
            ),
          ),
          const SizedBox(width: 8),
          _busy == key
              ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton(onPressed: _busy.isEmpty ? save : null, child: const Text('Save')),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Account details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          _row(_name, 'Name', 'name', _saveName, hint: 'Shown instead of your email'),
          _row(_picture, 'Profile picture link', 'picture', _savePicture, type: TextInputType.url, hint: 'https://…'),
          _row(_email, 'Email', 'email', _saveEmail, type: TextInputType.emailAddress),
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
          _row(_confirm, 'Confirm new password', 'password', _savePassword, obscure: true),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_forever_rounded, color: MF.bad),
            title: const Text('Delete account', style: TextStyle(color: MF.bad, fontWeight: FontWeight.w700)),
            subtitle: const Text('Permanently deletes your account and all its data.'),
            enabled: _busy.isEmpty,
            onTap: _delete,
          ),
        ]),
      ),
    );
  }
}
