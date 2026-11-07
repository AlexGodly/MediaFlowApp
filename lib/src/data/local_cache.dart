import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../state/state_codec.dart';
import '../util/js.dart';
import 'account_ops.dart';
import 'records.dart';

/// What the app keeps on the device for one account: the last cloud copy it
/// saw (as stored: the website's compressed form) and the changes not yet
/// uploaded.
class CachedAccount {
  CachedAccount({this.raw, this.baseUpdatedAt, List<AccountOp>? pending, this.savedAt, this.upgraded = false, this.records})
      : pending = pending ?? [];
  Object? raw;
  String? baseUpdatedAt;

  /// Per-record storage: what the device knows of the cloud's records.
  RecordIndex? records;
  final List<AccountOp> pending;
  int? savedAt;

  /// Read from an older file layout (rewritten on the next save).
  final bool upgraded;
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

/// Reads an account's cache files. Runs in the background: the files can be
/// tens of megabytes. Beta 15 and older kept the cloud copy uncompressed; it is
/// compressed here once so the app never holds it twice.
CachedAccount readCachedAccount(String path, String pendingPath, String userId) {
  try {
    final file = File(path);
    if (!file.existsSync()) return CachedAccount();
    final m = asMap(jsonDecode(file.readAsStringSync()));
    if (m == null || m['userId'] != userId) return CachedAccount();
    var pending = asList(m['pending']);
    final pendingFile = File(pendingPath);
    if (pendingFile.existsSync()) {
      final p = asMap(jsonDecode(pendingFile.readAsStringSync()));
      if (p != null && p['userId'] == userId) pending = asList(p['pending']);
    }
    Object? raw = m['baseRaw'];
    var upgraded = false;
    if (raw == null && asMap(m['base']) != null) {
      raw = encodeStateData(asMap(m['base'])!);
      upgraded = true;
    }
    return CachedAccount(
      raw: raw,
      baseUpdatedAt: m['baseUpdatedAt'] is String ? m['baseUpdatedAt'] as String : null,
      pending: pending.map((p) => AccountOp.fromJson(asMap(p) ?? const {})).toList(),
      savedAt: jsNum(m['savedAt']).toInt(),
      upgraded: upgraded,
      // Only valid together with the copy it describes.
      records: raw == null ? null : RecordIndex.fromJson(m['records']),
    );
  } catch (_) {
    return CachedAccount();
  }
}

Future<CachedAccount> _readInBackground(String path, String pendingPath, String userId) =>
    Isolate.run(() => readCachedAccount(path, pendingPath, userId));

/// Writes [data] as JSON to [path] atomically (temp file + rename), in the
/// background.
Future<void> _writeInBackground(String path, Object data) => Isolate.run(() {
      final tmp = File('$path.tmp');
      tmp.parent.createSync(recursive: true);
      tmp.writeAsStringSync(jsonEncode(data), flush: true);
      tmp.renameSync(path);
    });

/// Per account, in the app's private support folder: the last cloud copy (as
/// stored, rewritten only when it changes) and the pending changes (small,
/// rewritten on every change). Writes are atomic and never overlap.
class FileAccountCache implements AccountCache {
  String? _lastBase;
  Future<void> _tail = Future<void>.value();

  Future<File> _file(String userId, [String suffix = '']) async {
    final dir = await getApplicationSupportDirectory();
    final safe = userId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}${Platform.pathSeparator}mediaflow-account-$safe$suffix.json');
  }

  @override
  Future<CachedAccount> load(String userId) async {
    try {
      final file = await _file(userId);
      final pendingFile = await _file(userId, '-pending');
      final cached = await _readInBackground(file.path, pendingFile.path, userId);
      _lastBase = cached.upgraded || cached.raw == null
          ? null
          : '${identityHashCode(cached.raw)}|${cached.baseUpdatedAt}|${cached.records?.cursor}|${cached.records?.entries.length}';
      return cached;
    } catch (_) {
      return CachedAccount();
    }
  }

  @override
  Future<void> save(String userId, CachedAccount account) {
    final next = _tail.then((_) => _save(userId, account));
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _save(String userId, CachedAccount account) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final records = account.records;
    final key = '${identityHashCode(account.raw)}|${account.baseUpdatedAt}|${records?.cursor}|${records?.entries.length}';
    if (account.raw != null && key != _lastBase) {
      await _writeInBackground((await _file(userId)).path, {
        'version': 4,
        'userId': userId,
        'savedAt': now,
        'baseUpdatedAt': account.baseUpdatedAt,
        'baseRaw': account.raw,
        'pending': const [],
        if (records != null) 'records': records.toJson(),
      });
      _lastBase = key;
    }
    await _writeInBackground((await _file(userId, '-pending')).path, {
      'version': 4,
      'userId': userId,
      'savedAt': now,
      'pending': account.pending.map((p) => p.toJson()).toList(),
    });
  }

  @override
  Future<void> delete(String userId) async {
    await _tail;
    _lastBase = null;
    for (final suffix in ['', '-pending']) {
      final file = await _file(userId, suffix);
      if (await file.exists()) await file.delete();
    }
  }
}
