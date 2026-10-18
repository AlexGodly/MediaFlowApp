import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow_app/cloud/mediaflow_cloud.dart';

Map<String, dynamic> state() => {
  'library': [
    {'id': 'a', 'title': 'The Mentalist', 'categoryId': 'tv',
      'progress': 15, 'total': 151, 'status': 'active', 'coverUrl': ''},
  ],
  'categories': [{'id': 'tv', 'name': 'TV Shows'}],
  'sessions': [{'id': 'past'}],
  'opaqueFutureSettings': {'mustBePreserved': true},
};

void main() {
  test('decodes live website plain JSON snapshot without defaults', () {
    final decoded = MediaFlowCloudSnapshot.decode(
      ownerId: 'owner', revision: '2026-10-18T12:00:00Z',
      rawState: state());
    expect(decoded.library.single.title, 'The Mentalist');
    expect(decoded.library.single.progress, 15);
    expect(decoded.previousSessions, 1);
    expect(decoded.categories['tv'], 'TV Shows');
  });

  test('supports existing website gzip/base64 snapshot', () {
    final wire = {
      '__mediaflowCompressed': 'gzip',
      'data': base64Encode(gzip.encode(utf8.encode(jsonEncode(state())))),
    };
    final decoded = MediaFlowCloudSnapshot.decode(
      ownerId: 'owner', revision: 'rev', rawState: wire);
    expect(decoded.library.single.id, 'a');
  });

  test('rejects missing or invalid cloud data rather than empty account', () {
    expect(() => MediaFlowCloudSnapshot.decode(
      ownerId: 'owner', revision: 'rev',
      rawState: {'library': []}), throwsFormatException);
    expect(() => MediaFlowCloudSnapshot.decode(
      ownerId: 'owner', revision: 'rev', rawState: null),
      throwsFormatException);
    expect(() => MediaFlowCloudSnapshot.decode(
      ownerId: 'owner', revision: 'rev',
      rawState: {'__mediaflowCompressed': 'lz4', 'data': 'abc'}),
      throwsFormatException);
  });
}
