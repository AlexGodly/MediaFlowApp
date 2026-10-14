import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/mediaflow_shell.dart';
import '../../services/mediaflow_auth.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth});
  final MediaFlowAuth auth;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: auth.changes,
      builder: (context, snapshot) {
        if (auth.user != null) {
          return MediaFlowShell(
            key: ValueKey('mediaflow-user-${auth.user!.id}'),
            client: auth.client,
          );
        }
        return SignInScreen(auth: auth);
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});
  final MediaFlowAuth auth;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool signup = false;
  bool busy = false;
  String? message;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!email.text.trim().contains('@')) {
      setState(() => message = 'Enter a valid email address.');
      return;
    }
    if (password.text.length < 6) {
      setState(() => message = 'Password must contain at least 6 characters.');
      return;
    }
    if (signup && password.text != confirmation.text) {
      setState(() => message = 'Passwords do not match.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      final result = signup
          ? await widget.auth.signUp(email.text, password.text)
          : await widget.auth.signIn(email.text, password.text);
      if (signup && result.session == null && mounted) {
        setState(() => message = 'Check your email to confirm your account.');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (_) {
      if (mounted) setState(() => message = 'Could not connect. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> requestPasswordReset() async {
    if (busy) return;
    if (!email.text.trim().contains('@')) {
      setState(() => message = 'Enter your email above, then request a reset.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      await widget.auth.resetPassword(email.text);
      if (mounted) {
        setState(() => message =
            'Password reset email requested. Check your inbox.');
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (_) {
      if (mounted) setState(() => message = 'Could not request a reset.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('MediaFlow', textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 12),
            Text(signup ? 'Create your account' : 'Welcome back',
              textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextField(controller: email, keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true,
              autofillHints: [signup ? AutofillHints.newPassword : AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Password')),
            if (signup) ...[
              const SizedBox(height: 12),
              TextField(controller: confirmation, obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'Confirm password')),
            ],
            if (message != null) Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(message!, textAlign: TextAlign.center)),
            const SizedBox(height: 20),
            FilledButton(onPressed: busy ? null : submit,
              child: Text(busy ? 'Please wait…' : signup ? 'Create account' : 'Log in')),
            TextButton(onPressed: busy ? null : () => setState(() {
              signup = !signup;
              message = null;
            }), child: Text(signup ? 'Already have an account? Log in' : 'Create account')),
            if (!signup) TextButton(
              onPressed: busy ? null : requestPasswordReset,
              child: const Text('Forgot password?'),
            ),
          ]),
        ),
      ),
    ),
  );
}
