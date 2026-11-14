// 9.0.0 (website v577): the keyless sources read the answers the real
// services give (shapes recorded live with tool/live_sources.py on GitHub).

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/metadata_search.dart';
import 'package:mediaflow/src/data/provider_catalog.dart';
import 'package:mediaflow/src/logic/ratings_engine.dart';

void main() {
  Future<Object?> Function(String) fake(Map<Pattern, Object?> answers) => (url) async {
        for (final e in answers.entries) {
          if (url.contains(e.key)) return e.value;
        }
        return null;
      };

  test('Wikidata: search, then the entities, the image from Commons', () async {
    final rows = await keylessWikidata('Dune', fake({
      'wbsearchentities': {'search': [{'id': 'Q190192', 'label': 'Dune'}]},
      'wbgetentities': {
        'entities': {
          'Q190192': {
            'id': 'Q190192',
            'labels': {'en': {'value': 'Dune'}},
            'descriptions': {'en': {'value': '1965 novel'}},
            'claims': {
              'P18': [{'mainsnak': {'datavalue': {'value': 'Dune cover.jpg'}}}],
              'P577': [{'mainsnak': {'datavalue': {'value': {'time': '+1965-08-01T00:00:00Z'}}}}],
            },
          },
        },
      },
    }));
    expect(rows.single['id'], 'Q190192');
    expect(rows.single['year'], 1965);
    expect(commonsImage(rows.single['image']), 'https://commons.wikimedia.org/wiki/Special:FilePath/Dune_cover.jpg?width=600');
  });

  test('Inventaire, Library of Congress and EpisoDate', () async {
    final inv = await keylessInventaire('Dune', fake({
      'inventaire.io': {'results': [{'uri': 'wd:Q190192', 'label': 'Dune', 'description': '1965 science fiction novel', 'image': '/img/entities/a936'}]},
    }));
    expect(inv.single['id'], 'Q190192');
    expect(inv.single['image'], 'https://inventaire.io/img/entities/a936');
    final loc = await keylessLoc('Frankenstein', fake({
      'loc.gov': {'results': [{'id': 'http://www.loc.gov/item/2001234567/', 'title': 'Frankenstein', 'date': '1818', 'image_url': ['//tile.loc.gov/x.jpg#h=150']}]},
    }));
    expect(loc.single['id'], '2001234567');
    expect(loc.single['image'], 'https://tile.loc.gov/x.jpg');
    final ep = await keylessEpisodate('Breaking Bad', fake({
      'episodate.com': {'tv_shows': [{'id': 17658, 'name': 'Breaking Bad', 'permalink': 'breaking-bad', 'start_date': '2008-01-20',
        'image_thumbnail_path': 'https://static.episodate.com/images/tv-show/thumbnail/17658.jpg'}]},
    }));
    expect(ep.single['id'], 'breaking-bad');
    expect(ep.single['image'], 'https://static.episodate.com/images/tv-show/full/17658.jpg');
  });

  test('every keyless source is listed and usable; blocked ones say why', () {
    for (final id in kKeylessCoverSources) {
      expect(providerStatus(id, cover: true).works, isTrue, reason: id);
    }
    for (final id in kKeylessDetailSources) {
      expect(providerStatus(id).works, isTrue, reason: id);
      expect(kAvailableSources, contains(id));
    }
    expect(providerStatus('boardgamegeek').works, isFalse);
    expect(providerStatus('boardgamegeek').text, contains('key'));
  });
}
