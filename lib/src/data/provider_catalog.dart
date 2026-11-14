// The website's provider catalog (v433 / v438 / v440, `mf438Catalog()`) and
// Cover Recovery registry (`MF424_PROVIDER_META`), recorded from website v574.
// What actually works is decided by the app's adapters (metadata_search.dart)
// and the provider service; this list is what Sources shows.

/// (id, name, access, capabilities, media types). access: public, key,
/// restricted (needs approval), review (licensing review), skipped.
const kProviderCatalog = <({String id, String name, String access, String caps, String media})>[
  (id: 'anidb', name: 'AniDB', access: 'restricted', caps: 'cover/id/metadata', media: 'anime'),
  (id: 'anilist', name: 'AniList', access: 'public', caps: 'cover/id', media: 'anime/anime-movie/manga'),
  (id: 'animeschedule', name: 'AnimeSchedule', access: 'key', caps: 'cover/id/releases', media: 'anime'),
  (id: 'itunes', name: 'Apple iTunes Search', access: 'public', caps: 'cover/id/metadata/releases', media: 'music/album'),
  (id: 'bnf', name: 'BnF', access: 'public', caps: 'cover/id/metadata', media: 'book'),
  (id: 'boardgamegeek', name: 'BoardGameGeek', access: 'review', caps: 'cover/id/metadata', media: 'other'),
  (id: 'comicvine', name: 'Comic Vine', access: 'restricted', caps: 'cover/id/metadata/releases', media: 'comic'),
  (id: 'coverartarchive', name: 'Cover Art Archive', access: 'public', caps: 'cover/id', media: 'music'),
  (id: 'crossref', name: 'Crossref', access: 'public', caps: 'cover/id/metadata', media: 'book'),
  (id: 'deezer', name: 'Deezer', access: 'public', caps: 'cover/id/metadata', media: 'music'),
  (id: 'discogs', name: 'Discogs', access: 'key', caps: 'cover/id/metadata/rating', media: 'music'),
  (id: 'episodate', name: 'EpisoDate', access: 'public', caps: 'cover/id/releases', media: 'other'),
  (id: 'fanart', name: 'Fanart.tv', access: 'key', caps: 'cover/id', media: 'movie/tv'),
  (id: 'fribb', name: 'Fribb Anime Lists', access: 'public', caps: 'cover/id/mapping', media: 'anime'),
  (id: 'dnb', name: 'German National Library', access: 'public', caps: 'cover/id/metadata', media: 'book'),
  (id: 'giantbomb', name: 'Giant Bomb', access: 'key', caps: 'cover/id/metadata', media: 'game'),
  (id: 'gog', name: 'GOG', access: 'review', caps: 'cover/id/metadata', media: 'game'),
  (id: 'googlebooks', name: 'Google Books', access: 'skipped', caps: 'cover/id/metadata', media: 'book/comic/reading'),
  (id: 'gcd', name: 'Grand Comics Database', access: 'public', caps: 'cover/id/releases', media: 'other'),
  (id: 'gutendex', name: 'Gutendex', access: 'public', caps: 'cover/id/metadata', media: 'other'),
  (id: 'gutendex-public', name: 'Gutendex / Gutenberg Covers', access: 'public', caps: 'cover/id', media: 'book/comic/reading'),
  (id: 'hardcover', name: 'Hardcover', access: 'key', caps: 'cover/id/metadata', media: 'other'),
  (id: 'ifarchive', name: 'IF Archive', access: 'public', caps: 'id/metadata', media: 'interactive_fiction'),
  (id: 'ifwiki', name: 'IFWiki', access: 'public', caps: 'id/metadata', media: 'interactive_fiction'),
  (id: 'igdb', name: 'IGDB', access: 'key', caps: 'cover/id/metadata/rating', media: 'game'),
  (id: 'ifdb', name: 'Interactive Fiction Database', access: 'public', caps: 'cover/id/metadata/rating', media: 'interactive_fiction'),
  (id: 'inventaire', name: 'Inventaire.io', access: 'public', caps: 'cover/id/metadata', media: 'other'),
  (id: 'itch', name: 'itch.io', access: 'review', caps: 'cover/id/metadata', media: 'game/interactive_fiction/visual_novel'),
  (id: 'jikan', name: 'Jikan', access: 'public', caps: 'cover/id', media: 'anime/anime-movie/manga'),
  (id: 'kitsu', name: 'Kitsu', access: 'public', caps: 'cover/id', media: 'anime/anime-movie/manga'),
  (id: 'lastfm', name: 'Last.fm', access: 'key', caps: 'cover/id/metadata', media: 'music'),
  (id: 'loc', name: 'Library of Congress', access: 'public', caps: 'cover/id/metadata', media: 'book'),
  (id: 'livechart', name: 'LiveChart', access: 'review', caps: 'cover/id/releases', media: 'other'),
  (id: 'manami', name: 'manami-project', access: 'review', caps: 'cover/id/mapping', media: 'anime'),
  (id: 'mangadex', name: 'MangaDex', access: 'review', caps: 'cover/id/releases', media: 'manga'),
  (id: 'mangaupdates', name: 'MangaUpdates', access: 'review', caps: 'cover/id/releases', media: 'other'),
  (id: 'marvel', name: 'Marvel', access: 'restricted', caps: 'cover/id/metadata', media: 'comic'),
  (id: 'metron', name: 'Metron', access: 'key', caps: 'cover/id/metadata/releases', media: 'comic'),
  (id: 'mobygames', name: 'MobyGames', access: 'key', caps: 'cover/id/metadata', media: 'game'),
  (id: 'musicbrainz', name: 'MusicBrainz', access: 'public', caps: 'cover/id/metadata/releases', media: 'music/album'),
  (id: 'malofficial', name: 'MyAnimeList Official', access: 'restricted', caps: 'cover/id/metadata', media: 'anime/anime-movie/manga'),
  (id: 'omdb', name: 'OMDb', access: 'key', caps: 'cover/id/metadata', media: 'movie/tv'),
  (id: 'openlibrary', name: 'Open Library', access: 'public', caps: 'cover/id', media: 'book/comic/reading'),
  (id: 'opencritic', name: 'OpenCritic', access: 'review', caps: 'id/rating/metadata', media: 'game'),
  (id: 'rawg', name: 'RAWG', access: 'key', caps: 'cover/id/metadata/rating', media: 'game'),
  (id: 'royalroad', name: 'Royal Road RSS', access: 'public', caps: 'cover/id/releases', media: 'other'),
  (id: 'simkl', name: 'SIMKL', access: 'restricted', caps: 'cover/id/metadata/releases', media: 'anime/anime-movie/tv/movie'),
  (id: 'spotify', name: 'Spotify', access: 'key', caps: 'cover/id/metadata', media: 'music'),
  (id: 'steam', name: 'Steam Store', access: 'public', caps: 'cover/id/metadata/rating/releases', media: 'game/visual_novel'),
  (id: 'tenrai', name: 'Tenrai', access: 'public', caps: 'cover/id', media: 'anime/anime-movie/manga'),
  (id: 'thetvdb', name: 'TheTVDB', access: 'restricted', caps: 'cover/id/metadata/releases', media: 'tv'),
  (id: 'tmdb', name: 'TMDB', access: 'key', caps: 'cover/id/metadata', media: 'movie/tv'),
  (id: 'trakt', name: 'Trakt', access: 'key', caps: 'cover/id/metadata/releases', media: 'other'),
  (id: 'tvmaze', name: 'TVmaze', access: 'public', caps: 'cover/id', media: 'tv'),
  (id: 'vgmdb', name: 'VGMdb', access: 'review', caps: 'cover/id/metadata', media: 'music'),
  (id: 'vndb', name: 'VNDB', access: 'public', caps: 'cover/id/metadata/rating', media: 'visual_novel'),
  (id: 'vndb-api', name: 'VNDB Kana API', access: 'public', caps: 'id/metadata', media: 'visual_novel'),
  (id: 'watchmode', name: 'Watchmode', access: 'key', caps: 'cover/id/metadata/releases', media: 'movie/tv'),
  (id: 'wikidata', name: 'Wikidata', access: 'public', caps: 'cover/id/mapping', media: 'anime/manga/movie/tv/book/comic'),
  (id: 'wikimedia', name: 'Wikimedia Commons', access: 'public', caps: 'cover/id/metadata', media: 'other'),
  (id: 'youtube', name: 'YouTube Data API', access: 'key', caps: 'cover/id/releases', media: 'other'),
];

