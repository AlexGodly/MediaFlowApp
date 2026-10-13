import 'package:supabase_flutter/supabase_flutter.dart';

import 'mediaflow_models.dart';
import 'mediaflow_state_codec.dart';

abstract class MediaFlowLibraryRepository {
  Future<MediaFlowCatalog> load();

  /// Default fallback for test repositories. Production overrides to bypass cache.
  Future<MediaFlowCatalog> reload() => load();
}

/// All native read-only pages share the same authenticated snapshot request.
/// This avoids downloading and inflating the whole v410 state for every tab.
class SupabaseMediaFlowLibraryRepository extends MediaFlowLibraryRepository {
  SupabaseMediaFlowLibraryRepository(this.client);
  final SupabaseClient client;

  Future<MediaFlowCatalog>? _cached;

  @override
  Future<MediaFlowCatalog> load() => _cached ??= _fetch();

  @override
  Future<MediaFlowCatalog> reload() {
    _cached = _fetch();
    return _cached!;
  }

  Future<MediaFlowCatalog> _fetch() async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before reading your MediaFlow data.');
    }

    // Owner predicate plus the existing authenticated RLS SELECT policy.
    // This class never writes or mutates the original account snapshot.
    final row = await client
        .from('mediaflow_states')
        .select('state_data,updated_at')
        .eq('user_id', user.id)
        .maybeSingle();

    final decoded = await decodeMediaFlowStateAsync(row?['state_data']);
    return MediaFlowCatalog(
      categories: decoded.categories,
      library: decoded.library,
      sessions: decoded.sessions,
      collections: decoded.collections,
      currentTask: decoded.currentTask,
      sessionActive: decoded.sessionActive,
      tasksPerDay: decoded.tasksPerDay,
      dailyMinutes: decoded.dailyMinutes,
      updatedAt: DateTime.tryParse((row?['updated_at'] ?? '').toString()),
    );
  }
}
