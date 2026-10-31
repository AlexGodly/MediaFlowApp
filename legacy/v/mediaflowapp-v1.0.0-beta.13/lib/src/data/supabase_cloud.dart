import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../state/state_codec.dart';
import 'sync_engine.dart';

/// Reads and writes the website's existing `mediaflow_states` row. Uses the
/// signed-in user's session and the row-level security policies the website
/// already relies on; no service key, no schema changes.
class SupabaseCloud implements CloudBackend {
  SupabaseCloud(this.client);
  final SupabaseClient client;

  @override
  Future<CloudSnapshot?> fetch(String userId) async {
    final row = await client
        .from(kStateTable)
        .select('state_data,updated_at')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    final raw = row['state_data'];
    final updatedAt = row['updated_at'];
    if (updatedAt is! String || updatedAt.isEmpty) {
      throw StateError('The MediaFlow cloud row has no version. Refusing to continue.');
    }
    final state = await decodeStateDataInBackground(raw);
    return CloudSnapshot(state, updatedAt);
  }

  @override
  Future<String?> compareAndSwap(String userId, String expectedUpdatedAt, Map<String, dynamic> state) async {
    final payload = await encodeStateDataInBackground(state);
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
