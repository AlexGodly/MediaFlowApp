// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'native_offline_key_vault.dart';
import 'native_sync_review.dart';

/// Encrypted device-only pending REVIEW (not a cloud write/retry queue).
/// The signed-in account must explicitly inspect a fresh full cloud row
/// before any simulated action; this class has no network dependencies.
class NativePendingReviewStore {
  NativePendingReviewStore({
    Future<Directory> Function()? directoryProvider,
    NativeOfflineKeyVault? keyVault,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _keys = keyVault ?? PlatformOfflineKeyVault();

  static const format = 'mediaflow-encrypted-pending-review-v1';
  static const maxFileBytes = 2 * 1024 * 1024;
  final Future<Directory> Function() _directoryProvider;
  final NativeOfflineKeyVault _keys;
  Future<void> _gate = Future<void>.value();

  // The distinct hash is a key-vault namespace too: clearing the M18
  // snapshot key must not corrupt a pending record unexpectedly.
  String _hash(String accountId) {
    if (accountId.isEmpty) throw StateError('Signed-in owner required');
    return sha256.convert(utf8.encode('m19-pending-review:' + accountId))
        .toString();
  }

  Future<File> _file(String ownerHash) async {
    final root = await _directoryProvider();
    return File(root.path + Platform.pathSeparator +
        'mediaflow-pending-review-v1' + Platform.pathSeparator +
        'review-' + ownerHash + '.json');
  }

  Future<void> _serialized(Future<void> Function() action) {
    final next = _gate.then((_) => action());
    _gate = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<T> _after<T>(Future<T> Function() action) async {
    await _gate;
    return action();
  }

  Future<void> save(NativeReviewBatch batch, String signedInOwnerId) {
    if (signedInOwnerId.isEmpty || batch.ownerId != signedInOwnerId) {
      throw StateError('Account mismatch for pending review');
    }
    // Deep validation BEFORE acquiring the write gate.
    final sanitized = NativeReviewBatch.fromJson(
      batch.toJson(), signedInOwnerId: signedInOwnerId,
    );
    return _serialized(() async {
      final hash = _hash(signedInOwnerId);
      var key = await _keys.read(hash);
      if (key == null) {
        final random = Random.secure();
        key = Uint8List.fromList(List.generate(
          32, (_) => random.nextInt(256),
        ));
        await _keys.write(hash, key);
        if (!listEquals(await _keys.read(hash), key)) {
          throw StateError('Could not verify pending-review encryption key');
        }
      }
      if (key.length != 32) {
        throw StateError('Invalid pending-review encryption key');
      }
      final random = Random.secure();
      final nonce = List<int>.generate(12, (_) => random.nextInt(256));
      final plain = utf8.encode(jsonEncode(sanitized.toJson()));
      final box = await AesGcm.with256bits().encrypt(
        plain,
        secretKey: SecretKey(key),
        nonce: nonce,
        aad: utf8.encode(format + ':' + hash),
      );
      final encoded = jsonEncode({
        'format': format,
        'ownerHash': hash,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      });
      if (utf8.encode(encoded).length > maxFileBytes) {
        throw const FormatException('Encrypted pending review is too large');
      }
      final primary = await _file(hash);
      await primary.parent.create(recursive: true);
      final pending = File(primary.path + '.pending');
      try {
        await pending.writeAsString(encoded, flush: true);
        // A pending record cannot become active until the complete authenticated
        // ciphertext was durably written. No automatic execution ever occurs.
        if (await primary.exists()) await primary.delete();
        await pending.rename(primary.path);
      } finally {
        if (await pending.exists()) await pending.delete();
      }
    });
  }

  Future<NativeReviewBatch?> load(String signedInOwnerId) {
    final hash = _hash(signedInOwnerId);
    return _after(() async {
      try {
        final key = await _keys.read(hash);
        if (key == null || key.length != 32) return null;
        final primary = await _file(hash);
        if (!await primary.exists() ||
            await primary.length() > maxFileBytes) return null;
        final raw = jsonDecode(await primary.readAsString());
        if (raw is! Map ||
            raw['format'] != format ||
            raw['ownerHash'] != hash ||
            raw['nonce'] is! String ||
            raw['mac'] is! String ||
            raw['ciphertext'] is! String) return null;
        final nonce = base64Decode(raw['nonce'] as String);
        final mac = base64Decode(raw['mac'] as String);
        final cipher = base64Decode(raw['ciphertext'] as String);
        if (nonce.length != 12 || mac.length != 16 ||
            cipher.length > maxFileBytes) return null;
        final plain = await AesGcm.with256bits().decrypt(
          SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
          secretKey: SecretKey(key),
          aad: utf8.encode(format + ':' + hash),
        );
        if (plain.length > NativeReviewBatch.maxSerializedBytes) return null;
        final decoded = jsonDecode(utf8.decode(plain));
        if (decoded is! Map) return null;
        return NativeReviewBatch.fromJson(
          Map<String, dynamic>.from(decoded),
          signedInOwnerId: signedInOwnerId,
        );
      } catch (_) {
        // A foreign, corrupt, locked, or tampered record always fails closed.
        return null;
      }
    });
  }

  /// Wipes the signed-in account's key and files. Called before sign-out.
  Future<void> clear(String signedInOwnerId) {
    final hash = _hash(signedInOwnerId);
    return _serialized(() async {
      Object? failure;
      try {
        await _keys.delete(hash);
      } catch (error) {
        failure = error;
      }
      final primary = await _file(hash);
      for (final suffix in ['', '.pending']) {
        try {
          final file = File(primary.path + suffix);
          if (await file.exists()) await file.delete();
        } catch (error) {
          failure ??= error;
        }
      }
      if (failure != null) {
        throw StateError('Cannot fully clear private pending review');
      }
    });
  }
}
