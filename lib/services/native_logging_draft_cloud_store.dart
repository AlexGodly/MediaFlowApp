import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Account-scoped, separate cloud storage for **drafts only**.
/// Never writes public.mediaflow_states, Library, History, XP or website data.
/// Revision comparisons are performed in the single PostgreSQL UPDATE.
class NativeLoggingDraftCloudStore {
  NativeLoggingDraftCloudStore({required this.client, required this.ownerId});
  final SupabaseClient client;
  final String ownerId;

  static const table = 'mediaflow_native_logging_drafts';
  static const format = 'mediaflow-native-logging-draft-v1';
  static const maxBytes = 1024 * 1024;

  void _verifyOwner() {
    if (ownerId.isEmpty || client.auth.currentUser?.id != ownerId) {
      throw StateError('The signed-in MediaFlow account changed.');
    }
  }

  static void validate(Map<String, dynamic> payload) {
    if (payload['format'] != format ||
        payload['entries'] is! List ||
        payload['keepTitles'] is! bool ||
        (payload['entries'] as List).length > 300 ||
        utf8.encode(jsonEncode(payload)).length > maxBytes) {
      throw const FormatException('Invalid or oversized native Logging draft.');
    }
  }

  Future<NativeCloudLoggingDraft?> load() async {
    _verifyOwner();
    final row = await client.from(table)
        .select('revision,draft_data,updated_at')
        .eq('user_id', ownerId)
        .maybeSingle();
    _verifyOwner();
    if (row == null) return null;
    return NativeCloudLoggingDraft.fromRow(row);
  }

  /// On first save INSERT intentionally fails on existing row (23505):
  /// another device must never silently overwrite it.
  /// On subsequent saves, compare-and-swap is one atomic UPDATE.
  Future<NativeCloudLoggingDraft> save(
      Map<String, dynamic> payload, {required int? expectedRevision}) async {
    _verifyOwner();
    validate(payload);
    final data = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
    final Map<String, dynamic>? row;
    try {
      if (expectedRevision == null) {
        row = await client.from(table)
            .insert({'user_id': ownerId, 'revision': 1, 'draft_data': data})
            .select('revision,draft_data,updated_at').maybeSingle();
      } else {
        if (expectedRevision < 1) {
          throw const FormatException('Invalid draft revision.');
        }
        row = await client.from(table)
            .update({
              'draft_data': data,
              'revision': expectedRevision + 1,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('user_id', ownerId)
            .eq('revision', expectedRevision)
            .select('revision,draft_data,updated_at').maybeSingle();
      }
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw const NativeDraftCloudConflict();
      }
      rethrow;
    }
    _verifyOwner();
    if (row == null) throw const NativeDraftCloudConflict();
    return NativeCloudLoggingDraft.fromRow(row);
  }
}

class NativeDraftCloudConflict implements Exception {
  const NativeDraftCloudConflict();
  @override
  String toString() => 'Draft changed on another device. Review before replacing it.';
}

class NativeCloudLoggingDraft {
  NativeCloudLoggingDraft({
    required this.revision,
    required this.data,
    required this.updatedAt,
  });

  factory NativeCloudLoggingDraft.fromRow(Map<String, dynamic> row) {
    final revision = row['revision'] is int
        ? row['revision'] as int
        : int.tryParse(row['revision'].toString());
    final raw = row['draft_data'];
    if (revision == null || revision < 1 || raw is! Map) {
      throw const FormatException('Invalid cloud draft response.');
    }
    final data = Map<String, dynamic>.from(raw);
    NativeLoggingDraftCloudStore.validate(data);
    return NativeCloudLoggingDraft(
      revision: revision,
      data: jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
    );
  }

  final int revision;
  final Map<String, dynamic> data;
  final DateTime? updatedAt;
}
