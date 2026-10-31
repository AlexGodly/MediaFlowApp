import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../state/state_codec.dart';
import '../util/js.dart';
import 'account_ops.dart';

/// What the app keeps on the device for one account: the last cloud copy it
/// saw and the changes not yet uploaded.
class CachedAccount {
  CachedAccount({this.base, this.baseUpdatedAt, List<AccountOp>? pending, this.savedAt})
      : pending = pending ?? [];
  Map<String, dynamic>? base;
  String? baseUpdatedAt;
  final List<AccountOp> pending;
  int? savedAt;
}

abstract class AccountCache {
  Future<CachedAccount> load(String userId);
  Future<void> save(String userId, CachedAccount account);
  Future<void> delete(String userId);
}

/// One JSON file per account in the app's private support folder, written
/// atomically (temp file + rename) so a crash can't leave half a file.
class FileAccountCache implements AccountCache {
  Future<File> _file(String userId) async {
    final dir = await getApplicationSupportDirectory();
    final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}mediaflow-account-$safe.json');
  }

  @override
  Future<CachedAccount> load(String userId) async {
    try {
      final file = await _file(userId);
      if (!await file.exists()) return CachedAccount();
      final text = await file.readAsString();
      final json = await jsonDecodeInBackground(text);
      final m = asMap(json);
      if (m == null || m['userId'] != userId) return CachedAccount();
      return CachedAccount(
        base: asMap(m['base']),
        baseUpdatedAt: m['baseUpdatedAt'] is String ? m['baseUpdatedAt'] as String : null,
        pending: asList(m['pending']).map((p) => AccountOp.fromJson(asMap(p) ?? const {})).toList(),
        savedAt: jsNum(m['savedAt']).toInt(),
      );
    } catch (_) {
      return CachedAccount();
    }
  }

  @override
  Future<void> save(String userId, CachedAccount account) async {
    final file = await _file(userId);
    final data = {
      'version': 2,
      'userId': userId,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'baseUpdatedAt': account.baseUpdatedAt,
      'base': account.base,
      'pending': account.pending.map((p) => p.toJson()).toList(),
    };
    final text = await jsonEncodeInBackground(data);
    final tmp = File('${file.path}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete(String userId) async {
    final file = await _file(userId);
    if (await file.exists()) await file.delete();
  }
}
