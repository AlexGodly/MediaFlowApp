import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/metadata_search.dart';

void main() {
  tearDown(() => providerGateway = null);

  test('cover sources follow settings.v424Covers.enabled', () {
    expect(enabledCoverSources(null), containsAll(kDefaultCoverSources));
    expect(enabledCoverSources({'v424Covers': {'enabled': ['anilist']}}), {'anilist', 'itunes'});
  });

  test('gateway providers are used only when configured', () async {
    final sent = <String>[];
    providerGateway = (body) async {
      sent.add('${body['action']}:${body['provider'] ?? ''}');
      if (body['action'] == 'status') {
        return {
          'providers': [
            {'id': 'omdb', 'configured': true, 'testable': true},
            {'id': 'fanart', 'configured': false, 'testable': true},
          ],
        };
      }
      return {
        'results': [
          {'provider': body['provider'], 'title': 'Dune', 'url': 'https://x/a.jpg', 'externalIdKey': 'imdb', 'externalIdValue': 'tt1'},
        ],
      };
    };
    await gatewayStatus(refresh: true);
    final omdb = await searchGateway('omdb', 'Dune');
    final fanart = await searchGateway('fanart', 'Dune');
    expect(omdb.single.source, 'OMDb');
    expect(omdb.single.externalIdKey, 'imdb');
    expect(fanart, isEmpty);
    expect(sent.where((s) => s.startsWith('search')).toList(), ['search:omdb']);
  });
}
