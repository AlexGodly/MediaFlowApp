// Generates test/fixtures/ratings-golden.json from the website's own v555
// ratings engine (src/js/components/396-v555-ratings-engine.js) and the v437 /
// v439 / v377 helpers it uses. Each scenario gives a Library title, its
// category, the rating sources and what each source answers (stubbed network);
// the fixture records the order of the source calls, what the engine accepted
// and discovered, and the title exactly as the website saves it afterwards.
// The app's port (lib/src/logic/ratings_engine.dart) must match it.
//
//   node tool/website_reference/generate_ratings_goldens.mjs <website checkout>
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const site = process.argv[2];
if (!site) { console.error('usage: generate_ratings_goldens.mjs <MediaFlow website checkout>'); process.exit(2); }
const dir = path.join(site, 'src/js/components');
const read = f => fs.readFileSync(path.join(dir, f), 'utf8');
const files = Object.fromEntries(fs.readdirSync(dir).filter(f => f.endsWith('.js')).map(f => [f, read(f)]));
const findFile = needle => Object.keys(files).find(f => files[f].includes(needle)) || (() => { throw Error('not found: ' + needle); })();

// A statement starting at `start`, ending where its brackets balance (strings skipped).
function block(src, start) {
  let depth = 0, i = start, q = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (q) { if (c === '\\') { i++; continue; } if (c === q) q = null; continue; }
    if (c === '"' || c === "'" || c === '`') { q = c; continue; }
    if ('([{'.includes(c)) depth++;
    else if (')]}'.includes(c)) depth--;
    else if ((c === ';' || c === '\n') && depth === 0) break;
  }
  if (src[i] === ';') i++;
  return src.slice(start, i);
}
function fn(name) {
  const f = findFile('function ' + name + '(');
  const src = files[f];
  const at = src.search(new RegExp('(?:async )?function ' + name + '\\('));
  // Function bodies: count braces only from the first '{'.
  let p = src.indexOf('(', at), pd = 0;
  for (; p < src.length; p++) { if (src[p] === '(') pd++; else if (src[p] === ')') { pd--; if (pd === 0) break; } }
  let i = src.indexOf('{', p), depth = 0, q = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (q) { if (c === '\\') { i++; continue; } if (c === q) q = null; continue; }
    if (c === '/' && src[i + 1] === '/' && src[i - 1] !== '\\' && src[i - 1] !== ':') { i = src.indexOf('\n', i); continue; }
    if (c === '/' && src[i + 1] === '*') { i = src.indexOf('*/', i) + 1; continue; }
    if (c === '"' || c === "'" || c === '`') { q = c; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) { i++; break; } }
  }
  return src.slice(at, i) + '\n';
}
function cnst(name) {
  const re = new RegExp('const ' + name + '=');
  const f = Object.keys(files).find(k => re.test(files[k]));
  if (!f) throw Error('const not found: ' + name);
  const src = files[f];
  return block(src, src.search(re)) + '\n';
}

