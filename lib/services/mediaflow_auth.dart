import 'package:supabase_flutter/supabase_flutter.dart';

/// Uses the existing MediaFlow Supabase project. No new tables are created.
class MediaFlowAuth {
  MediaFlowAuth(this.client);
  final SupabaseClient client;
  Stream<AuthState> get changes => client.auth.onAuthStateChange;
  User? get user => client.auth.currentUser;
  Future<AuthResponse> signIn(String email, String password) =>
      client.auth.signInWithPassword(email: email.trim(), password: password);
  Future<AuthResponse> signUp(String email, String password) =>
      client.auth.signUp(email: email.trim(), password: password);
  Future<void> signOut() => client.auth.signOut();
  /// Uses the signed-in, verified Supabase password-recovery session.
  /// No application state, history or XP is touched.
  Future<void> updatePassword(String password) async {
    await client.auth.updateUser(UserAttributes(password: password));
  }
  Future<void> resetPassword(String email) =>
      client.auth.resetPasswordForEmail(email.trim());
}
