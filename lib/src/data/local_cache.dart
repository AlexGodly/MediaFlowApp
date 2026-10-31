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

/// The account last used on this device, so the app opens offline even when
/// the sign-in session is gone. Cleared only by an explicit sign-out.
class LastAccount {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}mediaflow-last-account.json');
  }

  static Future<({String userId, String email})?> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final m = asMap(await jsonDecodeInBackground(await f.readAsString()));
      final id = jsStr(m?['userId']);
      return id.isEmpty ? null : (userId: id, email: jsStr(m?['email']));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String userId, String email) async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(await jsonEncodeInBackground({'userId': userId, 'email': email}), flush: true);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Per account, in the app's private support folder: the last cloud copy (large,
/// rewritten only when it changes) and the pending changes (small, rewritten on
/// every change). Both are written atomically (temp file + rename).
class FileAccountCache implements AccountCache {
  String? _lastBase;

  Future<File> _file(String userId, [String suffix = '']) async {
    final dir = await getApplicationSupportDirectory();
    final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}mediaflow-account-$safe$suffix.json');
  }

  @override
  Future<CachedAccount> load(String userId) async {
    try {
      final file = await _file(userId);
      if (!await file.exists()) return CachedAccount();
      final m = asMap(await jsonDecodeInBackground(await file.readAsString()));
      if (m == null || m['userId'] != userId) return CachedAccount();
      var pending = asList(m['pending']);
      final pendingFile = await _file(userId, '-pending');
      if (await pendingFile.exists()) {
        final p = asMap(await jsonDecodeInBackground(await pendingFile.readAsString()));
        if (p != null && p['userId'] == userId) pending = asList(p['pending']);
      }
      final base = asMap(m['base']);
      final updatedAt = m['baseUpdatedAt'] is String ? m['baseUpdatedAt'] as String : null;
      _lastBase = '${identityHashCode(base)}|$updatedAt';
      return CachedAccount(
        base: base,
        baseUpdatedAt: updatedAt,
        pending: pending.map((p) => AccountOp.fromJson(asMap(p) ?? const {})).toList(),
        savedAt: jsNum(m['savedAt']).toInt(),
      );
    } catch (_) {
      return CachedAccount();
    }
  }

  Future<void> _write(File file, Object data) async {
    final text = await jsonEncodeInBackground(data);
    final tmp = File('${file.path}.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> save(String userId, CachedAccount account) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = '${identityHashCode(account.base)}|${account.baseUpdatedAt}';
    if (key != _lastBase) {
      await _write(await _file(userId), {
        'version': 3,
        'userId': userId,
        'savedAt': now,
        'baseUpdatedAt': account.baseUpdatedAt,
        'base': account.base,
        'pending': const [],
      });
      _lastBase = key;
    }
    await _write(await _file(userId, '-pending'), {
      'version': 3,
      'userId': userId,
      'savedAt': now,
      'pending': account.pending.map((p) => p.toJson()).toList(),
    });
  }

  @override
  Future<void> delete(String userId) async {
    _lastBase = null;
    for (final suffix in ['', '-pending']) {
      final file = await _file(userId, suffix);
      if (await file.exists()) await file.delete();
    }
  }
}