const code = [
  cnst('V377_ID_PROVIDERS'), cnst('MF437_RATING_SOURCES'), cnst('MF437_ADDITIONAL_IDS'),
  "for(const [key,label] of MF437_ADDITIONAL_IDS){if(!V377_ID_PROVIDERS.some(row=>row[0]===key))V377_ID_PROVIDERS.push([key,label,'Optional verified provider ID']);}",
  cnst('MF437_SCHEMA_VERSION'), cnst('MF437_MEDIA_TYPES'), cnst('MF437_RATING_MAP'),
  'const MF437_FIELD_MAP=new Map();const MF439_LEGACY_FIELDS={};',
  cnst('mf437Object'), cnst('mf437Copy'),
  fn('mf437Normalized'), fn('mf437Clean'), fn('mf437FieldCompare'), fn('mf437SetRating'),
  cnst('mf439Plain'), fn('mf439TitleVariants'), fn('mf439Norm'), fn('mf439Year'),
  fn('mf439FieldDefinition'), fn('mf439IsProtected'), fn('mf439Value'),
  'const MF555R={gatewayLast:new Map(),wikiLast:0,wikiCache:new Map(),stats:{titles:0,ratingsWritten:0,idsWritten:0,byId:0,byName:0,byWikidata:0,parentShow:0,lastLog:[]}};',
  cnst('MF555R_ID_LOOKUP'), cnst('MF555R_PRIMARY'), cnst('MF555R_RECORD_KEYS'),
  cnst('mf555rNorm'), fn('mf555rIsMovie'), fn('mf555rIsSeries'), fn('mf555rBaseShowName'),
  fn('mf555rRowYear'), fn('mf555rRowType'), fn('mf555rIdsConflict'), fn('mf555rIdMatch'), fn('mf555rQuery'),
  fn('mf555RatingsForTitle'), fn('mf555ApplyRatings'),
  // Stubs: the network and the category.
  'let CATEGORY={};function getCategory(){return CATEGORY;}',
  'let CALLS=[],ANSWERS={},WIKI=null;',
  'async function mf555rLookup(provider,query){CALLS.push([provider,query.title,query.externalIds]);',
  '  const key=provider+"|"+query.title+"|"+JSON.stringify(Object.fromEntries(Object.entries(query.externalIds).sort()));',
  '  const a=ANSWERS[key];if(a&&a.error)throw new Error(a.error);return JSON.parse(JSON.stringify(a||[]));}',
  'async function mf555rWikidata(ids){CALLS.push(["wikidata","",JSON.parse(JSON.stringify(ids))]);return WIKI;}',
  'globalThis.api={run:async(sc)=>{CATEGORY=sc.category;CALLS=[];ANSWERS=sc.answers||{};WIKI=sc.wiki||null;',
  '  const item=JSON.parse(JSON.stringify(sc.item));',
  '  const found=await mf555RatingsForTitle(item,{providers:sc.providers});',
  '  const realNow=Date.now;Date.now=()=>sc.now;let written;try{written=mf555ApplyRatings(item,found);}finally{Date.now=realNow;}',
  '  return {calls:CALLS,accepted:found.accepted.map(r=>[r.provider,String(r.recordId),r.mf555Via]),',
  '   discovered:Object.fromEntries(Object.entries(found.discovered).map(([k,d])=>[k,{value:d.value,via:d.via,conflict:!!d.conflict}])),',
  '   failures:found.failures.map(f=>f.provider),written:[written.ratings,written.ids],itemJson:JSON.stringify(item)};},',
  ' baseShowName:mf555rBaseShowName,norm:mf439Norm,year:mf439Year};',
].join('\n');
vm.runInThisContext(code);
const { api } = globalThis;

const e = (provider, recordId, title, other = {}) => ({ provider, recordId: String(recordId), title, year: 0, externalIds: {}, fields: {}, ratings: {}, legacy: {}, ...other });
const k = (provider, title, ids = {}) => provider + '|' + title + '|' + JSON.stringify(Object.fromEntries(Object.entries(ids).sort()));
const NOW = 1762500000000;

