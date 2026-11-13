// TMDB covers through MediaFlow's provider gateway (website v434 + v559).

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/metadata_search.dart';

void main() {
  tearDown(() => providerGateway = null);

  test('movie / TV hint like the website', () {
    expect(tmdbKind(categoryId: 'cat_movies', categoryName: 'Movies'), 'movie');
    expect(tmdbKind(categoryId: 'x', categoryName: 'TV Shows'), 'tv');
    expect(tmdbKind(categoryId: 'x', categoryName: 'Finished Anime'), '');
    expect(tmdbKind(categoryId: 'x', categoryName: 'Anime', externalIds: {'tmdb_tv': '1429'}), 'tv');
  });

  test('sends a search for the signed-in account and reads poster results', () async {
    final sent = <Map<String, dynamic>>[];
    providerGateway = (body) async {
      sent.add(body);
      return {
        'provider': 'tmdb',
        'results': [
          {'provider': 'tmdb', 'title': 'Dune Part Two', 'url': '', 'year': 2024, 'exact': false, 'externalIdKey': 'tmdb', 'externalIdValue': '693134'},
          {'provider': 'tmdb', 'title': 'Dune', 'url': 'https://image.tmdb.org/t/p/w500/a.jpg', 'year': 2021, 'exact': true, 'externalIdKey': 'tmdb', 'externalIdValue': '438631'},
          {'provider': 'omdb', 'title': 'Dune', 'url': 'https://m.media-amazon.com/x.jpg'},
        ],
      };
    };
    final r = await searchTmdb('Dune', kind: 'movie', externalIds: {'tmdb': '438631', 'bad key': 'x'});
    expect(sent.single['action'], 'search');
    expect(sent.single['provider'], 'tmdb');
    expect(sent.single['kind'], 'movie');
    expect(sent.single['loose'], true);
    expect(sent.single['externalIds'], {'tmdb': '438631'});
    expect(r.length, 2);
    expect(r.first.title, 'Dune');
    expect(r.first.source, 'TMDB');
    expect(r.first.coverUrl, 'https://image.tmdb.org/t/p/w500/a.jpg');
    expect(r.first.year, 2021);
    expect(r.last.subtitle, contains('similar title'));
  });

  test('retries once when the gateway asks to wait', () async {
    var calls = 0;
    providerGateway = (body) async {
      calls++;
      if (calls == 1) throw Exception('Please wait 1 seconds before requesting this source');
      return {'results': [{'provider': 'tmdb', 'title': 'Arcane', 'url': 'https://image.tmdb.org/t/p/w500/b.jpg', 'exact': true, 'externalIdKey': 'tmdb_tv'}]};
    };
    final r = await searchTmdb('Arcane');
    expect(calls, 2);
    expect(r.single.subtitle, 'TV');
  });

  test('no gateway (signed out) or a failure gives no results', () async {
    expect(await searchTmdb('Dune'), isEmpty);
    providerGateway = (body) async => throw Exception('Invalid account session');
    expect(await searchTmdb('Dune'), isEmpty);
  });
}
