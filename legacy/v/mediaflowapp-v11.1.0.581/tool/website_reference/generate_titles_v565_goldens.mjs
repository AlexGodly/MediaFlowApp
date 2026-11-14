// Golden fixtures for website v565 titles (411-v565-titles.js): a title's own
// unit and its names in every language. Runs the real website file and
// records what it returns, for test/titles_v565_golden_test.dart.
//
//   node tool/website_reference/generate_titles_v565_goldens.mjs <path to MediaFlow repo>
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const site = process.argv[2] || '../MediaFlow';
const src = fs.readFileSync(path.join(site, 'src/js/components/411-v565-titles.js'), 'utf8');
const util = fs.readFileSync(path.join(site, 'src/js/utils/006-util.js'), 'utf8');
const ct = util.indexOf('function cleanTitle(');
const cleanTitleSrc = util.slice(ct, util.indexOf('\n}', ct) + 2);

const UNITS = {
  episodes: { label: 'episodes', singular: 'episode' }, chapters: { label: 'chapters', singular: 'chapter' },
  movies: { label: 'movies', singular: 'movie' }, issues: { label: 'issues', singular: 'issue' },
  sessions: { label: 'sessions', singular: 'session' }, videos: { label: 'videos', singular: 'video' },
  pages: { label: 'pages', singular: 'page' }, volumes: { label: 'volumes', singular: 'volume' },
  tracks: { label: 'tracks', singular: 'track' }, albums: { label: 'albums', singular: 'album' },
  levels: { label: 'levels', singular: 'level' }, missions: { label: 'missions', singular: 'mission' },
  matches: { label: 'matches', singular: 'match' }, lessons: { label: 'lessons', singular: 'lesson' },
  items: { label: 'items', singular: 'item' },
};
const ctx = {
  window: {}, MediaFlowRuntime: { registerPageEnhancer() {} }, S: { settings: {}, library: [] },
  document: { addEventListener() {}, documentElement: {}, body: {} }, UNITS, App: {}, setTimeout() {}, setInterval() {},
  getCategory: () => ({ unit: 'sessions', minutesPerUnit: 60 }), MutationObserver: function () { this.observe = () => {}; },
  requestAnimationFrame: () => 0,
};
vm.createContext(ctx);
vm.runInContext(`
function unitLabel(k,c){const u=UNITS[k]||UNITS.episodes;return c===1?u.singular:u.label;}
// The website's own cleanTitle (utils/006-util.js).
${cleanTitleSrc}
function v369DefaultSeconds(){return 3600;}
function batchTitleCandidates(){return [];}
function mf439TitleVariants(i){return [i.title];}
async function mf439Discover(){return {};}
function mf439Apply(){return {changed:0};}
function libraryModalHtml(){return '';}
var renderView=()=>{};
var persistLibrary=()=>{};
${src}
this.api={mf565UnitFactor,mf565ToCategoryAmount,mf565UnitKey,mf565TitleSeconds,unitLabel,mf565Names,mf565DisplayTitle,
  mf565NameMatches,mf565SearchText,mf565AddNames,mf565WriteEditor,mf565ScriptLang,mf565Singular,mf565NamePrefs,S};`, ctx);
const a = ctx.api;

const cats = {
  hour: { unit: 'sessions', minutesPerUnit: 60 },
  secs: { unit: 'sessions', secondsPerUnit: 1500, minutesPerUnit: 99 },
  frac: { unit: 'episodes', minutesPerUnit: 23.5 },
  none: { unit: 'episodes' },
};
const items = {
  plain: { title: 'Plain' },
  matches: { title: 'Game', mf565Unit: 'matches', mf565SecondsPerUnit: 1200 },
  noRuntime: { title: 'Game', mf565Unit: 'rounds' },
  long: { title: 'Long', mf565Unit: 'boss fights', mf565SecondsPerUnit: 5400 },
  odd: { title: 'Odd', mf565Unit: 'laps', mf565SecondsPerUnit: 700 },
  spaces: { title: 'S', mf565Unit: '  races  ', mf565SecondsPerUnit: 900.9 },
};
const units = [];
for (const [ik, item] of Object.entries(items)) {
  for (const [ck, cat] of Object.entries(cats)) {
    for (const q of [0, 1, 3, 2.5, 7]) {
      units.push({ item: ik, cat: ck, qty: q, factor: a.mf565UnitFactor(item, cat), amount: a.mf565ToCategoryAmount(item, cat, q),
        key: a.mf565UnitKey(item, cat), seconds: a.mf565TitleSeconds(item, cat) });
    }
  }
}
const labels = [];
for (const w of ['matches', 'rounds', 'boss fights', 'boxes', 'stories', 'glass', 'quizzes', 'runs', 'days', 'chess', 'episodes', 'sessions'])
  for (const c of [1, 2]) labels.push({ unit: w, count: c, label: a.unitLabel(w, c) });

