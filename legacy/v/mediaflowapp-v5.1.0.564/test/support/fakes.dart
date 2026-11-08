import 'dart:convert';

import 'package:mediaflow/src/data/local_cache.dart';
import 'package:mediaflow/src/data/records.dart';
import 'package:mediaflow/src/data/sync_engine.dart';
import 'package:mediaflow/src/state/state_codec.dart';

/// In-memory stand-in for the `mediaflow_states` row with real
/// compare-and-swap behaviour on `updated_at`. Like the website, it stores the
/// compressed form when [compressed] is set.
class FakeCloud implements CloudBackend {
  FakeCloud(Map<String, dynamic>? state, {this.compressed = false})
      : _state = state == null ? null : jsonEncode(state);
  String? _state;
  final bool compressed;
  int _version = 1;
  int casCalls = 0;
  int fetchCalls = 0;
  int versionCalls = 0;

  /// Runs before the next compare-and-swap, e.g. "the website saved meanwhile".
  void Function(FakeCloud cloud)? beforeNextCas;

  String get updatedAt => 'v$_version';
  Map<String, dynamic> get state => (jsonDecode(_state!) as Map).cast<String, dynamic>();

  void websiteSaves(void Function(Map<String, dynamic> s) edit) {
    final s = state;
    edit(s);
    _state = jsonEncode(s);
    _version++;
  }

  @override
  Future<String?> version(String userId) async {
    versionCalls++;
    return _state == null ? null : updatedAt;
  }

  @override
  Future<CloudSnapshot?> fetch(String userId) async {
    fetchCalls++;
    if (_state == null) return null;
    return CloudSnapshot(compressed ? encodeStateData(state) : state, updatedAt);
  }

  @override
  Future<String?> compareAndSwap(String userId, String expectedUpdatedAt, Object payload) async {
    casCalls++;
    final hook = beforeNextCas;
    beforeNextCas = null;
    hook?.call(this);
    if (expectedUpdatedAt != updatedAt) return null;
    _state = jsonEncode(decodeStateData(payload));
    _version++;
    return updatedAt;
  }
}

class MemoryCache implements AccountCache {
  final Map<String, String> files = {};

  @override
  Future<CachedAccount> load(String userId) async {
    final text = files[userId];
    if (text == null) return CachedAccount();
    final m = jsonDecode(text) as Map<String, dynamic>;
    return CachedAccount(raw: m['raw'], baseUpdatedAt: m['baseUpdatedAt'] as String?);
  }

  @override
  Future<void> save(String userId, CachedAccount account) async {
    files[userId] = jsonEncode({'raw': account.raw, 'baseUpdatedAt': account.baseUpdatedAt, 'pending': account.pending.length});
  }

  @override
  Future<void> delete(String userId) async => files.remove(userId);
}

/// In-memory stand-in for the website's per-record storage (v556): rows keyed
/// by (kind, record_id) with a database-set `updated_at`, plus the single-row
/// fallback copy. [websiteSaves] writes the way the website does (only the
/// records that changed).
class FakeRecordCloud extends FakeCloud implements RecordBackend {
  FakeRecordCloud(Map<String, dynamic> state, {this.migrated = true}) : super(state, compressed: true) {
    if (migrated) _writeAll(state);
  }
  bool migrated;
  final Map<String, RecordRow> rows = {};
  int _tick = 0;
  int uploadCalls = 0, uploadedRows = 0, fetchRecordCalls = 0, fallbackWrites = 0;
  Object? fallback;

  String _now() => DateTime.utc(2026, 11, 7).add(Duration(seconds: 10 * ++_tick)).toIso8601String();

  void _put(String k, String i, double? pos, String? data, {bool deleted = false}) {
    rows[recordKey(k, i)] = RecordRow(kind: k, recordId: i, pos: pos, data: data, deleted: deleted, updatedAt: _now());
  }

  void _writeAll(Map<String, dynamic> state) {
    for (final r in decomposeState(state, (_) => null).values) {
      _put(r.k, r.i, r.pos, r.j);
    }
    _put('meta', 'store', null, '{"version":556}');
  }

  /// The account as the website would rebuild it from the rows.
  Map<String, dynamic> get recordState => composeState([
        for (final r in rows.values)
          if (r.kind != 'meta' && !r.deleted && r.data != null) Rec(r.kind, r.recordId, r.pos, r.data!),
      ]);

  /// The website edits the account and saves only the changed records.
  void websiteSavesRecords(void Function(Map<String, dynamic> s) edit) {
    final s = recordState;
    final before = {for (final r in rows.values) if (!r.deleted && r.kind != 'meta') recordKey(r.kind, r.recordId): r};
    edit(s);
    final recs = decomposeState(s, (key) => before[key]?.pos);
    for (final r in recs.values) {
      final cur = before[r.key];
      if (cur != null && cur.data == r.j && cur.pos == r.pos) continue;
      _put(r.k, r.i, r.pos, r.j);
    }
    for (final key in before.keys.where((k) => !recs.containsKey(k))) {
      final cur = before[key]!;
      _put(cur.kind, cur.recordId, null, null, deleted: true);
    }
  }

  @override
  Future<bool> usesRecords(String userId) async => migrated;

  @override
  Future<List<RecordRow>> fetchRecords(String userId, String since) async {
    fetchRecordCalls++;
    final out = rows.values.where((r) => since.isEmpty || r.updatedAt.compareTo(since) > 0).toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return out;
  }

  @override
  Future<void> uploadRecords(String userId, List<RecordUpload> upload, String deviceId) async {
    uploadCalls++;
    uploadedRows += upload.length;
    for (final r in upload) {
      _put(r.k, r.i, r.pos, r.deleted ? null : r.j, deleted: r.deleted);
    }
  }

  @override
  Future<List<RecordRow>> fetchDocRecords(String userId, List<String> recordIds, String since) async {
    final out = rows.values
        .where((r) => r.kind == 'doc' && recordIds.contains(r.recordId) && (since.isEmpty || r.updatedAt.compareTo(since) > 0))
        .toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return out;
  }

  @override
  Future<void> writeFallback(String userId, Object payload, String deviceId) async {
    fallbackWrites++;
    fallback = payload;
  }
}
