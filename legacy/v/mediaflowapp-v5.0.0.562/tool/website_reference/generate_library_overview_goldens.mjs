// test/fixtures/library-overview-golden.json: the website's own
// v53LibraryOverview + v183LibraryOverviewEstimate over sample libraries.
//   node tool/website_reference/generate_library_overview_goldens.mjs <website checkout>
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const site = process.argv[2];
const read = f => fs.readFileSync(path.join(site, 'src/js', f), 'utf8');
function fn(src, name) {
  const at = src.indexOf(`function ${name}(`);
  if (at < 0) throw new Error(name);
  let i = src.indexOf('{', at), depth = 0;
  for (; i < src.length; i++) { if (src[i] === '{') depth++; else if (src[i] === '}' && --depth === 0) break; }
  return src.slice(at, i + 1);
}
const v53 = fn(read('pages/library/012-v63-large-library-performance-engine.js'), 'v53LibraryOverview');
const est = fn(read('legacy/117-v183.js'), 'v183LibraryOverviewEstimate');

const categories = [
  { id: 'anime', target: 3 }, { id: 'manga', target: 0 }, { id: 'books', target: 20 }, { id: 'empty', target: 2 }, { id: 'games' },
];
const libraries = {
  mixed: [
    { categoryId: 'anime', progress: 12, total: 12 }, { categoryId: 'anime', progress: 30, total: 24 }, { categoryId: 'anime', progress: 5, total: 0 },
    { categoryId: 'manga', progress: 140 }, { categoryId: 'manga', progress: '20', total: '' }, { categoryId: 'manga', progress: -3 },
    { categoryId: 'books', progress: 100, total: 300 }, { categoryId: 'books', progress: 50, total: 200 },
    { categoryId: 'games', progress: 0 }, { categoryId: 'gone', progress: 7, total: 10 },
  ],
  allUnknown: [{ categoryId: 'books', progress: 0 }, { categoryId: 'books', progress: 0 }, { categoryId: 'anime', progress: 1000 }],
  none: [],
};
const out = { categories, cases: {} };
for (const [name, library] of Object.entries(libraries)) {
  const ctx = { S: { categories, library } };
  vm.createContext(ctx);
  vm.runInContext(`function v53EnsureLibraryIndex(){} const V53_LIB={}; ${v53} ${est}
    const ov=v53LibraryOverview();
    globalThis.result={overallPct:ov.overallPct,totalDone:ov.totalDone,totalAll:ov.totalAll,
      rows:S.categories.map(cat=>{const x=ov.byCat.get(cat.id)||{items:0,done:0,knownDone:0,total:0,unknown:false};return {id:cat.id,...x,...v183LibraryOverviewEstimate(cat,x)};})};`, ctx);
  out.cases[name] = { library, expected: JSON.parse(JSON.stringify(ctx.result)) };
}
const here = path.dirname(new URL(import.meta.url).pathname);
fs.writeFileSync(path.join(here, '../../test/fixtures/library-overview-golden.json'), JSON.stringify(out, null, 1) + '\n');
console.log(JSON.stringify(out.cases.mixed.expected.rows));
