import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'presence.dart';
import 'theme.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, this.email, this.asRoute = false});

  /// Pre-filled email (signing in again after the session expired).
  final String? email;

  /// Opened on top of the app: closes itself after a successful sign-in.
  final bool asRoute;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final _email = TextEditingController(text: widget.email ?? '');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  bool _signup = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// The website's `friendlyAuthError`.
  static String _friendly(Object e) => (e is AuthException ? e.message : '$e')
      .replaceAll('Invalid login credentials', 'Incorrect email or password.')
      .replaceAll('User already registered', 'That email is already registered. Try logging in.');

  Future<void> _createAccount() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and a password.');
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final r = await Supabase.instance.client.auth.signUp(email: email, password: password, emailRedirectTo: kWebsiteUrl);
      if (r.session != null) {
        if (widget.asRoute && mounted) Navigator.of(context).pop(true);
      } else if (mounted) {
        setState(() {
          _signup = false;
          _password.clear();
          _confirm.clear();
          _notice = 'Account created. Check your email to confirm your account, then log in.';
        });
      }
    } on AuthException catch (e) {
      setState(() => _error = _friendly(e));
    } catch (e) {
      setState(() => _error = 'Could not reach MediaFlow. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final c = TextEditingController(text: _email.text.trim());
    String? error;
    var sending = false;
    final sent = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Reset your password'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text("Enter your account email and we'll send you a link to choose a new password.", style: TextStyle(color: MF.textDim)),
            const SizedBox(height: 12),
            TextField(controller: c, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: MF.bad))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      final email = c.text.trim();
                      if (email.isEmpty) {
                        set(() => error = 'Enter your account email.');
                        return;
                      }
                      set(() {
                        sending = true;
                        error = null;
                      });
                      try {
                        await Supabase.instance.client.auth.resetPasswordForEmail(email, redirectTo: kWebsiteUrl);
                        if (d.mounted) Navigator.pop(d, email);
                      } catch (e) {
                        set(() {
                          sending = false;
                          error = e is AuthException ? _friendly(e) : 'Could not reach MediaFlow. Check your connection and try again.';
                        });
                      }
                    },
              child: Text(sending ? 'Sending…' : 'Send reset email'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    if (sent != null && mounted) {
      setState(() {
        _email.text = sent;
        _error = null;
        _notice = 'Password reset email sent. Check your inbox.';
      });
    }
  }

  Future<void> _signIn() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
      if (widget.asRoute && mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      setState(() => _error = _friendly(e));
    } catch (e) {
      setState(() => _error = 'Could not reach MediaFlow. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PresenceScope(info: const PresenceInfo(situation: 'other'), child: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset('assets/branding/mediaflow-launcher-512.png', width: 88, height: 88),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('MediaFlow',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: MF.text)),
                  const SizedBox(height: 6),
                  Text(_signup ? 'Create your MediaFlow account' : 'Sign in with your MediaFlow account',
                      textAlign: TextAlign.center, style: TextStyle(color: MF.textDim)),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _hide,
                    autofillHints: _signup ? const [AutofillHints.newPassword] : const [AutofillHints.password],
                    onSubmitted: (_) => _signup ? _createAccount() : _signIn(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _hide ? 'Show password' : 'Hide password',
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  if (_signup) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: _hide,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: (_) => _createAccount(),
                      decoration: const InputDecoration(labelText: 'Confirm password'),
                    ),
                  ],
                  if (_notice != null) ...[
                    const SizedBox(height: 12),
                    Text(_notice!, style: const TextStyle(color: MF.good)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: MF.bad)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : (_signup ? _createAccount : _signIn),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(_signup ? 'Create account' : 'Sign in', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  if (!_signup)
                    TextButton(onPressed: _busy ? null : _forgot, child: const Text('Forgot password?')),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _signup = !_signup;
                              _error = null;
                              _notice = null;
                            }),
                    child: Text(_signup ? 'Already have an account? Sign in' : 'New to MediaFlow? Create an account'),
                  ),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(kWebsiteUrl), mode: LaunchMode.externalApplication),
                    child: const Text('Open the MediaFlow website'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }
}
