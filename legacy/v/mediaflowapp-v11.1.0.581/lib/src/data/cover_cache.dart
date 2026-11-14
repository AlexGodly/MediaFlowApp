// Covers saved on the device, so the Library and logging show them offline.
// A cover is downloaded the first time it is shown, then always read from disk.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

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

  /// Why the last download of a link failed (10.0.0), shown in Settings.
  final Map<String, CoverFailure> failures = {};

  /// The cover on disk, downloading it first if needed. Null when it can't be
  /// had right now (offline and never seen, or a broken link); the reason is
  /// in [failures]. A failure is never permanent: the next call tries again.
  Future<File?> file(String url) {
    if (!url.startsWith('http')) return Future.value(null);
    final hit = ready[url];
    if (hit != null) return Future.value(hit);
    return _pending.putIfAbsent(url, () async {
      final r = await _download(url);
      if (r.file != null) {
        failures.remove(url);
        return ready[url] = r.file!;
      }
      failures[url] = r.failure!;
      return null;
    }).whenComplete(() => _pending.remove(url)); // allows a retry later (e.g. back online)
  }

  Future<File?> _target(String url) async {
    try {
      final dir = await _root();
      return File('${dir.path}${Platform.pathSeparator}${_key(url)}');
    } catch (_) {
      return null;
    }
  }

  Future<({File? file, CoverFailure? failure})> _download(String url) async {
    final f = await _target(url);
    if (f == null) return (file: null, failure: const CoverFailure('Could not save on this device', recoverable: true));
    if (await f.exists() && await f.length() > 0) return (file: f, failure: null);
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return (file: null, failure: const CoverFailure('Not a valid link', recoverable: false));
    // Browser-like requests: several image hosts refuse unknown clients or
    // requests without the site they are shown on (hot-link protection).
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
    try {
      final req = await client.getUrl(uri);
      req.followRedirects = true;
      req.maxRedirects = 6;
      req.headers
        ..set(HttpHeaders.acceptHeader, 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8')
        ..set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9')
        ..set(HttpHeaders.refererHeader, '${uri.scheme}://${uri.host}/');
      final res = await req.close().timeout(const Duration(seconds: 25));
      final code = res.statusCode;
      if (code != 200) {
        await res.drain<void>().catchError((_) {});
        return (file: null, failure: CoverFailure.http(code));
      }
      final type = res.headers.contentType?.mimeType ?? '';
      if (type.startsWith('text/') || type.contains('json')) {
        await res.drain<void>().catchError((_) {});
        return (file: null, failure: const CoverFailure('The link opens a web page, not an image', recoverable: false));
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(const Duration(seconds: 40))) {
        bytes.add(chunk);
        if (bytes.length > 15 * 1024 * 1024) return (file: null, failure: const CoverFailure('The image is too large (over 15 MB)', recoverable: false));
      }
      if (bytes.isEmpty) return (file: null, failure: const CoverFailure('The host sent an empty image', recoverable: true));
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(bytes.takeBytes(), flush: true);
      await tmp.rename(f.path);
      return (file: f, failure: null);
    } on TimeoutException {
      return (file: null, failure: const CoverFailure('The host took too long to answer', recoverable: true));
    } on SocketException catch (e) {
      final m = e.message.toLowerCase();
      return (
        file: null,
        failure: CoverFailure(m.contains('host lookup') ? 'No connection, or the site no longer exists' : 'Connection problem', recoverable: true),
      );
    } on HandshakeException {
      return (file: null, failure: const CoverFailure('The site\'s secure connection failed', recoverable: true));
    } on HttpException catch (e) {
      return (file: null, failure: CoverFailure('Download interrupted (${e.message})', recoverable: true));
    } catch (e) {
      return (file: null, failure: CoverFailure('Download failed ($e)', recoverable: true));
    } finally {
      client.close(force: true);
    }
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

/// Why a cover could not be downloaded, and whether trying again may help.
class CoverFailure {
  const CoverFailure(this.reason, {required this.recoverable});
  final String reason;
  final bool recoverable;

  factory CoverFailure.http(int code) => switch (code) {
        404 || 410 => CoverFailure('The image is gone from its site (error $code); find a new cover', recoverable: false),
        401 || 403 => CoverFailure('The site refuses downloads of this image (error $code)', recoverable: true),
        429 => const CoverFailure('The site asked to slow down (error 429)', recoverable: true),
        >= 500 => CoverFailure('The site had a problem (error $code)', recoverable: true),
        _ => CoverFailure('The site answered with error $code', recoverable: code < 400 || code >= 500),
      };
}
