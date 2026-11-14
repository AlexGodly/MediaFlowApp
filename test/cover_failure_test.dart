// 10.0.0: offline cover downloads say why a cover failed, and only a broken
// link (gone, not an image) is reported as needing a new cover; everything
// else may work later and is tried again.

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/cover_cache.dart';

void main() {
  test('HTTP errors map to a reason and whether a retry may help', () {
    expect(CoverFailure.http(404).recoverable, isFalse);
    expect(CoverFailure.http(404).reason, contains('find a new cover'));
    expect(CoverFailure.http(410).recoverable, isFalse);
    expect(CoverFailure.http(403).recoverable, isTrue);
    expect(CoverFailure.http(429).recoverable, isTrue);
    expect(CoverFailure.http(503).recoverable, isTrue);
    expect(CoverFailure.http(400).recoverable, isFalse);
    for (final c in [400, 403, 404, 429, 500, 503]) {
      expect(CoverFailure.http(c).reason, contains('$c'));
    }
  });

  test('a failed link is not remembered as unavailable for good', () async {
    final cache = CoverCache.instance;
    expect(await cache.file('not-a-link'), isNull);
    expect(cache.failures.containsKey('not-a-link'), isFalse, reason: 'non-http links are skipped, not failed');
  });
}
