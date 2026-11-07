// Generates test/fixtures/recovery-golden.json from the website's own v439
// Metadata Recovery (src/js/components/396-v555-ratings-engine.js) and the v437 /
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
  cnst('V377_ID_PROVIDERS'),
  // v433 (file 313) builds its allowed-ID set before v437 adds more keys.
  cnst('MF433_ALLOWED_ID_KEYS'), cnst('MF433_NATIVE_ID_KEYS'), cnst('v377IdValid'),
  fn('mf433ValidId'), fn('mf433NativeKey'), fn('mf433EnrichCoverCandidate'), fn('mf433CandidateLinks'), fn('mf433LinkCandidateIds'),
  cnst('MF437_RATING_SOURCES'), cnst('MF437_ADDITIONAL_IDS'),
  "for(const [key,label] of MF437_ADDITIONAL_IDS){if(!V377_ID_PROVIDERS.some(row=>row[0]===key))V377_ID_PROVIDERS.push([key,label,'Optional verified provider ID']);}",
  cnst('MF437_SCHEMA_VERSION'), cnst('MF437_MEDIA_TYPES'), cnst('MF437_RATING_MAP'),
  'const MF437_FIELD_MAP=new Map();',
  cnst('mf437Object'), cnst('mf437Copy'),
  fn('mf437Normalized'), fn('mf437Clean'), fn('mf437FieldCompare'), fn('mf437SetRating'),
  cnst('mf439Plain'), fn('mf439TitleVariants'), fn('mf439Norm'), fn('mf439Year'), cnst('mf439StringList'),
  cnst('MF439_LEGACY_FIELDS'), cnst('mf439Has'),
  fn('mf439FieldDefinition'), fn('mf439FieldValue'), fn('mf439IsProtected'), fn('mf439Value'), fn('mf439ValueKey'),
  fn('mf439Evidence'), fn('mf439Proposals'), fn('mf439Apply'),
  "const MF439={account:''};const mf439Account=()=>'';const mf439Preferences=()=>({minimumConfidence:0.94});",
  'Object.assign(globalThis,{mf433EnrichCoverCandidate,mf433CandidateLinks,mf433LinkCandidateIds});',
  'globalThis.api={run:(sc)=>{const item=JSON.parse(JSON.stringify(sc.item));',
  '  const realNow=Date.now;Date.now=()=>sc.now;let preview,res;try{preview=mf439Proposals(item,JSON.parse(JSON.stringify(sc.rows)));',
  '  for(const p of preview.proposals){if(sc.select&&sc.select[p.token]!==undefined){p.selected=true;p.choice=sc.select[p.token];}}',
  '  res=mf439Apply(item,preview,sc.mode||"review");}finally{Date.now=realNow;}',
  '  return {proposals:preview.proposals.map(p=>({token:p.token,status:p.status,selected:p.selected,choice:p.choice,options:p.options.length,providers:p.options[0].sources.map(s=>s.provider),confidence:p.options[0].confidence})),',
  '   errors:preview.errors.map(e=>e.provider),result:res,itemJson:JSON.stringify(item)};}};',
].join('\n');
vm.runInThisContext(code);
const { api, mf433EnrichCoverCandidate, mf433CandidateLinks, mf433LinkCandidateIds } = globalThis;
const NOW = 1762600000000;
const row = (provider, recordId, title, other = {}) => ({ provider, recordId: String(recordId), title, year: 0, externalIds: {}, fields: {}, ratings: {}, legacy: {}, ...other });
const scenarios = [
  {
    name: 'missing fields filled automatically; existing and protected kept; conflicts left for review',
    mode: 'automatic',
    item: { id: 'm1', title: 'Frieren', year: 2023, synopsis: '', genres: ['Fantasy'], studios: [], mediaFormat: '', externalIds: { mal: '52991' },
      richMetadataManual: { ageRating: true }, modifiedAt: 1, universalMetadata: { mediaType: 'anime' } },
    rows: [
      row('jikan', 52991, 'Sousou no Frieren', { year: 2023, aliases: ['Frieren'], externalIds: { mal: '52991' },
        legacy: { synopsis: '<p>An elf mage &amp; her party</p>', year: 2023, mediaFormat: 'TV', genres: ['Adventure', 'Drama'], ageRating: 'PG-13' },
        ratings: { mal: { score: 9.3, scale: 10, votes: 500000 } } }),
      row('anilist', 154587, 'Frieren', { year: 2023, externalIds: { anilist: '154587', mal: '52991' },
        legacy: { year: 2023, mediaFormat: 'TV_SHORT', durationMinutes: 24 }, ratings: { anilist: { score: 91, scale: 100 } } }),
      row('kitsu', 1, 'Frieren', { year: 2019, legacy: { synopsis: 'Wrong year' } }),
    ],
  },
  {
    name: 'review: chosen option of a conflict is applied, exact-title-only results need review',
    mode: 'review',
    select: { 'legacy.mediaFormat': 1, 'legacy.synopsis': 0 },
    item: { id: 'm2', title: 'Dune', releaseDate: '2021-10-22', modifiedAt: 5,
      universalMetadata: { externalRatings: { imdb: { score: 8, scale: 10, votes: 1, url: '', updatedAt: 1, source: 'manual' } },
        provenance: { 'rating.imdb': { source: 'manual', verified: false, updatedAt: 1 } }, locks: { 'rating.imdb': true } } },
    rows: [
      row('tmdb', 438631, 'Dune', { year: 2021, externalIds: { tmdb: '438631' }, legacy: { mediaFormat: 'Movie', synopsis: 'Paul Atreides…' }, ratings: { tmdb: { score: 7.8, scale: 10, votes: 12000 } } }),
      row('omdb', 'tt1160419', 'Dune', { year: 2021, externalIds: { imdb: 'tt1160419' }, legacy: { mediaFormat: 'movie (feature)' }, ratings: { imdb: { score: 8.0, scale: 10, votes: 900000 } } }),
    ],
  },
];
const out = { generatedFrom: '319-v439-metadata-recovery.js', now: NOW, scenarios: [], coverLinks: [] };
for (const sc of scenarios) out.scenarios.push({ ...sc, now: NOW, expected: api.run({ ...sc, now: NOW }) });

