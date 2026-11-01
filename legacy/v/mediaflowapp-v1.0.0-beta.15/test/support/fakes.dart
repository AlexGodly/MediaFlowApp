import 'dart:convert';

import 'package:mediaflow/src/data/local_cache.dart';
import 'package:mediaflow/src/data/sync_engine.dart';

/// In-memory stand-in for the `mediaflow_states` row with real
/// compare-and-swap behaviour on `updated_at`.
class FakeCloud implements CloudBackend {
  FakeCloud(Map<String, dynamic>? state) : _state = state == null ? null : jsonEncode(state);
  String? _state;
  int _version = 1;
  int casCalls = 0;

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
  Future<CloudSnapshot?> fetch(String userId) async =>
      _state == null ? null : CloudSnapshot(state, updatedAt);

  @override
  Future<String?> compareAndSwap(String userId, String expectedUpdatedAt, Map<String, dynamic> next) async {
    casCalls++;
    final hook = beforeNextCas;
    beforeNextCas = null;
    hook?.call(this);
    if (expectedUpdatedAt != updatedAt) return null;
    _state = jsonEncode(next);
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
    return CachedAccount(base: (m['base'] as Map?)?.cast<String, dynamic>(), baseUpdatedAt: m['baseUpdatedAt'] as String?);
  }

  @override
  Future<void> save(String userId, CachedAccount account) async {
    files[userId] = jsonEncode({'base': account.base, 'baseUpdatedAt': account.baseUpdatedAt, 'pending': account.pending.length});
  }

  @override
  Future<void> delete(String userId) async => files.remove(userId);
}
