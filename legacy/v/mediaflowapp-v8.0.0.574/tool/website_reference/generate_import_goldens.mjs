// Golden fixtures for imports from other services (website Exchange Hub, v158
// metadata engine and its v176 / v178 / v252 / v295 / v377 / v378 wrappers,
// Simkl History). Runs the website's own functions, taken from its source
// files, and records what they write, for test/exchange_import_golden_test.dart.
//
//   TZ=UTC node tool/website_reference/generate_import_goldens.mjs <path to MediaFlow repo>
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const site = process.argv[2] || '../MediaFlow';
const read = (rel) => fs.readFileSync(path.join(site, 'src/js', rel), 'utf8');

/** The statement that starts at [marker] in [rel] (the shortest piece that compiles). */
function take(rel, marker, from = 0) {
  const src = read(rel);
  const start = src.indexOf(marker, from);
  if (start < 0) throw new Error(`${marker} not found in ${rel}`);
  for (let i = start; i < src.length; i++) {
    const ch = src[i];
    if (ch !== '}' && ch !== ';' && ch !== '\n') continue;
    const piece = src.slice(start, i + 1);
    try {
      new vm.Script(piece);
      // A function body must be closed (not just "function x(){" on one line).
      if (/^\s*(async\s+)?function\b/.test(piece) && ch !== '}') continue;
      return piece;
    } catch (_) {}
  }
  throw new Error(`could not cut ${marker} from ${rel}`);
}

const files = {
  legacy: 'legacy/025-v40-multi-service-exchange-hub-custom-import-confirmation.js',
  v158: 'components/cover/061-v158-complete-import-metadata-safe-cover-repair.js',
  v176: 'pages/library/085-v176-dense-library-rows-rich-imported-metadata.js',
  v178: 'legacy/093-v178-editable-rich-imported-metadata.js',
  p095: 'legacy/095-protect-manually-edited-fields-from-future-imports.js',
  v252: 'components/186-v252-seasons-view.js',
  v295: 'components/226-v295-default-categories-responsive-data-audit.js',
  v377: 'components/273-v377-ids-editor-jikan-recovery.js',
  v378: 'components/274-v378-tenrai-import-logging-order.js',
  v135: 'pages/statistics/032-v44-stopwatch-add-time-ratings-covers-xp-timeline.js',
};
const util = read('utils/006-util.js');
const ct = util.indexOf('function cleanTitle(');

const parts = [
  util.slice(ct, util.indexOf('\n}', ct) + 2),
  take(files.v135, 'function v135ParseDateInput('),
  read(files.legacy),
  // v158: the engine (everything up to the file import UI) and Simkl import.
  ...[
    'const V158_IMPORT_VERSION', 'function v158SafeHttpUrl(', 'function v158ParseDateLike(', 'function v158FirstDate(',
    'function v158NestedObjects(', 'function v158UrlFromImageValue(', 'function v158ExtractCoverUrl(',
    'function v158NormalizeExternalIds(', 'function v158NormalizeStatus(', 'function v158NormalizedTitleKey(',
    'function v158InferCategory(', 'function v158SimklEpisodeBounds(', 'function v158NormalizeRecord(',
    'mfNormalizeRecord=v158NormalizeRecord;', 'function v158ImportIndex(', 'function v158FindImportItem(',
    'function v158CategoryFallback(', 'function v158ImportedStartSource(', 'function v158ApplyNormalizedRecord(',
    'function v158SyncCompletionTimeline(', 'async function v158MergeExchangeRecords(',
    'function v158FindLibraryForSimklRecord(', 'App.importSimklJson=async function', 'mfExchangeRows=function(){',
  ].map((m) => take(files.v158, m)),
  // v176 rich metadata.
  ...[
    'const V176_RICH_FIELDS', 'function v176SafeText(', 'function v176SourceObjects(', 'function v176Key(', 'function v176FindValue(',
    'function v176List(', 'function v176DurationMinutes(', 'function v176DateValue(', 'function v176CommunityScore(',
    'function v176ExtractRichMetadata(', 'function v176HasRichMetadata(', 'const v176NormalizeRecordBase', 'v158NormalizeRecord=function',
    'function v176MergeListValues(', 'function v176ApplyRichMetadata(', 'const v176ApplyNormalizedRecordBase', 'v158ApplyNormalizedRecord=function',
  ].map((m) => take(files.v176, m)),
  // v178 manual fields and the 095 protection.
  take(files.v178, 'const V178_EDITABLE_RICH_FIELDS'),
  take(files.v178, 'function v178ManualMap('),
  take(files.p095, 'v176ApplyRichMetadata=function'),
  take(files.p095, 'const v178ApplyNormalizedRecordBase'),
  take(files.p095, 'v158ApplyNormalizedRecord=function'),
  // v252 seasons.
  ...[
    'function v252SeasonUid(', 'function v252Num(', 'function v252SeasonNumberValue(', 'function v252SeasonLabel(',
    'function v252NormalizeSeason(', 'function v252SortSeasons(', 'function v252NormalizeSeasons(', 'function v252Seasons(',
    'function v252HasSeasons(', 'function v252SeasonAggregate(', 'function v252SyncTitleFromSeasons(',
    'function v252ReconcileImportedAggregate(', 'function v252FirstNumber(', 'function v252SeasonFromImport(',
    'function v252ExtractImportedSeasons(', 'function v252MergeImportedSeasons(', 'const v252NormalizeRecordBase',
    'v158NormalizeRecord=function', 'const v252ApplyNormalizedRecordBase', 'v158ApplyNormalizedRecord=function',
    'const v252ExchangeRowsBase', 'mfExchangeRows=function',
  ].map((m) => take(files.v252, m)),
  // v295 category fallbacks.
  take(files.v295, "if(typeof mfGuessCategory==='function')"),
  take(files.v295, "if(typeof v158InferCategory==='function')"),
  // v377 manual ID overrides, v378 ID normalization.
  take(files.v377, 'const v377ApplyImportedBase'),
  take(files.v377, 'v158ApplyNormalizedRecord=function'),
  take(files.v378, 'const V378_ID_ALIASES'),
  take(files.v378, 'function v378NormalizeId('),
  take(files.v378, 'function v378ExtractIds('),
  take(files.v378, 'const v378ImportNormBase'),
  take(files.v378, 'v158NormalizeExternalIds=function'),
  take(files.v378, 'const v378ApplyNormBase'),
  take(files.v378, 'let V378_IMPORT_STATS'),
  take(files.v378, 'v158ApplyNormalizedRecord=function'),
];

