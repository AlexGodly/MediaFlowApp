// Covers saved on the device, so the Library and logging show them offline.
// A cover is downloaded the first time it is shown, then always read from disk.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CoverCache {
  CoverCache._();
  static final CoverCache instance = CoverCache._();

  Directory? _dir;
  final Map<String, Future<File?>> _pending = {};

  /// Covers already resolved in this run (lets widgets draw without a frame of placeholder).
  final Map<String, File> ready = {};

  Future<Directory> _root() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}covers');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  static String _key(String url) {
    // FNV-1a 64-bit: short, stable file names.
    var h = 0xcbf29ce484222325;
    for (final c in url.codeUnits) {
      h ^= c;
      h = h * 0x100000001b3; // wraps at 64 bits
    }
    return (h >>> 32).toRadixString(16).padLeft(8, '0') + (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  }

  /// The cover on disk, downloading it first if needed. Null when it can't be
  /// had right now (offline and never seen, or a broken link).
  Future<File?> file(String url) {
    if (!url.startsWith('http')) return Future.value(null);
    final hit = ready[url];
    if (hit != null) return Future.value(hit);
    return _pending.putIfAbsent(url, () async {
      try {
        final dir = await _root();
        final f = File('${dir.path}${Platform.pathSeparator}${_key(url)}');
        if (await f.exists() && await f.length() > 0) return ready[url] = f;
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
        try {
          final req = await client.getUrl(Uri.parse(url));
          final res = await req.close().timeout(const Duration(seconds: 20));
          if (res.statusCode != 200) return null;
          final bytes = <int>[];
          await for (final chunk in res) {
            bytes.addAll(chunk);
            if (bytes.length > 12 * 1024 * 1024) return null;
          }
          if (bytes.isEmpty) return null;
          final tmp = File('${f.path}.part');
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(f.path);
          return ready[url] = f;
        } finally {
          client.close(force: true);
        }
      } catch (_) {
        return null;
      }
    }).whenComplete(() => _pending.remove(url)); // allows a retry later (e.g. back online)
  }

  Future<int> sizeBytes() async {
    try {
      final dir = await _root();
      var total = 0;
      await for (final e in dir.list()) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    ready.clear();
    try {
      final dir = await _root();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}
