// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/mediaflow_models.dart';
import 'native_offline_key_vault.dart';
import 'native_offline_projection_codec.dart';

/// Encrypted, account-isolated read-only device cache, never a sync authority.
/// AES-256-GCM keys are held by the OS-protected key vault, NOT the cache files.
/// Old M17 plaintext caches are intentionally discarded, not loaded as fallback.
class NativeOfflineSnapshotStore {
  NativeOfflineSnapshotStore({
    Future<Directory> Function()? directoryProvider,
    NativeOfflineKeyVault? keyVault,
  })  : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
        _keys = keyVault ?? PlatformOfflineKeyVault();

  static const format = 'mediaflow-native-encrypted-snapshot-v2';
  static const maxFileBytes = 96 * 1024 * 1024;
  static const maxExpandedBytes = 192 * 1024 * 1024;
  static const keyLength = 32;
  static const nonceLength = 12;

  final Future<Directory> Function() _directoryProvider;
  final NativeOfflineKeyVault _keys;
  Future<void> _writes = Future<void>.value();

  String _ownerHash(String accountId) {
    if (accountId.isEmpty) {
      throw StateError('An authenticated account is required');
    }
    return sha256.convert(utf8.encode(accountId)).toString();
  }

  Future<Directory> _folder() async {
    final root = await _directoryProvider();
    return Directory(root.path + Platform.pathSeparator +
        'mediaflow-offline-v2');
  }

  Future<Directory> _legacyFolder() async {
    final root = await _directoryProvider();
    return Directory(root.path + Platform.pathSeparator +
        'mediaflow-offline');
  }

  String _path(Directory folder, String hash) =>
      folder.path + Platform.pathSeparator + 'snapshot-' + hash + '.json';

  Future<T> _afterWrites<T>(Future<T> Function() action) async {
    await _writes;
    return action();
  }