const NOW = Date.UTC(2026, 10, 12, 10, 0, 0);
let seq = 0;
const ctx = {
  console, JSON, Math, Number, String, Object, Array, Set, Map, RegExp, URL, Promise, isFinite, parseInt,
  Date: class extends Date {
    constructor(...a) { super(...(a.length ? a : [NOW])); }
    static now() { return NOW; }
  },
  window: {}, App: {}, S: {},
  uid: () => `id_${++seq}`,
  yieldToBrowser: async () => {}, normalizeSeasonalLibraryItems: () => false, v53InvalidateLibraryCache() {}, v53InvalidateSessionCache() {},
  showImportProgress() {}, updateImportProgress() {}, finishImportProgress() {}, mfBegin() {}, mfCommit() {}, saveState: async () => true,
  render() {}, mfRestoreCore() {},
  getCategory: (id) => (ctx.S.categories || []).find((c) => c.id === id),
  v135DateInputValue: (ts) => { ts = Number(ts) || 0; if (!ts) return ''; const d = new Date(ts); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; },
};
ctx.Date.parse = Date.parse;
ctx.Date.UTC = Date.UTC;
vm.createContext(ctx);
vm.runInContext(parts.join('\n;\n'), ctx);

const categories = [
  { id: 'seasonal', name: 'Seasonal Anime', unit: 'episodes', minutesPerUnit: 24 },
  { id: 'backlog', name: 'Anime', unit: 'episodes', minutesPerUnit: 24 },
  { id: 'animemovies', name: 'Anime Movies', unit: 'movies', minutesPerUnit: 110 },
  { id: 'manga', name: 'Manga', unit: 'chapters', minutesPerUnit: 6 },
  { id: 'tv', name: 'TV', unit: 'episodes', minutesPerUnit: 45 },
  { id: 'movies', name: 'Movies', unit: 'movies', minutesPerUnit: 120 },
  { id: 'books', name: 'Books', unit: 'pages', minutesPerUnit: 2, enabled: false },
];
const library = [
  { id: 'lib_frieren', title: 'Frieren', categoryId: 'backlog', progress: 3, total: 28, status: 'active', externalIds: { mal: '52991' }, year: 2023, createdAt: 1700000000000 },
  { id: 'lib_dune', title: 'Dune', categoryId: 'movies', progress: 0, total: 1, status: 'planned', year: 2021, coverUrl: 'https://img/dune.jpg', createdAt: 1700000000000 },
  { id: 'lib_manual', title: 'Bocchi the Rock!', categoryId: 'backlog', progress: 1, status: 'active', year: 2022, externalIds: { mal: '47917', anilist: '130003' },
    richMetadataManual: { year: true, genres: true }, genres: ['Mine'], v377ManualExternalIds: { kitsu: '' }, createdAt: 1700000000000 },
  { id: 'lib_bb', title: 'Breaking Bad', categoryId: 'tv', progress: 10, status: 'active', createdAt: 1700000000000 },
];

