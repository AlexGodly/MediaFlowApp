// test/fixtures/cover-match-golden.json: the website's own Cover Recovery
// matching (v424 mf424Normalize / mf424Titles / mf424Match) over sample
// titles and provider records, including the record shapes each provider
// adapter builds (AniList, Kitsu, TVmaze, MangaDex, Open Library, Google Books).
//   node tool/website_reference/generate_cover_match_goldens.mjs <website checkout>
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const site = process.argv[2];
const read = f => fs.readFileSync(path.join(site, 'src/js', f), 'utf8');
function fn(src, name) {
  const at = src.indexOf(`function ${name}(`);
  if (at < 0) throw new Error(name);
  let i = src.indexOf('{', src.indexOf(')', at)), depth = 0;
  for (; i < src.length; i++) { if (src[i] === '{') depth++; else if (src[i] === '}' && --depth === 0) break; }
  return src.slice(at, i + 1) + '\n';
}
const cover = read('components/309-v424-advanced-cover-recovery.js');
const code = fn(read('utils/006-util.js'), 'cleanTitle') + ['mf424Normalize', 'mf424Titles', 'mf424Match'].map(n => fn(cover, n)).join('');
const ctx = {};
vm.createContext(ctx);
vm.runInContext(code + 'globalThis.api={norm:mf424Normalize,titles:mf424Titles,match:mf424Match};', ctx);

const normalize = [
  'Frieren: Beyond Journey’s End', '  SPY×FAMILY  ', 'Ｆｕｌｌｗｉｄｔｈ　Ｔｅｘｔ１２３', 'Kaguya-sama: Love is War -Ultra Romantic-',
  'Re:ZERO -Starting Life in Another World-', 'Ōshi no Ko', 'ﬁnal ﬂight', 'Ⅻ Kingdoms', '進撃の巨人', 'Pokémon', '½ Prince', '', 'İstanbul',
];
const items = {
  plain: { title: 'Frieren: Beyond Journey’s End' },
  year2023: { title: 'Frieren: Beyond Journey’s End', year: 2023 },
  releaseYear: { title: '<![CDATA[Oshi no Ko]]>', releaseYear: '2023' },
  pubYear: { title: 'Dune', publicationYear: 1965 },
  noTitle: { title: '' },
};
const records = {
  // AniList adapter: {id, idMal, title: romaji, titles: [english, native, ...synonyms], year}
  anilist: { id: 154587, idMal: 52991, title: 'Sousou no Frieren', titles: ['Frieren: Beyond Journey’s End', '葬送のフリーレン', 'Frieren at the Funeral'], year: 2023 },
  anilistOther: { id: 1, title: 'Cowboy Bebop', titles: ['Cowboy Bebop', null], year: 1998 },
  // Jikan/Tenrai raw record
  jikan: { mal_id: 52991, title: 'Sousou no Frieren', title_english: 'Frieren: Beyond Journey\'s End', title_japanese: '葬送のフリーレン',
    title_synonyms: ['Frieren The Slayer'], titles: [{ type: 'Default', title: 'Sousou no Frieren' }, { type: 'English', title: 'Frieren: Beyond Journey’s End' }], year: 2024 },
  // Kitsu adapter
  kitsu: { id: '46474', title: 'Oshi no Ko', titles: ['[Oshi No Ko]', '【推しの子】'], year: 2023 },
  // TVmaze adapter
  tvmaze: { title: 'Dune', year: 2021 },
  // Open Library / Google Books adapters
  openlibrary: { title: 'Dune', year: 1965 },
  googlebooks: { title: 'Dune', year: 0 },
  premiered: { name: 'Dune', premiered: '1965-08-01' },
  publishedFrom: { title: 'Dune', published: { from: '1966-01-01T00:00:00+00:00' } },
  kitsuRaw: { attributes: { canonicalTitle: 'Oshi no Ko', titles: { en: 'Oshi no Ko', ja_jp: '【推しの子】' } } },
};
const matches = [];
for (const [iname, item] of Object.entries(items)) {
  for (const [rname, rec] of Object.entries(records)) {
    for (const idMatch of [false, true]) {
      matches.push({ item: iname, record: rname, idMatch, expected: JSON.parse(JSON.stringify(ctx.api.match(item, rec, idMatch))) });
    }
  }
}
const out = {
  normalize: normalize.map(s => [s, ctx.api.norm(s)]),
  titles: Object.fromEntries(Object.entries(records).map(([k, r]) => [k, ctx.api.titles(r)])),
  items, records, matches,
};
const here = path.dirname(new URL(import.meta.url).pathname);
fs.writeFileSync(path.join(here, '../../test/fixtures/cover-match-golden.json'), JSON.stringify(out, null, 1) + '\n');
console.log(out.normalize.map(x => JSON.stringify(x)).join('\n'));
console.log(out.matches.filter(m => m.item === 'year2023').map(m => `${m.record} ${m.idMatch} ${m.expected.confidence}`).join(' | '));
