/// Source-grounded subset of v410 v297 authentication rules. Website
/// validates email format through native input type=email and requires
/// minimum six password characters plus signup confirmation parity.
abstract final class NativeM35AuthRules {
  static String? email(String input) {
    final value = input.trim();
    if (value.isEmpty ||
        value.length > 320 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? password(String input) =>
      input.length < 6 ? 'Password must contain at least 6 characters.' : null;

  static String? confirmation(String input, String repeated) {
    final message = password(input);
    if (message != null) return message;
    return input != repeated ? 'Passwords do not match.' : null;
  }
}

/// Validates and performs *only* Supabase Auth credential rotation.
/// Does not modify MediaFlow Library/cloud states, trigger a sync worker,
/// or assume that a password recovery link is a verified cross-device state.
class NativeM35PasswordRecovery {
  NativeM35PasswordRecovery({
    required this.expectedOwnerId,
    required this.currentOwnerId,
    required this.updatePassword,
  });

  final String expectedOwnerId;
  final String? Function() currentOwnerId;
  final Future<void> Function(String password) updatePassword;
  bool _busy = false;
  bool get busy => _busy;

  void _checkOwner() {
    if (expectedOwnerId.isEmpty ||
        currentOwnerId() != expectedOwnerId) {
      throw StateError('Password recovery session changed. Request a new link.');
    }
  }

  Future<void> complete(String password, String confirm) async {
    if (_busy) throw StateError('Password recovery is already in progress.');
    _checkOwner();
    final issue = NativeM35AuthRules.confirmation(password, confirm);
    if (issue != null) throw FormatException(issue);
    _busy = true;
    try {
      _checkOwner();
      await updatePassword(password);
      _checkOwner();
    } finally {
      _busy = false;
    }
  }
}