const scenarios = [
  {
    name: 'saved MAL ID, then names, then recheck with new IDs',
    category: { unit: 'episodes', type: 'video' },
    providers: ['jikan', 'anilist', 'kitsu', 'tvmaze', 'omdb', 'tmdb'],
    item: { id: 'a1', title: 'Shingeki no Kyojin', categoryId: 'anime', year: 2013, externalIds: { mal: '16498' }, progress: 3, modifiedAt: 1700000000000,
      universalMetadata: { schemaVersion: 1, mediaType: 'anime', fields: { alternateTitles: ['進撃の巨人'] }, externalRatings: {}, provenance: {}, locks: {}, updatedAt: 0 } },
    answers: {
      [k('jikan', 'Shingeki no Kyojin', { mal: '16498' })]: [e('jikan', 16498, 'Shingeki no Kyojin', { year: 2013, aliases: ['Attack on Titan', '進撃の巨人'], externalIds: { mal: '16498' }, legacy: { mediaFormat: 'TV' }, ratings: { mal: { score: 8.55, scale: 10, votes: 2900000 } } })],
      [k('anilist', 'Shingeki no Kyojin', { mal: '16498' })]: [e('anilist', 16498, 'Shingeki no Kyojin', { year: 2013, aliases: ['Attack on Titan'], externalIds: { anilist: '16498', mal: '16498' }, ratings: { anilist: { score: 85, scale: 100, votes: null } } })],
      [k('kitsu', 'Attack on Titan', { mal: '16498', imdb: 'tt2560140' })]: [
        e('kitsu', 7442, 'Attack on Titan', { year: 2013, externalIds: { kitsu: '7442' }, legacy: { mediaFormat: 'TV' }, ratings: { kitsu: { score: 84.5, scale: 100, votes: 150000 } } }),
        e('kitsu', 9999, 'Attack on Titan: Junior High', { year: 2015, externalIds: { kitsu: '9999' } }),
      ],
      [k('omdb', 'Shingeki no Kyojin', { mal: '16498', imdb: 'tt2560140' })]: [e('omdb', 'tt2560140', 'Attack on Titan', { year: 2013, externalIds: { imdb: 'tt2560140' }, ratings: { imdb: { score: 9.1, scale: 10, votes: 600000 }, metacritic: { score: 0, scale: 100 } } })],
      [k('tmdb', 'Attack on Titan', { mal: '16498', imdb: 'tt2560140' })]: [
        e('tmdb', '1429', 'Attack on Titan', { year: 2013, externalIds: { tmdb_tv: '1429', imdb: 'tt2560140' }, ratings: { tmdb: { score: 8.7, scale: 10, votes: 7000 } } }),
      ],
    },
    wiki: { qid: 'Q482990', ids: { mal: '16498', imdb: 'tt2560140' }, parent: null },
  },
  {
    name: 'season shares the whole show rating; ambiguous names skipped',
    category: { unit: 'episodes', type: 'video' },
    providers: ['tvmaze', 'omdb', 'tmdb'],
    item: { id: 'b2', title: 'The Expanse Season 3', categoryId: 'tv', year: '2018', progress: 0 },
    answers: {
      [k('tvmaze', 'The Expanse Season 3', {})]: [e('tvmaze', 1825, 'The Expanse', { year: 2015 })],
      [k('omdb', 'The Expanse Season 3', {})]: [],
      [k('omdb', 'The Expanse', {})]: [
        e('omdb', 'tt3230854', 'The Expanse', { year: 2015, legacy: { mediaFormat: 'series' }, externalIds: { imdb: 'tt3230854' }, ratings: { imdb: { score: 8.5, scale: 10, votes: 190000 } } }),
      ],
      [k('tmdb', 'The Expanse Season 3', {})]: { error: 'TMDB: Please wait 1 second' },
      [k('tmdb', 'The Expanse', {})]: [
        e('tmdb', '63639', 'The Expanse', { year: 2015, externalIds: { tmdb_tv: '63639' }, ratings: { tmdb: { score: 8.0, scale: 10, votes: 3000 } } }),
        e('tmdb', '70000', 'The Expanse', { year: 2010, externalIds: { tmdb_tv: '70000' }, ratings: { tmdb: { score: 5, scale: 10 } } }),
      ],
    },
  },
  {
    name: 'manual ratings and saved IDs are never replaced; same-source refresh',
    category: { unit: 'movies', type: 'video' },
    providers: ['omdb', 'tmdb', 'trakt'],
    item: { id: 'c3', title: 'Dune: Part Two', categoryId: 'movie', releaseDate: '2024-03-01', externalIds: { imdb: 'tt15239678', tmdb: '693134' }, modifiedAt: 1800000000000,
      universalMetadata: { mediaType: 'movie', note: 'kept', externalRatings: {
        imdb: { score: 8.6, scale: 10, votes: 500000, url: '', updatedAt: 1, source: 'omdb' },
        tmdb: { score: 9.9, scale: 10, votes: null, url: '', updatedAt: 1, source: 'manual' },
        trakt: { score: 8.1, scale: 10, votes: 10, url: '', updatedAt: 1, source: 'trakt' } },
        provenance: { 'rating.imdb': { source: 'omdb', verified: true, recordId: 'tt15239678', updatedAt: 1 }, 'rating.tmdb': { source: 'manual', verified: false, updatedAt: 1 },
          'rating.trakt': { source: 'simkl', verified: true, updatedAt: 1 } },
        locks: { 'rating.tmdb': true }, updatedAt: 5 } },
    answers: {
      [k('omdb', 'Dune: Part Two', { imdb: 'tt15239678', tmdb: '693134' })]: [e('omdb', 'tt15239678', 'Dune: Part Two', { year: 2024, externalIds: { imdb: 'tt15239678' }, ratings: { imdb: { score: 8.5, scale: 10, votes: 620000 }, rottentomatoes_critics: { score: 92, scale: 100 }, metacritic: { score: 79, scale: 100, votes: null } } })],
      [k('tmdb', 'Dune: Part Two', { imdb: 'tt15239678', tmdb: '693134' })]: [e('tmdb', '693134', 'Dune: Part Two', { year: 2024, externalIds: { tmdb: '693134', imdb: 'tt99999999' }, ratings: { tmdb: { score: 8.2, scale: 10, votes: 5000 } } })],
      [k('trakt', 'Dune: Part Two', { imdb: 'tt15239678', tmdb: '693134' })]: [e('trakt', 'dune-part-two-2024', 'Dune: Part Two', { year: 2024, externalIds: { trakt: 'dune-part-two-2024', imdb: 'tt15239678' }, ratings: { trakt: { score: 8.4, scale: 10, votes: 20 }, imdb: { score: 1, scale: 10 } } })],
    },
  },
  {
    name: 'conflicting discoveries are not saved; wrong-year and wrong-type rows skipped',
    category: { unit: 'chapters', type: 'reading' },
    providers: ['jikan', 'anilist', 'kitsu', 'vndb'],
    item: { id: 'd4', title: 'Ｂｅｒｓｅｒｋ', titleEnglish: 'Berserk', categoryId: 'manga', year: 1989 },
    answers: {
      [k('jikan', 'Ｂｅｒｓｅｒｋ', {})]: [],
      [k('jikan', 'Berserk', {})]: [e('jikan', 2, 'Berserk', { year: 1989, externalIds: { mal: '2' }, ratings: { mal: { score: 9.47, scale: 10, votes: 350000 } } })],
      [k('anilist', 'Ｂｅｒｓｅｒｋ', {})]: [e('anilist', 30002, 'Berserk', { year: 1989, externalIds: { anilist: '30002', mal: '3' }, ratings: { anilist: { score: 93, scale: 100 } } })],
      [k('kitsu', 'Ｂｅｒｓｅｒｋ', {})]: [
        e('kitsu', 1, 'Berserk', { year: 1997, externalIds: { kitsu: '1' } }),
        e('kitsu', 2, 'Berserk', { year: 1990, legacy: { mediaFormat: 'movie' }, externalIds: { kitsu: '2' } }),
      ],
      [k('vndb', 'Ｂｅｒｓｅｒｋ', {})]: [],
      [k('vndb', 'Berserk', {})]: [],
    },
  },
];