/// Cover Recovery's registry, in the website's order (`MF424_PROVIDER_META`).
const kCoverRegistry = <({String id, String name, bool websiteReady, bool credentials})>[
  (id: 'tenrai', name: 'Tenrai', websiteReady: true, credentials: false),
  (id: 'jikan', name: 'Jikan', websiteReady: true, credentials: false),
  (id: 'anilist', name: 'AniList', websiteReady: true, credentials: false),
  (id: 'kitsu', name: 'Kitsu', websiteReady: true, credentials: false),
  (id: 'tvmaze', name: 'TVmaze', websiteReady: true, credentials: false),
  (id: 'mangadex', name: 'MangaDex', websiteReady: false, credentials: false),
  (id: 'openlibrary', name: 'Open Library', websiteReady: true, credentials: false),
  (id: 'googlebooks', name: 'Google Books Cover Art', websiteReady: true, credentials: false),
  (id: 'simkl', name: 'SIMKL', websiteReady: false, credentials: true),
  (id: 'malofficial', name: 'MyAnimeList Official', websiteReady: false, credentials: true),
  (id: 'tmdb', name: 'TMDB', websiteReady: false, credentials: true),
  (id: 'omdb', name: 'OMDb', websiteReady: false, credentials: true),
  (id: 'thetvdb', name: 'TheTVDB', websiteReady: false, credentials: true),
  (id: 'fanart', name: 'Fanart.tv', websiteReady: false, credentials: true),
  (id: 'comicvine', name: 'Comic Vine', websiteReady: false, credentials: true),
  (id: 'metron', name: 'Metron', websiteReady: false, credentials: true),
  (id: 'anidb', name: 'AniDB', websiteReady: false, credentials: true),
  (id: 'animeschedule', name: 'AnimeSchedule', websiteReady: false, credentials: false),
  (id: 'watchmode', name: 'Watchmode', websiteReady: false, credentials: true),
  (id: 'marvel', name: 'Marvel API', websiteReady: false, credentials: true),
  (id: 'wikidata', name: 'Wikidata', websiteReady: true, credentials: false),
  (id: 'fribb', name: 'Fribb', websiteReady: false, credentials: false),
  (id: 'manami', name: 'manami-project', websiteReady: false, credentials: false),
  (id: 'loc', name: 'Library of Congress', websiteReady: true, credentials: false),
  (id: 'dnb', name: 'German National Library', websiteReady: false, credentials: false),
  (id: 'bnf', name: 'BnF', websiteReady: false, credentials: false),
  (id: 'crossref', name: 'Crossref', websiteReady: false, credentials: false),
  (id: 'trakt', name: 'Trakt', websiteReady: false, credentials: true),
  (id: 'hardcover', name: 'Hardcover', websiteReady: false, credentials: true),
  (id: 'inventaire', name: 'Inventaire.io', websiteReady: true, credentials: false),
  (id: 'gutendex', name: 'Gutendex', websiteReady: false, credentials: false),
  (id: 'episodate', name: 'EpisoDate', websiteReady: true, credentials: false),
  (id: 'mangaupdates', name: 'MangaUpdates', websiteReady: false, credentials: false),
  (id: 'gcd', name: 'Grand Comics Database', websiteReady: false, credentials: false),
  (id: 'royalroad', name: 'Royal Road RSS', websiteReady: false, credentials: false),
  (id: 'youtube', name: 'YouTube Data API', websiteReady: false, credentials: true),
  (id: 'livechart', name: 'LiveChart', websiteReady: false, credentials: false),
  (id: 'steam', name: 'Steam Store Artwork', websiteReady: true, credentials: false),
  (id: 'itunes', name: 'Apple iTunes Album Art', websiteReady: true, credentials: false),
  (id: 'musicbrainz', name: 'MusicBrainz / Cover Art Archive', websiteReady: true, credentials: false),
  (id: 'vndb', name: 'VNDB Visual Novel Covers', websiteReady: true, credentials: false),
  (id: 'ifdb', name: 'IFDB Interactive Fiction Covers', websiteReady: true, credentials: false),
  (id: 'gutendex-public', name: 'Gutendex / Gutenberg Covers', websiteReady: true, credentials: false),
  // 9.0.0 (website v577): keyless, checked live.
  (id: 'wikimedia', name: 'Wikimedia Commons', websiteReady: true, credentials: false),
  (id: 'deezer', name: 'Deezer (app only)', websiteReady: false, credentials: false),
];

