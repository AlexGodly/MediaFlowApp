import 'package:supabase_flutter/supabase_flutter.dart';
import 'mediaflow_models.dart';
import 'mediaflow_state_codec.dart';

abstract class MediaFlowLibraryRepository {
  Future<MediaFlowCatalog> load();
}

/// Matches v410's existing cloud read, with user_id explicitly restricted.
/// Supabase RLS remains the essential server-side ownership guarantee.
class SupabaseMediaFlowLibraryRepository implements MediaFlowLibraryRepository {
  const SupabaseMediaFlowLibraryRepository(this.client);
  final SupabaseClient client;

  @override
  Future<MediaFlowCatalog> load() async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before reading your MediaFlow Library.');
    }

    // Read-only: no INSERT, UPDATE, RPC, cloud merge or schema migration.
    final row = await client
        .from('mediaflow_states')
        .select('state_data,updated_at')
        .eq('user_id', user.id)
        .maybeSingle();

    final decoded = await decodeMediaFlowStateAsync(row?['state_data']);
    return MediaFlowCatalog(
      categories: decoded.categories,
      library: decoded.library,
      updatedAt: DateTime.tryParse((row?['updated_at'] ?? '').toString()),
    );
  }
}
