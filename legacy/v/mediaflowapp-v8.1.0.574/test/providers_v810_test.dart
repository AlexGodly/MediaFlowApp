// 8.1.0.574: every API of the website in the app (Sources), the website's
// v440 cover sources, and cover presets per category (shared with the website).

import 'package:flutter_test/flutter_test.dart';
import 'package:mediaflow/src/data/metadata_search.dart';
import 'package:mediaflow/src/data/provider_catalog.dart';
import 'package:mediaflow/src/logic/ratings_engine.dart' show kAvailableSources;
import 'package:mediaflow/src/logic/recovery.dart' show coverProviderId;

void main() {
  test('the website\'s whole catalog and cover registry', () {
    expect(kProviderCatalog.length, 61);
    expect(kCoverRegistry.length, 43);
    expect(kProviderCatalog.map((p) => p.id), containsAll(['tenrai', 'igdb', 'spotify', 'wikidata', 'vndb', 'steam']));
    // Every cover source the website can use works in the app.
    for (final p in kCoverRegistry.where((p) => p.websiteReady)) {
      expect(providerStatus(p.id, cover: true).works, isTrue, reason: p.id);
    }
    expect(providerStatus('igdb').works, isFalse);
    expect(providerStatus('tmdb', cover: true, serviceChecked: true, serviceReady: {'tmdb'}).works, isTrue);
    expect(providerStatus('omdb', cover: true, serviceChecked: true).works, isFalse);
    expect(kAvailableSources.length, 19, reason: 'details & ratings sources, as on the website');
  });

  test('cover sources: global list, category preset, and what a preset may hold', () {
    expect(enabledCoverSources(null), containsAll(['tenrai', 'steam', 'itunes', 'musicbrainz', 'vndb', 'ifdb', 'gutendex-public', 'googlebooks']));
    final settings = <String, dynamic>{
      'v424Covers': {'enabled': ['tenrai', 'anilist']},
      'v453RecoveryPresets': {
        'games': {'cover': ['steam', 'vndb'], 'metadata': ['steam']},
      },
    };
    expect(coverSourcesFor(settings, 'anime'), {'tenrai', 'anilist'});
    expect(coverSourcesFor(settings, 'games'), {'steam', 'vndb'});
    expect(hasCoverPreset(settings, 'games'), isTrue);
    expect(hasCoverPreset(settings, 'anime'), isFalse);

    final saved = presetToSave(settings, 'games', 'cover', ['steam', 'not-a-source', 'ifdb'], coverRegistryIds);
    expect((saved['games'] as Map)['cover'], ['steam', 'ifdb']);
    expect((saved['games'] as Map)['metadata'], ['steam'], reason: 'the details preset is kept');
    final cleared = presetToSave({'v453RecoveryPresets': saved}, 'games', 'cover', null, coverRegistryIds);
    expect((cleared['games'] as Map).containsKey('cover'), isFalse);
    final gone = presetToSave({'v453RecoveryPresets': {'x': {'cover': ['steam']}}}, 'x', 'cover', null, coverRegistryIds);
    expect(gone.containsKey('x'), isFalse);
  });

  test('saved IDs for the new cover sources (website mf440Id)', () {
    final ids = {
      'steam_app': '620',
      'apple_music_album': '1440650428',
      'musicbrainz_release_group': '1dc4c347-a1db-32aa-b14f-bc9cc507b843',
      'vndb': 'v17',
      'ifdb': '0dbnusxunq7fw5ro',
      'gutendex': '84',
      'googlebooks': 'zyTCAlFPjgYC',
    };
    for (final p in kExtraCoverIdKeys.keys) {
      expect(savedExtraCoverId(ids, p), isNotEmpty, reason: p);
    }
    expect(savedExtraCoverId({'steam_app': 'abc'}, 'steam'), '');
    expect(savedExtraCoverId({'vndb': '17'}, 'vndb'), '');
    expect(savedExtraCoverId({'musicbrainz_release_group': 'nope'}, 'musicbrainz'), '');
  });

  test('result sources map to the website\'s provider ids', () {
    expect(coverProviderId('Steam'), 'steam');
    expect(coverProviderId('iTunes'), 'itunes');
    expect(coverProviderId('MusicBrainz'), 'musicbrainz');
    expect(coverProviderId('VNDB'), 'vndb');
    expect(coverProviderId('IFDB'), 'ifdb');
    expect(coverProviderId('Gutenberg'), 'gutendex-public');
    expect(coverProviderId('Google Books'), 'googlebooks');
    expect(coverProviderId('Tenrai'), 'tenrai');
  });

  test('the editor\'s online search adds the sources that fit a category', () {
    expect(extraCoverSourcesForCategory(name: 'Games', unit: 'matches'), contains('steam'));
    expect(extraCoverSourcesForCategory(name: 'Music', unit: 'albums'), containsAll(['itunes', 'musicbrainz']));
    expect(extraCoverSourcesForCategory(name: 'Novels', unit: 'chapters', type: 'reading'), containsAll(['gutendex-public', 'googlebooks']));
    expect(extraCoverSourcesForCategory(name: 'Seasonal Anime', unit: 'episodes', type: 'video'), isEmpty);
  });
}
