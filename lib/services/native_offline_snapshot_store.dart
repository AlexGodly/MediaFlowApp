import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/mediaflow_models.dart';
import 'native_offline_projection_codec.dart';

/// Last verified device-local, READ-ONLY projection, never an offline edit queue.
/// File names are hashed account IDs, and the document has a second owner check.
/// Content lives in the OS app-private support folder; it is NOT encrypted.
class NativeOfflineSnapshotStore {
  NativeOfflineSnapshotStore({Future<Directory> Function()? directoryProvider})
      : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const format = 'mediaflow-native-device-snapshot-v1';
  static const maxFileBytes = 96 * 1024 * 1024;

  final Future<Directory> Function() _directoryProvider;
  Future<void> _writes = Future<void>.value();

  String _ownerHash(String accountId) {
    if (accountId.isEmpty) throw StateError('An authenticated account is required');
    return sha256.convert(utf8.encode(accountId)).toString();
  }

  Future<Directory> _directory() async {
    final root = await _directoryProvider();
    return Directory(root.path + Platform.pathSeparator + 'mediaflow-offline');
  }

  String _path(Directory folder, String hash) =>
      folder.path + Platform.pathSeparator + 'snapshot-' + hash + '.json';

  Future<T> _afterWrites<T>(Future<T> Function() action) async {
    await _writes;
    return action();
  }

  Future<void> _exclusive(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<NativeCachedSnapshot?> load(String accountId) {
    final hash = _ownerHash(accountId);
    return _afterWrites(() async {
      final folder = await _directory();
      final main = File(_path(folder, hash));
      final first = await _read(main, hash);
      if (first != null) return first;
      final backup = await _read(File(main.path + '.previous'), hash);
      return backup == null ? null : NativeCachedSnapshot(
        catalog: backup.catalog,
        savedAt: backup.savedAt,
        recoveredPrevious: true,
      );
    });
  }

  /// Only called after a current, authenticated cloud snapshot has decoded.
  /// Two generations protect the last validated projection from torn writes.
  Future<void> save(String accountId, MediaFlowCatalog catalog) {
    final hash = _ownerHash(accountId);
    // Queue before compression. A sign-out purge must never race an in-flight
    // serialization and leave a newly written cache behind.
    return _exclusive(() async {
      final stamp = DateTime.now().toUtc().toIso8601String();
      final compressed = await compute(_compressProjection, catalog);
      final digest = _checksum(hash, stamp, compressed);
      final envelope = jsonEncode({
        'format': format,
        'ownerHash': hash,
        'savedAt': stamp,
        'payload': compressed,
        'checksum': digest,
      });
      if (utf8.encode(envelope).length > maxFileBytes) {
        throw const FormatException('Offline projection exceeds device cache limit');
      }
      final folder = await _directory();
      await folder.create(recursive: true);
      final primary = File(_path(folder, hash));
      final backup = File(primary.path + '.previous');
      final temp = File(primary.path + '.pending');
      try {
        await temp.writeAsString(envelope, flush: true);
        // A newly corrupted primary must never replace a valid backup.
        if (await primary.exists()) {
          if (await _read(primary, hash) != null) {
            if (await backup.exists()) await backup.delete();
            await primary.rename(backup.path);
          } else {
            await primary.delete();
          }
        }
        await temp.rename(primary.path);
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    });
  }

  /// This removes only this account's device projection, not cloud data.
  Future<void> clear(String accountId) {
    final hash = _ownerHash(accountId);
    return _exclusive(() async {
      final folder = await _directory();
      final path = _path(folder, hash);
      for (final suffix in ['', '.previous', '.pending']) {
        final candidate = File(path + suffix);
        if (await candidate.exists()) await candidate.delete();
      }
    });
  }

  Future<NativeCachedSnapshot?> _read(File file, String ownerHash) async {
    try {
      if (!await file.exists() || await file.length() > maxFileBytes) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map ||
          raw['format'] != format ||
          raw['ownerHash'] != ownerHash ||
          raw['savedAt'] is! String ||
          raw['payload'] is! String ||
          raw['checksum'] is! String) {
        return null;
      }
      final stamp = raw['savedAt'] as String;
      final savedAt = DateTime.tryParse(stamp);
      if (savedAt == null) return null;
      final payload = raw['payload'] as String;
      if (raw['checksum'] != _checksum(ownerHash, stamp, payload)) return null;
      final catalog = await compute(_expandProjection, payload);
      return NativeCachedSnapshot(
        catalog: catalog,
        savedAt: savedAt,
        recoveredPrevious: false,
      );
    } catch (_) {
      // Corrupt, truncated, unsupported and inaccessible files are never used.
      return null;
    }
  }

  String _checksum(String hash, String stamp, String payload) =>
      sha256.convert(utf8.encode([format, hash, stamp, payload].join('\n')))
          .toString();
}

class NativeCachedSnapshot {
  const NativeCachedSnapshot({
    required this.catalog,
    required this.savedAt,
    required this.recoveredPrevious,
  });

  final MediaFlowCatalog catalog;
  final DateTime savedAt;
  final bool recoveredPrevious;
}

String _compressProjection(MediaFlowCatalog catalog) {
  final raw = jsonEncode(NativeOfflineProjectionCodec.encode(catalog));
  return base64Encode(gzip.encode(utf8.encode(raw)));
}

/// Chunking also caps decompression of a damaged/hostile local gzip payload.
MediaFlowCatalog _expandProjection(String payload) {
  final bytes = base64Decode(payload);
  final sink = _BoundedBytesSink();
  final decoder = gzip.decoder.startChunkedConversion(sink);
  const chunkSize = 64 * 1024;
  for (var position = 0; position < bytes.length; position += chunkSize) {
    final end = position + chunkSize < bytes.length
        ? position + chunkSize : bytes.length;
    decoder.add(bytes.sublist(position, end));
  }
  decoder.close();
  final raw = utf8.decode(sink.bytes.takeBytes());
  return NativeOfflineProjectionCodec.decode(jsonDecode(raw));
}

class _BoundedBytesSink implements Sink<List<int>> {
  static const maxUncompressedBytes = 192 * 1024 * 1024;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int total = 0;

  @override
  void add(List<int> chunk) {
    total += chunk.length;
    if (total > maxUncompressedBytes) {
      throw const FormatException('Offline projection expands past safe limit');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