// Cover Recovery ID linking (v433 mf433EnrichCoverCandidate / CandidateLinks /
// LinkCandidateIds), as the cover chooser and automatic jobs use it.
const linkCases = [
  { name: 'AniList cover links AniList + the MAL ID AniList reports', manual: true,
    item: { title: 'Frieren', externalIds: {} },
    candidate: { provider: 'anilist', recordId: '154587', externalIdKey: 'anilist', externalIdValue: '154587', recordUrl: '' }, entry: { idMal: 52991 } },
  { name: 'conflicting saved ID is kept; the rest link', manual: true,
    item: { title: 'Frieren', externalIds: { mal: '1' } },
    candidate: { provider: 'anilist', recordId: '154587', externalIdKey: 'anilist', externalIdValue: '154587', recordUrl: '' }, entry: { idMal: 52991 } },
  { name: 'TVmaze cover links TVmaze + IMDb', manual: true,
    item: { title: 'Severance', externalIds: { tvmaze: '44933' } },
    candidate: { provider: 'tvmaze', recordId: '44933', externalIdKey: 'tvmaze', externalIdValue: '44933', recordUrl: '' }, entry: { externals: { imdb: 'tt11280740' } } },
  { name: 'Open Library work ID', manual: true,
    item: { title: 'Dune', externalIds: {} },
    candidate: { provider: 'openlibrary', recordId: 'OL893415W', externalIdKey: 'openlibrary', externalIdValue: 'OL893415W', recordUrl: '' }, entry: {} },
  { name: 'TMDB TV from the gateway', manual: true,
    item: { title: 'Arcane', externalIds: {} },
    candidate: { provider: 'tmdb', recordId: '94605', externalIdKey: 'tmdb_tv', externalIdValue: '94605', recordUrl: '' }, entry: {} },
  { name: 'automatic link skips IDs the person cleared or wrote', manual: false,
    item: { title: 'Frieren', externalIds: {}, v377ManualExternalIds: { mal: '' } },
    candidate: { provider: 'anilist', recordId: '154587', externalIdKey: 'anilist', externalIdValue: '154587', recordUrl: '' }, entry: { idMal: 52991 } },
  { name: 'iTunes has no linkable ID', manual: true,
    item: { title: 'Ants From Up There', externalIds: {} },
    candidate: { provider: 'itunes', recordId: '1590446045', externalIdKey: '', externalIdValue: '', recordUrl: '' }, entry: {} },
];
for (const lc of linkCases) {
  const item = JSON.parse(JSON.stringify(lc.item));
  const c = mf433EnrichCoverCandidate(lc.entry, { ...lc.candidate });
  const links = mf433CandidateLinks(item, c);
  const changes = mf433LinkCandidateIds(item, c, { manual: lc.manual });
  out.coverLinks.push({ ...lc, expected: { ids: c.externalIdCandidates.map(r => [r.key, r.value]), links, changes, itemJson: JSON.stringify(item) } });
}
const here = path.dirname(new URL(import.meta.url).pathname);
fs.writeFileSync(path.join(here, '../../test/fixtures/recovery-golden.json'), JSON.stringify(out, null, 1) + '\n');
for (const s of out.scenarios) console.log(s.name, JSON.stringify(s.expected.result), s.expected.proposals.map(p => p.token + ':' + p.status + (p.selected ? '*' : '')).join(' '));
