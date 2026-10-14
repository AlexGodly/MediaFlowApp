import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/mediaflow_shell.dart';
import '../../services/mediaflow_auth.dart';
import '../../services/native_m35_auth_recovery.dart';

/// Owns the passwordRecovery event until the user explicitly completes the
/// password change. Token refreshes and userUpdated events cannot accidentally
/// bypass the form into the authenticated workspace.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth});
  final MediaFlowAuth auth;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _subscription;
  String? _recoveryOwner;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription = widget.auth.changes.listen((event) {
      if (!mounted) return;
      final owner = widget.auth.user?.id;
      if (event.event == AuthChangeEvent.passwordRecovery && owner != null) {
        setState(() => _recoveryOwner = owner);
      } else if (event.event == AuthChangeEvent.signedOut ||
          (_recoveryOwner != null && owner != _recoveryOwner)) {
        setState(() => _recoveryOwner = null);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.auth, widget.auth)) {
      unawaited(_subscription?.cancel());
      _recoveryOwner = null;
      _listen();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.auth.user?.id;
    if (_recoveryOwner != null && _recoveryOwner == owner) {
      return NativePasswordRecoveryScreen(
        key: ValueKey('recovery-$_recoveryOwner'),
        auth: widget.auth,
        ownerId: _recoveryOwner!,
        onRecovered: () {
          if (mounted) setState(() => _recoveryOwner = null);
        },
      );
    }
    if (owner != null) {
      return MediaFlowShell(
        key: ValueKey('mediaflow-user-$owner'),
        client: widget.auth.client,
      );
    }
    return SignInScreen(auth: widget.auth);
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
  bool visiblePassword = false;
  bool visibleConfirmation = false;
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
    final invalidEmail = NativeM35AuthRules.email(email.text);
    if (invalidEmail != null) {
      setState(() => message = invalidEmail);
      return;
    }
    final invalidPassword = signup
        ? NativeM35AuthRules.confirmation(password.text, confirmation.text)
        : NativeM35AuthRules.password(password.text);
    if (invalidPassword != null) {
      setState(() => message = invalidPassword);
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
    final issue = NativeM35AuthRules.email(email.text);
    if (issue != null) {
      setState(() => message = 'Enter your valid email above, then request a reset.');
      return;
    }
    setState(() { busy = true; message = null; });
    try {
      await widget.auth.resetPassword(email.text);
      if (mounted) {
        setState(() => message =
            'If the address can receive recovery emails, check your inbox. '
            'The link destination depends on your Supabase redirect settings.');
      }
    } on AuthException catch (_) {
      if (mounted) {
        setState(() => message =
            'Could not request a password reset. Please try again.');
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Could not request a reset.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _fields() => AutofillGroup(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const Key('m35-auth-email'),
        controller: email,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(
          labelText: 'Email', prefixIcon: Icon(Icons.alternate_email),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('m35-auth-password'),
        controller: password, obscureText: !visiblePassword,
        textInputAction: signup ? TextInputAction.next : TextInputAction.done,
        autofillHints: [signup ? AutofillHints.newPassword : AutofillHints.password],
        onSubmitted: signup ? null : (_) => unawaited(submit()),
        decoration: InputDecoration(
          labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: visiblePassword ? 'Hide password' : 'Show password',
            onPressed: () => setState(() => visiblePassword = !visiblePassword),
            icon: Icon(visiblePassword
                ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          ),
        ),
      ),
      if (signup) ...[
        const SizedBox(height: 12),
        TextField(
          key: const Key('m35-auth-confirm'),
          controller: confirmation, obscureText: !visibleConfirmation,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => unawaited(submit()),
          decoration: InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: const Icon(Icons.lock_person_outlined),
            suffixIcon: IconButton(
              tooltip: visibleConfirmation
                  ? 'Hide confirmation' : 'Show confirmation',
              onPressed: () => setState(
                () => visibleConfirmation = !visibleConfirmation),
              icon: Icon(visibleConfirmation
                  ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            ),
          ),
        ),
      ],
      if (message != null) Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(message!, key: const Key('m35-auth-message'),
          textAlign: TextAlign.center),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        key: const Key('m35-auth-submit'),
        onPressed: busy ? null : submit,
        icon: Icon(signup ? Icons.person_add_alt_1 : Icons.login),
        label: Text(busy ? 'Please wait…' :
          signup ? 'Create account' : 'Log in'),
      ),
      TextButton(
        onPressed: busy ? null : () => setState(() {
          signup = !signup;
          message = null;
          password.clear();
          confirmation.clear();
          visiblePassword = false;
          visibleConfirmation = false;
        }),
        child: Text(signup ? 'Already have an account? Log in' : 'Create account'),
      ),
      if (!signup) TextButton.icon(
        key: const Key('m35-auth-forgot'),
        onPressed: busy ? null : requestPasswordReset,
        icon: const Icon(Icons.lock_reset_outlined),
        label: const Text('Forgot password?'),
      ),
      const SizedBox(height: 6),
      Text('Supabase Auth protects your MediaFlow account. '
          'Existing Library and History remain private.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall),
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: LayoutBuilder(
      builder: (context, bounds) {
        final wide = bounds.maxWidth >= 800;
        return Center(child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: bounds.maxWidth < 360 ? 12 : 20, vertical: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: Card(child: Padding(
              padding: EdgeInsets.all(wide ? 32 : 20),
              child: wide ? Row(children: [
                Expanded(child: _brand(context, hero: true)),
                const SizedBox(width: 32),
                Expanded(child: _form(context)),
              ]) : _form(context),
            )),
          ),
        ));
      },
    )),
  );

  Widget _brand(BuildContext context, {bool hero = false}) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Image.asset('assets/branding/mediaflow-launcher-512.png',
          width: hero ? 90 : 64, height: hero ? 90 : 64),
      const SizedBox(height: 12),
      Text('MediaFlow',
          style: Theme.of(context).textTheme.headlineMedium),
      if (hero) ...[
        const SizedBox(height: 16),
        Text('Your media. Everywhere you are.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text('SYNC · ORGANIZE · ENJOY',
          textAlign: TextAlign.center),
      ],
    ],
  );

  Widget _form(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (MediaQuery.sizeOf(context).width < 800) ...[
        _brand(context), const SizedBox(height: 22),
      ],
      Text(signup ? 'Create your MediaFlow account'
          : 'Welcome back to MediaFlow',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Text(signup
          ? 'Create your account to access your private workspace.'
          : 'Sign in to your existing MediaFlow workspace.'),
      const SizedBox(height: 20),
      _fields(),
    ],
  );
}