const out = { generatedFrom: '396-v555-ratings-engine.js', now: NOW, scenarios: [] };
for (const sc of scenarios) {
  const r = await api.run({ ...sc, now: NOW });
  out.scenarios.push({ ...sc, now: NOW, expected: r });
}
out.baseShowNames = ['Attack on Titan Season 3', 'Attack on Titan: The Final Season Part 2', 'Mob Psycho 100 II', 'Re:Zero 2nd Season', 'Gintama S4', 'Kaguya-sama - Season 2', '進撃の巨人 第3期', 'Bleach', 'Part 2', 'Spy x Family Part 2']
  .map(t => [t, api.baseShowName(t)]);
out.norms = ['Ｂｅｒｓｅｒｋ', 'Re:Zero − Starting Life', '<b>Fate</b> &amp; Zero', 'Kaguya‐sama: Love is War', 'Ça va', '進撃の巨人'].map(t => [t, api.norm(t)]);
out.years = [[2013, api.year(2013)], ['2018-04-11', api.year('2018-04-11')], ['abc', api.year('abc')], [1700, api.year(1700)], ['', api.year('')]];
const here = path.dirname(new URL(import.meta.url).pathname);
fs.writeFileSync(path.join(here, '../../test/fixtures/ratings-golden.json'), JSON.stringify(out, null, 1) + '\n');
console.log('wrote', out.scenarios.length, 'scenarios');
for (const s of out.scenarios) console.log(s.name, JSON.stringify(s.expected.written), s.expected.accepted.map(a => a.join(':')).join(' '));