const nameItems = [
  { title: 'Shingeki no Kyojin', titleEnglish: 'Attack on Titan', titleRomaji: 'Shingeki no Kyojin', categoryId: 'anime',
    universalMetadata: { fields: { originalTitle: { value: '進撃の巨人' }, alternateTitles: { value: ['AoT', '进击的巨人', '진격의 거인'] } } } },
  { title: 'Main', mf565Names: [{ lang: 'ja', text: 'メイン' }, { lang: 'xx', text: 'Weird' }, { lang: 'en', text: '  Main  Eng ' }], mf565NameLanguage: 'ja', categoryId: 'manga' },
  { title: 'Only Main', categoryId: 'anime' },
  { title: 'Exempt', titleEnglish: 'Eng', mf565NameExempt: true, categoryId: 'anime' },
  { title: 'Orig', originalTitle: 'オリジナル', categoryId: 'games' },
  { title: 'Dup', mf565Names: [{ lang: 'en', text: 'Same' }, { lang: 'en', text: 'same' }, { lang: 'fr', text: 'Same' }], categoryId: 'games' },
];
const prefSets = [
  { global: 'main', categories: {} },
  { global: 'en', categories: {} },
  { global: 'en', categories: { manga: 'ja', anime: 'ja' } },
  { global: 'ja-Latn', categories: { games: 'fr' } },
];
const names = nameItems.map(item => ({
  item, names: a.mf565Names(item), search: a.mf565SearchText(item),
  shown: prefSets.map(p => a.mf565DisplayTitle(item, p)),
  matches: ['titan', 'aot', '巨人', 'eng', 'メイン', 'nothing', '', 'MAIN', 'same'].map(q => a.mf565NameMatches(item, q)),
}));
const prefsRaw = [
  undefined, {}, { global: 'zz' }, { global: 'en', categories: { a: 'ja', b: 'nope', c: '' } },
].map(raw => { a.S.settings = { mf565TitleNames: raw }; return { raw: raw ?? null, prefs: a.mf565NamePrefs() }; });

const addCases = [
  [{ title: 'A', mf565Names: [{ lang: 'en', text: 'B' }] }, [{ lang: 'en', text: 'B' }, { lang: 'ja', text: 'C', source: 'anilist' }, { lang: 'en', text: 'a' }]],
  [{ title: 'X', titleEnglish: 'Eng' }, [{ lang: 'en', text: 'Eng' }, { lang: 'en', text: 'eng' }, { lang: 'ko', text: 'K', source: 'kitsu' }]],
  [{ title: 'Y' }, []],
].map(([item, add]) => { const copy = JSON.parse(JSON.stringify(item)); const n = a.mf565AddNames(copy, add); return { item, add, added: n, after: copy }; });

const editCases = [
  [{ id: 't', title: 'T', modifiedAt: 5 }, { unit: 'matches', secs: 1200, names: [{ lang: 'en', text: 'Tee' }], lang: 'en', exempt: false }, []],
  [{ id: 't', title: 'T', mf565Unit: 'matches', mf565SecondsPerUnit: 1200, modifiedAt: 5 }, { unit: '', secs: 1200, names: [], lang: '', exempt: false }, []],
  [{ id: 't', title: 'T', mf565Unit: 'laps', modifiedAt: 5 }, { unit: 'laps', secs: 0, names: [], lang: '', exempt: true }, []],
  [{ id: 't', title: 'T', mf565Names: [{ lang: 'en', text: 'Tee', source: 'anilist' }], modifiedAt: 5 },
    { unit: '', secs: 0, names: [{ lang: 'en', text: 'Tee' }, { lang: 'ja', text: 'ティー' }], lang: '', exempt: false },
    [{ lang: 'en', text: 'Tee', source: 'anilist' }]],
  [{ id: 't', title: 'T', mf565Names: [{ lang: 'en', text: 'Tee', source: 'anilist' }], modifiedAt: 5 },
    { unit: '', secs: 0, names: [{ lang: 'en', text: 'Tee' }], lang: '', exempt: false },
    [{ lang: 'en', text: 'Tee', source: 'anilist' }]],
].map(([item, data, before]) => {
  const copy = JSON.parse(JSON.stringify(item));
  vm.runInContext('Date.now=()=>1000', ctx); // the sandbox has its own Date
  const changed = a.mf565WriteEditor(copy, data, before);
  return { item, data, before, changed, after: copy };
});

const out = { units, labels, names, prefSets, prefsRaw, addCases, editCases,
  scripts: ['進撃', 'メイン', '진격', 'abc', '进击'].map(t => [t, a.mf565ScriptLang(t)]) };
fs.writeFileSync('test/fixtures/titles-v565-golden.json', JSON.stringify(out, null, 1) + '\n');
console.log(`titles v565 goldens: ${units.length} unit cases, ${labels.length} labels, ${names.length} name items, ${editCases.length} editor cases`);
