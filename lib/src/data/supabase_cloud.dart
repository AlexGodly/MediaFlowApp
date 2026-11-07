import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'records.dart';
import 'sync_engine.dart';

/// Reads and writes the website's existing `mediaflow_states` row, and its
/// per-record storage (`mediaflow_records`, website v556) once the website has
/// moved the account over. Uses the signed-in user's session and the
/// row-level security policies the website already relies on; no service key,
/// no schema changes.
class SupabaseCloud implements RecordBackend {
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

  // ---- per-record storage (website v556) ----

  static const _columns = 'kind,record_id,pos,data,deleted,updated_at';
  static const _page = 1000, _rpcPage = 10000;
  bool? _rpc;

  @override
  Future<bool> usesRecords(String userId) async {
    try {
      final row = await client
          .from(kRecordTable)
          .select('record_id')
          .eq('user_id', userId)
          .eq('kind', 'meta')
          .eq('record_id', 'store')
          .maybeSingle();
      return row != null;
    } on PostgrestException {
      // No record table for this account (or not readable): the single row stays in use.
      return false;
    }
  }

  @override
  Future<List<RecordRow>> fetchRecords(String userId, String since) async {
    if (_rpc != false) {
      try {
        final rows = await _fetchRpc(since);
        _rpc = true;
        return rows;
      } on PostgrestException catch (e) {
        final missing = RegExp(r'PGRST202|42883|Could not find the function', caseSensitive: false)
            .hasMatch('${e.code ?? ''} ${e.message}');
        if (!missing) rethrow;
        _rpc = false;
      }
    }
    return _fetchPaged(userId, since);
  }

  /// `mediaflow_records_page`: keyset pages of up to 10,000 rows.
  Future<List<RecordRow>> _fetchRpc(String since) async {
    final out = <RecordRow>[];
    String? at = since.isEmpty ? null : since;
    var kind = '', id = '';
    for (;;) {
      final data = await client.rpc('mediaflow_records_page',
          params: {'p_after_at': at, 'p_after_kind': kind, 'p_after_id': id, 'p_limit': _rpcPage});
      final list = data is List ? data : const [];
      for (final r in list) {
        if (r is Map) out.add(RecordRow.fromJson(r.cast<String, dynamic>()));
      }
      if (list.length < _rpcPage) break;
      final last = out.last;
      at = last.updatedAt;
      kind = last.kind;
      id = last.recordId;
    }
    return out;
  }

  /// `mf556FetchPaged`: pages on updated_at; an instant with more than a page
  /// of rows is read with offsets.
  Future<List<RecordRow>> _fetchPaged(String userId, String since) async {
    final rows = <RecordRow>[];
    final seen = <String>{};
    var after = since, first = true;
    String rowId(RecordRow r) => '${r.kind}\u0001${r.recordId}\u0001${r.updatedAt}';
    for (;;) {
      var q = client.from(kRecordTable).select(_columns).eq('user_id', userId);
      if (after.isNotEmpty) q = first && since.isNotEmpty ? q.gt('updated_at', after) : q.gte('updated_at', after);
      final data = await q
          .order('updated_at', ascending: true)
          .order('kind', ascending: true)
          .order('record_id', ascending: true)
          .range(0, _page - 1);
      var added = 0;
      for (final m in data) {
        final r = RecordRow.fromJson(m);
        if (seen.add(rowId(r))) {
          rows.add(r);
          added++;
        }
      }
      first = false;
      if (data.length < _page) break;
      final last = '${data.last['updated_at']}';
      if (added == 0 || last == after) {
        var from = _page;
        for (;;) {
          final more = await client
              .from(kRecordTable)
              .select(_columns)
              .eq('user_id', userId)
              .eq('updated_at', last)
              .order('kind', ascending: true)
              .order('record_id', ascending: true)
              .range(from, from + _page - 1);
          for (final m in more) {
            final r = RecordRow.fromJson(m);
            if (seen.add(rowId(r))) rows.add(r);
          }
          if (more.length < _page) break;
          from += _page;
        }
        after = last;
        first = true;
        since = last;
        continue;
      }
      after = last;
    }
    return rows;
  }

  @override
  Future<void> uploadRecords(String userId, List<RecordUpload> rows, String deviceId) async {
    var batch = <Map<String, dynamic>>[];
    var bytes = 0;
    Future<void> flush() async {
      if (batch.isEmpty) return;
      Object? lastError;
      for (final wait in const [0, 600, 1500, 3500]) {
        if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
        try {
          await client.from(kRecordTable).upsert(batch, onConflict: 'user_id,kind,record_id');
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          if (!RegExp(r'timeout|57014|fetch|network|socket|503|502|504', caseSensitive: false).hasMatch('$e')) break;
        }
      }
      if (lastError != null) throw lastError;
      batch = [];
      bytes = 0;
    }

    for (final r in rows) {
      final row = {
        'user_id': userId,
        'kind': r.k,
        'record_id': r.i,
        'pos': r.pos,
        'data': r.deleted ? null : r.j,
        'deleted': r.deleted,
        'device_id': deviceId,
      };
      final size = (r.j?.length ?? 0) + 200;
      if (batch.isNotEmpty && (bytes + size > 900000 || batch.length >= 1000)) await flush();
      batch.add(row);
      bytes += size;
    }
    await flush();
  }

  @override
  Future<List<RecordRow>> fetchDocRecords(String userId, List<String> recordIds, String since) async {
    var q = client.from(kRecordTable).select(_columns).eq('user_id', userId).eq('kind', 'doc').inFilter('record_id', recordIds);
    if (since.isNotEmpty) q = q.gt('updated_at', since);
    final data = await q.order('updated_at', ascending: true);
    return [for (final m in data) RecordRow.fromJson(m)];
  }

  @override
  Future<void> writeFallback(String userId, Object payload, String deviceId) async {
    if (payload is! Map) return;
    await client.from(kStateTable).upsert({
      'user_id': userId,
      'state_data': {
        ...payload.cast<String, dynamic>(),
        'mf556': {'device': deviceId, 'at': DateTime.now().millisecondsSinceEpoch, 'version': 556},
      },
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }
}