  Future<void> _exclusive(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    // A failed write must not poison the next queued cache operation.
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _purgeLegacy(String hash) async {
    final folder = await _legacyFolder();
    final path = _path(folder, hash);
    for (final suffix in ['', '.previous', '.pending']) {
      final file = File(path + suffix);
      if (await file.exists()) await file.delete();
    }
  }

  /// Checks the authenticated account's current and previous encrypted copy.
  /// A missing OS key, bad authentication tag or malformed file fails closed.
  Future<NativeCachedSnapshot?> load(String accountId) {
    final hash = _ownerHash(accountId);
    return _afterWrites(() async {
      // Never expose M17 unencrypted caches after upgrading.
      await _purgeLegacy(hash);
      Uint8List? key;
      try {
        key = await _keys.read(hash);
      } catch (_) {
        return null;
      }
      if (key == null || key.length != keyLength) return null;
      final main = File(_path(await _folder(), hash));
      final current = await _read(main, hash, key);
      if (current != null) return current;
      final older = await _read(File(main.path + '.previous'), hash, key);
      return older == null ? null : NativeCachedSnapshot(
        catalog: older.catalog,
        savedAt: older.savedAt,
        recoveredPrevious: true,
      );
    });
  }

  /// Only called after an authenticated, successfully decoded cloud SELECT.
  /// Key provisioning and all file mutations are serialized with sign-out
  /// deletion to prevent a stale background save from restoring old data.
  Future<void> save(String accountId, MediaFlowCatalog catalog) {
    final hash = _ownerHash(accountId);
    return _exclusive(() async {
      await _purgeLegacy(hash);
      var key = await _keys.read(hash);
      if (key == null) {
        key = Uint8List.fromList(List<int>.generate(
          keyLength, (_) => Random.secure().nextInt(256),
        ));
        await _keys.write(hash, key);
        final verified = await _keys.read(hash);
        if (verified == null || !listEquals(verified, key)) {
          throw StateError('Secure device key could not be verified');
        }
      }
      if (key.length != keyLength) {
        throw StateError('Invalid secure device key length');
      }

      final savedAt = DateTime.now().toUtc().toIso8601String();
      final nonce = Uint8List.fromList(List<int>.generate(
        nonceLength, (_) => Random.secure().nextInt(256),
      ));
      final envelope = await compute(
        _sealProjection,
        _SealRequest(catalog, key, hash, savedAt, nonce),
      );
      final serialized = jsonEncode(envelope);
      if (utf8.encode(serialized).length > maxFileBytes) {
        throw const FormatException('Encrypted snapshot exceeds device limit');
      }

      final folder = await _folder();
      await folder.create(recursive: true);
      final main = File(_path(folder, hash));
      final previous = File(main.path + '.previous');
      final pending = File(main.path + '.pending');
      try {
        await pending.writeAsString(serialized, flush: true);
        // Never promote a corrupt or incorrectly keyed primary to backup.
        if (await main.exists()) {
          if (await _read(main, hash, key) != null) {
            if (await previous.exists()) await previous.delete();
            await main.rename(previous.path);
          } else {
            await main.delete();
          }
        }
        await pending.rename(main.path);
      } finally {
        if (await pending.exists()) await pending.delete();
      }
    });
  }

  /// Removes the key as well as all current, previous, pending and M17 copies.
  /// Clearing never touches Supabase or another user's cache.
  Future<void> clear(String accountId) {
    final hash = _ownerHash(accountId);
    return _exclusive(() async {
      Object? failure;
      try {
        await _keys.delete(hash);
      } catch (error) {
        failure = error;
      }
      try {
        final folder = await _folder();
        final filePath = _path(folder, hash);
        for (final suffix in ['', '.previous', '.pending']) {
          final file = File(filePath + suffix);
          if (await file.exists()) await file.delete();
        }
        await _purgeLegacy(hash);
      } catch (error) {
        failure ??= error;
      }
      if (failure != null) {
        throw StateError('Could not completely clear local account data');
      }
    });
  }

  Future<NativeCachedSnapshot?> _read(
    File file, String hash, Uint8List key,
  ) async {
    try {
      if (!await file.exists() || await file.length() > maxFileBytes) {
        return null;
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map ||
          raw['format'] != format ||
          raw['ownerHash'] != hash ||
          raw['savedAt'] is! String ||
          raw['nonce'] is! String ||
          raw['ciphertext'] is! String ||
          raw['mac'] is! String) {
        return null;
      }
      final savedAt = DateTime.tryParse(raw['savedAt'] as String);
      if (savedAt == null) return null;
      final date = raw['savedAt'] as String;
      final catalog = await compute(
        _openProjection,
        _OpenRequest(
          key, hash, date, raw['nonce'] as String,
          raw['ciphertext'] as String, raw['mac'] as String,
        ),
      );
      return NativeCachedSnapshot(
        catalog: catalog, savedAt: savedAt, recoveredPrevious: false,
      );
    } catch (_) {
      // Any AEAD/MAC failure, invalid data or inaccessible file fails closed.
      return null;
    }
  }
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

class _SealRequest {
  const _SealRequest(
    this.catalog, this.key, this.hash, this.savedAt, this.nonce,
  );
  final MediaFlowCatalog catalog;
  final Uint8List key, nonce;
  final String hash, savedAt;
}

class _OpenRequest {
  const _OpenRequest(
    this.key, this.hash, this.savedAt, this.nonce,
    this.ciphertext, this.mac,
  );
  final Uint8List key;
  final String hash, savedAt, nonce, ciphertext, mac;
}

List<int> _associatedData(String hash, String savedAt) =>
    utf8.encode([NativeOfflineSnapshotStore.format, hash, savedAt].join('\n'));

Future<Map<String, String>> _sealProjection(_SealRequest request) async {
  final raw = jsonEncode(NativeOfflineProjectionCodec.encode(request.catalog));
  final compressed = gzip.encode(utf8.encode(raw));
  if (compressed.length > NativeOfflineSnapshotStore.maxFileBytes) {
    throw const FormatException('Compressed projection is too large');
  }
  final box = await AesGcm.with256bits().encrypt(
    compressed,
    secretKey: SecretKey(request.key),
    nonce: request.nonce,
    aad: _associatedData(request.hash, request.savedAt),
  );
  return {
    'format': NativeOfflineSnapshotStore.format,
    'ownerHash': request.hash,
    'savedAt': request.savedAt,
    'nonce': base64Encode(box.nonce),
    'ciphertext': base64Encode(box.cipherText),
    'mac': base64Encode(box.mac.bytes),
  };
}

Future<MediaFlowCatalog> _openProjection(_OpenRequest request) async {
  final nonce = base64Decode(request.nonce);
  final ciphertext = base64Decode(request.ciphertext);
  final mac = base64Decode(request.mac);
  if (nonce.length != NativeOfflineSnapshotStore.nonceLength ||
      mac.length != 16 ||
      ciphertext.length > NativeOfflineSnapshotStore.maxFileBytes) {
    throw const FormatException('Invalid encrypted snapshot size');
  }
  final box = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
  // Decrypt authenticates the whole payload and bound owner/revision header
  // before any compressed content is parsed or displayed.
  final compressed = await AesGcm.with256bits().decrypt(
    box,
    secretKey: SecretKey(request.key),
    aad: _associatedData(request.hash, request.savedAt),
  );
  final sink = _BoundedBytesSink();
  final decoder = gzip.decoder.startChunkedConversion(sink);
  const chunkSize = 64 * 1024;
  for (var position = 0; position < compressed.length; position += chunkSize) {
    final end = position + chunkSize < compressed.length
        ? position + chunkSize : compressed.length;
    decoder.add(compressed.sublist(position, end));
  }
  decoder.close();
  return NativeOfflineProjectionCodec.decode(
    jsonDecode(utf8.decode(sink.bytes.takeBytes())),
  );
}

class _BoundedBytesSink implements Sink<List<int>> {
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int total = 0;
  @override
  void add(List<int> chunk) {
    total += chunk.length;
    if (total > NativeOfflineSnapshotStore.maxExpandedBytes) {
      throw const FormatException('Offline snapshot expands past safe limit');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}
