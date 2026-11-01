import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'sync_engine.dart';

/// Reads and writes the website's existing `mediaflow_states` row. Uses the
/// signed-in user's session and the row-level security policies the website
/// already relies on; no service key, no schema changes.
class SupabaseCloud implements CloudBackend {
  SupabaseCloud(this._client);
  final SupabaseClient Function() _client;

  /// The signed-in client. Throws [NotSignedIn] when there is no session (the
  /// device copy stays usable; changes wait until the user signs in again).
  SupabaseClient get client {
    final SupabaseClient c;
    try {
      c = _client();
    } catch (_) {
      throw const SocketException('MediaFlow cloud is not reachable yet');
    }
    if (c.auth.currentSession == null) throw NotSignedIn();
    return c;
  }

  @override
  Future<String?> version(String userId) async {
    final row = await client.from(kStateTable).select('updated_at').eq('user_id', userId).maybeSingle();
    if (row == null) return null;
    final updatedAt = row['updated_at'];
    if (updatedAt is! String || updatedAt.isEmpty) {
      throw StateError('The MediaFlow cloud row has no version. Refusing to continue.');
    }
    return updatedAt;
  }

  @override
  Future<CloudSnapshot?> fetch(String userId) async {
    final row = await client
        .from(kStateTable)
        .select('state_data,updated_at')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    final updatedAt = row['updated_at'];
    if (updatedAt is! String || updatedAt.isEmpty) {
      throw StateError('The MediaFlow cloud row has no version. Refusing to continue.');
    }
    // Kept as stored (the website's compressed form is one small object with a
    // text field); decoding happens in the background.
    return CloudSnapshot(row['state_data'], updatedAt);
  }

  @override
  Future<String?> compareAndSwap(String userId, String expectedUpdatedAt, Object payload) async {
    final next = DateTime.now().toUtc().toIso8601String();
    final result = await client
        .from(kStateTable)
        .update({'state_data': payload, 'updated_at': next})
        .eq('user_id', userId)
        .eq('updated_at', expectedUpdatedAt)
        .select('updated_at')
        .maybeSingle();
    if (result == null) return null;
    final written = result['updated_at'];
    return written is String && written.isNotEmpty ? written : next;
  }
}
