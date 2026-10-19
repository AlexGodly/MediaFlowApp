// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'native_m33_offline_queue.dart';
import 'native_offline_key_vault.dart';

/// Dedicated owner-scoped AES-256-GCM *offline draft* store (not a sync queue).
/// Contents remain unavailable without this owner's OS-protected key.
/// NEVER upload the ciphertext or promote it to a v410 cloud state.
class NativeM33DraftStore {
  NativeM33DraftStore({
    Future<Directory> Function()? directoryProvider,
    NativeOfflineKeyVault? keyVault,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _vault = keyVault ?? PlatformOfflineKeyVault();

  static const format = 'mediaflow-m33-device-drafts-aes256-v1';
  static const maxBytes = 1024 * 1024;
  final Future<Directory> Function() _directoryProvider;
  final NativeOfflineKeyVault _vault;
  Future<void> _operations = Future<void>.value();

  String _hash(String owner) {
    if (owner.isEmpty) throw StateError('Signed-in owner required');
    return sha256.convert(utf8.encode('m33-device-drafts:' + owner)).toString();
  }

  Future<File> _file(String hash) async {
    final root = await _directoryProvider();
    return File(root.path + Platform.pathSeparator + 'mediaflow-m33-drafts' +
        Platform.pathSeparator + 'queue-' + hash + '.json');
  }

  Future<T> _after<T>(Future<T> Function() work) async {
    await _operations;
    return work();
  }

  Future<void> _exclusive(Future<void> Function() work) {
    final next = _operations.then((_) => work());
    _operations = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<NativeM33OfflineDraftQueue?> load(String owner) {
    final hash = _hash(owner);
    return _after(() async {
      Uint8List? key;
      try {
        key = await _vault.read(hash);
      } catch (_) {
        return null;
      }
      if (key == null || key.length != 32) return null;
      final primary = await _file(hash);
      final recent = await _read(primary, hash, key, owner);
      if (recent != null) return recent;
      return _read(File(primary.path + '.previous'), hash, key, owner);
    });
  }

  Future<void> save(
    String owner,
    NativeM33OfflineDraftQueue queue, {
    String? explicitlyReplacingQueueId,
    bool forgetPreviousOnReplace = false,
  }) {
    if (owner.isEmpty || owner != queue.ownerId) {
      throw StateError('Foreign offline draft queue');
    }
    final sanitized = NativeM33OfflineDraftQueue.fromJson(
      Map<String, dynamic>.from(queue.toJson()), signedInOwnerId: owner,
    );
    final plain = utf8.encode(jsonEncode(sanitized.toJson()));
    if (plain.length > maxBytes) {
      throw const FormatException('Offline draft size limit exceeded');
    }

    return _exclusive(() async {
      final hash = _hash(owner);
      final primary = await _file(hash);
      final previous = File(primary.path + '.previous');
      final pending = File(primary.path + '.pending');
      var key = await _vault.read(hash);
      // Missing OS key for existing ciphertext must NOT cause silent rewrite.
      if (key == null) {
        if (await primary.exists() || await previous.exists() ||
            await pending.exists()) {
          throw StateError('Existing encrypted drafts require their old key');
        }
        final random = Random.secure();
        key = Uint8List.fromList(List.generate(32,
          (_) => random.nextInt(256)));
        await _vault.write(hash, key);
        if (!listEquals(await _vault.read(hash), key)) {
          throw StateError('Could not verify device encryption key');
        }
      }
      if (key.length != 32) {
        throw StateError('Invalid AES-256 offline draft key');
      }
      final current = await _read(primary, hash, key, owner);
      if (await primary.exists() && current == null) {
        throw StateError('Unreadable current draft must not be overwritten');
      }
      if (current == null && await previous.exists()) {
        throw StateError('Recover previous encrypted drafts before saving');
      }
      if (current != null &&
          (explicitlyReplacingQueueId == null ||
           current.queueId != explicitlyReplacingQueueId)) {
        throw StateError('An encrypted draft exists; discard first');
      }

      final random = Random.secure();
      final nonce = List<int>.generate(12, (_) => random.nextInt(256));
      final box = await AesGcm.with256bits().encrypt(
        plain,
        secretKey: SecretKey(key),
        nonce: nonce,
        aad: utf8.encode(format + ':' + hash),
      );
      final text = jsonEncode({
        'format': format, 'ownerHash': hash,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      });
      if (utf8.encode(text).length > maxBytes) {
        throw const FormatException('Encrypted offline draft too large');
      }

      await primary.parent.create(recursive: true);
      try {
        await pending.writeAsString(text, flush: true);
        if (current != null) {
          if (await previous.exists()) await previous.delete();
          await primary.rename(previous.path);
        }
        await pending.rename(primary.path);
        // A targeted discard must not preserve deleted draft entries in
        // the usual rollback generation after successful replacement.
        if (forgetPreviousOnReplace && await previous.exists()) {
          await previous.delete();
        }
      } finally {
        if (await pending.exists()) await pending.delete();
      }
    });
  }

  /// M34 intentionally prunes backup generation on successful local rewrite.
  Future<void> replaceForResolution(
    String owner, NativeM33OfflineDraftQueue queue, String oldQueueId,
  ) => save(owner, queue, explicitlyReplacingQueueId: oldQueueId,
      forgetPreviousOnReplace: true);

  Future<NativeM33OfflineDraftQueue?> _read(
    File file, String hash, Uint8List key, String owner,
  ) async {
    try {
      if (!await file.exists() || await file.length() > maxBytes) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map || data['format'] != format ||
          data['ownerHash'] != hash ||
          data['nonce'] is! String ||
          data['ciphertext'] is! String || data['mac'] is! String) {
        return null;
      }
      final nonce = base64Decode(data['nonce'] as String);
      final mac = base64Decode(data['mac'] as String);
      final cipher = base64Decode(data['ciphertext'] as String);
      if (nonce.length != 12 || mac.length != 16 || cipher.length > maxBytes) {
        return null;
      }
      final opened = await AesGcm.with256bits().decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key),
        aad: utf8.encode(format + ':' + hash),
      );
      if (opened.length > maxBytes) return null;
      final raw = jsonDecode(utf8.decode(opened));
      if (raw is! Map) return null;
      return NativeM33OfflineDraftQueue.fromJson(
        Map<String, dynamic>.from(raw), signedInOwnerId: owner,
      );
    } catch (_) {
      // Wrong account, corrupted ciphertext, unavailable keys, incompatible
      // queue formats and truncated files all fail closed.
      return null;
    }
  }

  /// Wipes per-owner key and all generations, serially after pending saves.
  Future<void> clear(String owner) {
    final hash = _hash(owner);
    return _exclusive(() async {
      Object? failure;
      try {
        await _vault.delete(hash);
      } catch (error) {
        failure = error;
      }
      try {
        final primary = await _file(hash);
        for (final suffix in ['', '.previous', '.pending']) {
          final file = File(primary.path + suffix);
          if (await file.exists()) await file.delete();
        }
      } catch (error) {
        failure ??= error;
      }
      if (failure != null) {
        throw StateError('Could not remove all encrypted offline drafts');
      }
    });
  }
}
