# MediaFlow 8.1.0.574

Every API of the website in the app. Matches the MediaFlow website v574.

## Sources
- **Every API** (Recovery → Sources): the website's whole list of 61 APIs, with what each one does in MediaFlow today: covers, details & ratings, or why it isn't connected yet (an API key, the provider's approval or a licensing review, the same as on the website).
- **Cover sources:** all 43 cover sources of the website, turned on or off here or on the website (shared). Tenrai, Jikan, AniList, Kitsu, TVmaze, Open Library, MangaDex and the new ones below work right away; TMDB, OMDb, Fanart.tv, AnimeSchedule, MyAnimeList Official, EpisoDate and Gutendex work through MediaFlow's provider service once their key is set up.
- **Category presets for covers:** pick which cover sources each category uses, next to its details sources (shared with the website's Recovery Presets). Select available, Deselect all, or back to the global list.
- Tenrai and Jikan now follow their own switches (before, turning either on used both).

## New cover sources
- **Steam** (games, visual novels), **Apple iTunes albums**, **MusicBrainz / Cover Art Archive** (music), **VNDB** (visual novels; explicit images left out), **IFDB** (interactive fiction), **Project Gutenberg** (books) and **Google Books**, as on the website (v440). A saved ID for one of them is looked up first.
- They're used by Cover Recovery (when turned on), by the title editor's online search for categories they fit, and can be tested in Settings → API Providers & Testing.