/// Shown only following an authenticated passwordRecovery event. An expired
/// link or account switch invalidates this screen's update authority.
class NativePasswordRecoveryScreen extends StatefulWidget {
  const NativePasswordRecoveryScreen({
    super.key,
    required this.auth,
    required this.ownerId,
    required this.onRecovered,
    this.testCoordinator,
  });
  final MediaFlowAuth auth;
  final String ownerId;
  final VoidCallback onRecovered;
  final NativeM35PasswordRecovery? testCoordinator;

  @override
  State<NativePasswordRecoveryScreen> createState() =>
      _NativePasswordRecoveryScreenState();
}

class _NativePasswordRecoveryScreenState
    extends State<NativePasswordRecoveryScreen> {
  final password = TextEditingController();
  final confirm = TextEditingController();
  late final NativeM35PasswordRecovery recovery;
  bool busy = false;
  bool reveal = false;
  bool revealConfirm = false;
  String? message;

  @override
  void initState() {
    super.initState();
    recovery = widget.testCoordinator ?? NativeM35PasswordRecovery(
      expectedOwnerId: widget.ownerId,
      currentOwnerId: () => widget.auth.user?.id,
      updatePassword: widget.auth.updatePassword,
    );
  }

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try {
      await recovery.complete(password.text, confirm.text);
      if (mounted) widget.onRecovered();
    } on FormatException catch (error) {
      if (mounted) setState(() => message = error.message);
    } on StateError catch (error) {
      if (mounted) setState(() => message = error.message);
    } on AuthException catch (_) {
      if (mounted) {
        setState(() => message =
            'Recovery failed. Check the link or request a new one.');
      }
    } catch (_) {
      if (mounted) setState(() =>
          message = 'Could not complete password recovery.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.verified_user_outlined, size: 44),
              const SizedBox(height: 16),
              Text('Choose a new password',
                style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Your recovery link authenticated this session. '
                'Choose a new password to finish. '
                'Your MediaFlow Library data will not be changed.'),
              const SizedBox(height: 16),
              TextField(
                key: const Key('m35-recovery-password'),
                controller: password,
                obscureText: !reveal,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'New password',
                  suffixIcon: IconButton(
                    tooltip: reveal ? 'Hide new password' : 'Show new password',
                    onPressed: () => setState(() => reveal = !reveal),
                    icon: Icon(reveal
                      ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('m35-recovery-confirm'),
                controller: confirm,
                obscureText: !revealConfirm,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => unawaited(_complete()),
                decoration: InputDecoration(
                  labelText: 'Confirm new password',
                  suffixIcon: IconButton(
                    tooltip: revealConfirm
                        ? 'Hide confirmation' : 'Show confirmation',
                    onPressed: () =>
                        setState(() => revealConfirm = !revealConfirm),
                    icon: Icon(revealConfirm
                        ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  ),
                ),
              ),
              if (message != null) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(message!, key: const Key('m35-recovery-message')),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('m35-recovery-submit'),
                onPressed: busy ? null : _complete,
                icon: const Icon(Icons.lock_reset_outlined),
                label: Text(busy ? 'Updating…' : 'Update password'),
              ),
            ],
          ),
        )),
      ),
    ))),
  );
}