const malXmlRecords = [
  { series_animedb_id: '52991', series_title: 'Sousou no Frieren', series_type: 'TV', series_episodes: '28', my_watched_episodes: '28', my_start_date: '2023-09-29',
    my_finish_date: '2024-03-22', my_score: '10', my_status: 'Completed', my_last_updated: '1711100000' },
  { series_animedb_id: '47917', series_title: 'Bocchi the Rock!', series_type: 'TV', series_episodes: '12', my_watched_episodes: '12', my_status: 'Completed',
    my_start_date: '0000-00-00', my_finish_date: '2023-01-01', series_image: 'https://cdn.myanimelist.net/images/anime/1448/127956.jpg' },
  { series_animedb_id: '0', series_title: 'Some Movie', series_type: 'Movie', series_episodes: '1', my_watched_episodes: '0', my_status: 'Plan to Watch' },
  { series_title: '' },
  { manga_mangadb_id: '2', manga_title: 'Berserk', manga_chapters: '0', my_read_chapters: '364', my_status: 'Reading', manga_type: 'Manhwa' },
];
const csvText = 'Title,Media Type,Status,Progress,Total,Rating,Year,IMDb ID,Genres,Runtime,Poster\n'
  + 'Dune,movie,completed,1,1,9,2021,https://www.imdb.com/title/tt1160419/,"Sci-Fi, Adventure",155 min,//image.tmdb.org/t/p/w500/d.jpg\n'
  + '"Breaking Bad",show,watching,30,62,,2008,tt0903747,Drama,47,\n'
  + 'New Show,tv,plan to watch,,,,,,,,\n';
const jsonData = {
  items: [
    { title: 'Arcane', type: 'show', status: 'completed', progress: 9, total: 9, year: 2021, ids: { tmdb: 94605, imdb: 'tt11126994' },
      seasons: [{ season: 1, episodes: 9, watched: 9 }, { season: 2, episodes: 9, watched: 0 }], overview: '<p>Two sisters.</p>', genres: [{ name: 'Animation' }, { name: 'Drama' }],
      added_at: '2021-11-07T12:00:00Z', finished_at: '2021-11-21T20:00:00Z', poster: { large: 'https://img/arcane.jpg' } },
    { name: 'Breaking Bad', kind: 'tv', status: 'on hold', progress: 12, community_score: 95, network: 'AMC' },
  ],
};
const simklData = {
  anime: [{ show: { title: 'Sousou no Frieren', year: 2023, ids: { simkl: 2099, mal: 52991 } }, status: 'completed', watched_episodes_count: 28, total_episodes_count: 28,
    seasons: [{ number: 1, episodes: [{ number: 1, watched_at: '2023-09-29T15:00:00Z' }, { number: 2, watched_at: '2023-09-29T15:30:00Z' }, { number: 3, watched_at: '2023-10-06T15:00:00Z' }] }],
    last_watched_at: '2024-03-22T15:00:00Z' }],
  shows: [{ show: { title: 'Breaking Bad', year: 2008, runtime: 47, ids: { simkl: 11, imdb: 'tt0903747' } }, status: 'watching', watched_episodes_count: 30,
    seasons: [{ number: 1, episodes: [{ number: 1, watched_at: '2020-01-02T10:00:00Z' }] }] }],
  movies: [{ movie: { title: 'Dune', year: 2021, ids: { simkl: 5, imdb: 'tt1160419' } }, status: 'completed', last_watched_at: '2022-01-01T20:00:00Z' }],
};

function fresh() {
  seq = 0;
  ctx.S = { categories: JSON.parse(JSON.stringify(categories)), library: JSON.parse(JSON.stringify(library)), completionTimeline: [], sessions: [] };
}
async function merge(name, service, records, extra = {}) {
  fresh();
  const r = await vm.runInContext('v158MergeExchangeRecords', ctx)(records, service, {});
  return { name, service, records, ...extra, result: { added: r.added, updated: r.updated, skipped: r.skipped, covers: r.covers, startDates: r.startDates, finishDates: r.finishDates, timestamps: r.timestamps },
    library: ctx.S.library, completionTimeline: ctx.S.completionTimeline };
}

const cases = [];
cases.push(await merge('mal-xml', 'malxml', malXmlRecords));
const csvRecords = vm.runInContext('mfCsvParse', ctx)(csvText);
cases.push(await merge('csv', 'csv', csvRecords, { csv: csvText }));
const jsonRecords = vm.runInContext('mfFlattenJson', ctx)(jsonData);
cases.push(await merge('json-trakt', 'trakt', jsonRecords, { json: jsonData }));
// Simkl: the whole App.importSimklJson (titles + watched History).
fresh();
await ctx.App.importSimklJson({ name: 'simkl.json', text: async () => JSON.stringify(simklData) });
cases.push({ name: 'simkl', service: 'simkl', simkl: simklData, library: ctx.S.library, completionTimeline: ctx.S.completionTimeline, sessions: ctx.S.sessions });

fresh();
const rows = vm.runInContext('mfExchangeRows', ctx)();

fs.writeFileSync('test/fixtures/import-golden.json', JSON.stringify({ now: NOW, categories, library, cases, exchangeRows: rows }, null, 1) + '\n');
console.log(`wrote test/fixtures/import-golden.json (${cases.length} imports)`);
