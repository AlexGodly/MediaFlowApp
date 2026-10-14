import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The per-account encryption key must never be stored next to cache files.
/// Platform storage typically delegates to the Android Keystore, Apple
/// Keychain, or Windows OS-protected storage (exact guarantees vary by OS).
abstract class NativeOfflineKeyVault {
  Future<Uint8List?> read(String ownerHash);
  Future<void> write(String ownerHash, Uint8List keyBytes);
  Future<void> delete(String ownerHash);
}

class PlatformOfflineKeyVault implements NativeOfflineKeyVault {
  PlatformOfflineKeyVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String hash) => 'mediaflowapp.native.offline.aes256.v2.$hash';

  @override
  Future<Uint8List?> read(String ownerHash) async {
    final encoded = await _storage.read(key: _key(ownerHash));
    if (encoded == null) return null;
    final key = base64Decode(encoded);
    if (key.length != 32) {
      throw const FormatException('Invalid protected offline key');
    }
    return Uint8List.fromList(key);
  }

  @override
  Future<void> write(String ownerHash, Uint8List keyBytes) async {
    if (keyBytes.length != 32) {
      throw ArgumentError('Expected 256-bit encryption key');
    }
    await _storage.write(
      key: _key(ownerHash), value: base64Encode(keyBytes),
    );
  }

  @override
  Future<void> delete(String ownerHash) =>
      _storage.delete(key: _key(ownerHash));
}
