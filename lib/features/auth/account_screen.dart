import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Native account management surface. Reads the existing identity, without
/// introducing new user tables or copying any application data.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.client});
  final SupabaseClient client;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool busy = false;
  String? message;

  Future<void> _resetPassword() async {
    final email = widget.client.auth.currentUser?.email;
    if (email == null || email.isEmpty || busy) return;
    setState(() { busy = true; message = null; });
    try {
      await widget.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        setState(() => message = 'Password reset email requested. Check your inbox.');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (_) {
      if (mounted) setState(() => message = 'Could not request reset. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signOut() async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try {
      await widget.client.auth.signOut();
    } on AuthException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (_) {
      if (mounted) setState(() => message = 'Could not sign out. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.client.auth.currentUser;
    final displayName = user?.userMetadata?['display_name']?.toString() ?? '';
    return ListView(children: [
      Text('Account', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 4),
      Text('Existing MediaFlow account',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      Card(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(radius: 26,
            child: Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'M')),
          const SizedBox(height: 14),
          Text(displayName.isEmpty ? 'MediaFlow user' : displayName,
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          SelectableText(user?.email ?? 'Email unavailable'),
          const SizedBox(height: 8),
          const Text('Your Library, History, and preferences remain in your '
            'original MediaFlow account. The native app does not create duplicate records.'),
        ]),
      )),
      const SizedBox(height: 12),
      Card(child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Security', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : _resetPassword,
            icon: const Icon(Icons.lock_reset_outlined),
            label: const Text('Email a password reset link'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy ? null : _signOut,
            icon: const Icon(Icons.logout),
            label: Text(busy ? 'Please wait…' : 'Sign out'),
          ),
          if (message != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message!, textAlign: TextAlign.center),
          ),
        ]),
      )),
    ]);
  }
}
