import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Isolated, read-only decoder for the website's existing single JSONB row.
/// Unknown MediaFlow state is never reconstructed from UI projections.
class CloudTitle {
  const CloudTitle({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.status,
    required this.progress,
    required this.total,
    required this.coverUrl,
    required this.seasons,
  });
  final String id, title, categoryId, status, coverUrl;
  final int progress;
  final int? total;
  final List<CloudSeason> seasons;

  factory CloudTitle.fromJson(Map<String, dynamic> v) {
    int number(Object? n) => n is num
        ? n.floor() : (num.tryParse(n?.toString() ?? '') ?? 0).floor();
    final rawSeasons = v['seasons'];
    return CloudTitle(
      id: (v['id'] ?? '').toString(),
      title: (v['title'] ?? 'Untitled').toString(),
      categoryId: (v['categoryId'] ?? '').toString(),
      status: (v['status'] ?? 'planned').toString(),
      progress: number(v['progress']).clamp(0, 100000000).toInt(),
      total: v['total'] == null ? null
          : number(v['total']).clamp(0, 100000000).toInt(),
      coverUrl: (v['coverUrl'] ?? '').toString(),
      seasons: rawSeasons is List
          ? rawSeasons.whereType<Map>().map((raw) =>
              CloudSeason.fromJson(Map<String, dynamic>.from(raw)))
              .toList(growable: false)
          : const [],
    );
  }
}

class CloudSeason {
  const CloudSeason({
    required this.id, required this.name,
    required this.progress, required this.total,
  });
  final String id, name;
  final int progress;
  final int? total;

  factory CloudSeason.fromJson(Map<String, dynamic> raw) {
    int? n(Object? value) => value is num
        ? value.floor() : int.tryParse(value?.toString() ?? '');
    return CloudSeason(
      id: (raw['id'] ?? raw['number'] ?? '').toString(),
      name: (raw['name'] ?? 'Season').toString(),
      progress: (n(raw['progress']) ?? 0).clamp(0, 100000000).toInt(),
      total: n(raw['total']),
    );
  }
}

class MediaFlowCloudSnapshot {
  const MediaFlowCloudSnapshot({
    required this.ownerId, required this.revision,
    required this.library, required this.categories,
    required this.previousSessions,
  });
  final String ownerId, revision;
  final List<CloudTitle> library;
  final Map<String, String> categories;
  final int previousSessions;

  static MediaFlowCloudSnapshot decode({
    required String ownerId, required String revision,
    required Object? rawState,
  }) {
    if (ownerId.isEmpty || revision.isEmpty || rawState == null) {
      throw const FormatException('Missing authenticated cloud snapshot.');
    }
    Object? decoded = rawState;
    if (decoded is Map) {
      final state = Map<String, dynamic>.from(decoded);
      if (state.containsKey('__mediaflowCompressed')) {
        if (state['__mediaflowCompressed'] != 'gzip' ||
            state['data'] is! String) {
          throw const FormatException('Unsupported cloud compression.');
        }
        try {
          decoded = jsonDecode(utf8.decode(
            gzip.decode(base64Decode(state['data'] as String))));
        } catch (_) {
          throw const FormatException('Cloud snapshot cannot be decompressed.');
        }
      }
    } else if (decoded is String) {
      decoded = jsonDecode(decoded);
    }
    if (decoded is! Map) {
      throw const FormatException('Cloud account data is not a JSON object.');
    }
    final state = Map<String, dynamic>.from(decoded);
    if (state['library'] is! List ||
        state['categories'] is! List ||
        state['sessions'] is! List) {
      throw const FormatException('Incomplete account snapshot; no defaults created.');
    }
    final rawTitles = state['library'] as List;
    final rawCategories = state['categories'] as List;
    if (rawTitles.any((row) => row is! Map) ||
        rawCategories.any((row) => row is! Map)) {
      throw const FormatException('Malformed Library or category records.');
    }
    final titles = rawTitles.map((row) =>
        CloudTitle.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList(growable: false);
    final categories = <String, String>{};
    for (final row in rawCategories) {
      final data = Map<String, dynamic>.from(row as Map);
      final id = (data['id'] ?? '').toString();
      if (id.isNotEmpty) {
        categories[id] = (data['name'] ?? 'Category').toString();
      }
    }
    return MediaFlowCloudSnapshot(
      ownerId: ownerId,
      revision: revision,
      library: titles,
      categories: categories,
      previousSessions: (state['sessions'] as List).length,
    );
  }
}

class MediaFlowCloudReader {
  const MediaFlowCloudReader(this.client);
  final SupabaseClient client;

  Future<MediaFlowCloudSnapshot> load() async {
    // A transient refresh failure must never be interpreted as an empty
    // cloud account. The UI keeps the last good snapshot when refresh fails.
    final auth = client.auth;
    final session = auth.currentSession;
    if (session == null) {
      throw StateError('Sign in to your MediaFlow account.');
    }
    if (session.isExpired) {
      await auth.refreshSession();
    }
    final owner = auth.currentUser?.id;
    if (owner == null || owner != session.user.id) {
      throw StateError('Signed-in account changed; cloud read stopped.');
    }
    final row = await client.from('mediaflow_states')
        .select('state_data,updated_at')
        .eq('user_id', owner)
        .maybeSingle();
    if (auth.currentUser?.id != owner) {
      throw StateError('Signed-in account changed while loading.');
    }
    if (row == null || row['state_data'] == null) {
      throw StateError('No existing MediaFlow cloud account data found. '
          'Nothing has been created or overwritten.');
    }
    return MediaFlowCloudSnapshot.decode(
      ownerId: owner,
      revision: (row['updated_at'] ?? '').toString(),
      rawState: row['state_data'],
    );
  }
}