/// Cover sources the app calls directly (no key needed).
const kAppCoverAdapters = {
  'tenrai', 'jikan', 'anilist', 'kitsu', 'tvmaze', 'openlibrary', 'mangadex',
  'steam', 'itunes', 'musicbrainz', 'vndb', 'ifdb', 'gutendex-public', 'googlebooks',
  // 9.0.0 (website v577): every keyless cover source.
  'wikidata', 'wikimedia', 'loc', 'inventaire', 'episodate', 'deezer',
};

/// 9.0.0: keyless sources that can't be used, and why (checked live).
const kBlockedSources = {
  'boardgamegeek': 'Now needs a registered key',
  'mangaupdates': 'Blocks automated requests',
  'royalroad': 'No search API; blocks automated requests',
  'gog': 'Its public search no longer returns results',
};

/// Cover sources reached through MediaFlow's provider service (keys stay on
/// the server); they work once their key is set up there.
const kServiceCoverSources = {'tmdb', 'omdb', 'fanart', 'animeschedule', 'malofficial', 'gutendex'};

/// What a provider can do in the app right now, in a few words.
({bool works, String text}) providerStatus(String id, {bool cover = false, Set<String> serviceReady = const {}, bool serviceChecked = false}) {
  if (kAppCoverAdapters.contains(id) && (cover || !kServiceCoverSources.contains(id))) {
    return (works: true, text: 'Public · ready');
  }
  if (kServiceCoverSources.contains(id)) {
    if (!serviceChecked) return (works: true, text: 'Provider service · used when its key is set up');
    return serviceReady.contains(id)
        ? (works: true, text: 'Provider service · ready')
        : (works: false, text: 'Provider service · API key not set up yet');
  }
  // 9.0.0: the keyless detail sources work directly; some can't be used.
  if (const ['wikidata', 'loc', 'crossref', 'inventaire', 'episodate', 'dnb', 'bnf', 'gcd', 'deezer'].contains(id)) {
    return (works: true, text: id == 'gcd' || id == 'deezer' ? 'Public · ready (in the app; the website can\'t reach it)' : 'Public · ready');
  }
  if (kBlockedSources[id] case final why?) return (works: false, text: '$why · not connected (same as the website)');
  final access = kProviderCatalog.where((p) => p.id == id).firstOrNull?.access ?? '';
  return (
    works: false,
    text: switch (access) {
      'key' => 'Needs an API key · no connection yet (same as the website)',
      'restricted' => 'Needs approval from the provider · no connection yet (same as the website)',
      'review' => 'Licensing review · no connection yet (same as the website)',
      'skipped' => 'Not connected (same as the website)',
      _ => 'No connection yet (same as the website)',
    },
  );
}

/// What `mf453SavePreset(category, mode, providers)` writes to
/// `settings.v453RecoveryPresets` (null providers = use the global list).
/// [registered]: the providers that mode accepts.
Map<String, dynamic> presetToSave(Map<String, dynamic>? settings, String categoryId, String mode, List<String>? providers, Iterable<String> registered) {
  final preset = <String, dynamic>{...?(settings?['v453RecoveryPresets'] as Map?)?.cast<String, dynamic>()};
  final row = <String, dynamic>{...?(preset[categoryId] as Map?)?.cast<String, dynamic>()};
  if (providers == null) {
    row.remove(mode);
  } else {
    final ok = registered.toSet();
    row[mode] = [...{...providers.where(ok.contains)}];
  }
  if (row.isNotEmpty) {
    preset[categoryId] = row;
  } else {
    preset.remove(categoryId);
  }
  return preset;
}

/// The cover sources Sources can turn on, in the website's order.
List<String> get coverRegistryIds => [for (final p in kCoverRegistry) p.id];
