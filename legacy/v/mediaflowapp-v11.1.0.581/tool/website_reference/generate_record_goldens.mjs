// Generates test/fixtures/records-golden.json from the website's own v556 code
// (src/js/components/399-v556-record-sync.js): the records the website writes
// for an account, before and after edits, plus sample hashes. The app's port
// (lib/src/data/records.dart) must produce exactly the same rows.
//
//   node tool/website_reference/generate_record_goldens.mjs <website checkout>
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const site = process.argv[2];
if (!site) { console.error('usage: generate_record_goldens.mjs <MediaFlow website checkout>'); process.exit(2); }
const src = fs.readFileSync(path.join(site, 'src/js/components/399-v556-record-sync.js'), 'utf8');
const pick = (re, what) => { const m = src.match(re); if (!m) throw Error('not found: ' + what); return m[0]; };
const fn = name => pick(new RegExp('(?:async )?function ' + name + '\\([\\s\\S]*?\\n}\\n'), name);
const code = [
  pick(/const MF556_ARRAYS=.*\n/, 'arrays'), pick(/const MF556_SEP=.*\n/, 'sep'),
  'const MF556={local:new Map()};', 'const mf556Tick=()=>async()=>{};',
  pick(/const mf556Key=.*\n/, 'key'),
  fn('mf556Hash'), fn('mf556ArrayHasIds'), fn('mf556Positions'), fn('mf556Decompose'), fn('mf556Compose'),
  'globalThis.api={hash:mf556Hash,positions:mf556Positions,decompose:mf556Decompose,compose:mf556Compose,local:MF556.local,key:mf556Key};',
].join('\n');
vm.runInThisContext(code);
const { api } = globalThis;

const here = path.dirname(new URL(import.meta.url).pathname);
const seed = JSON.parse(fs.readFileSync(path.join(here, 'seed-account.json'), 'utf8'));
const state1 = seed.state || seed;
const rows = recs => [...recs.values()].map(r => ({ k: r.k, i: r.i, pos: r.pos, j: r.j, h: api.hash(r.j + '|' + (r.pos ?? '')) }));

const recs1 = await api.decompose(state1);
for (const [key, r] of recs1) api.local.set(key, { ...r });

// Edits: move a title, add titles at the start, middle and end, delete one,
// change a setting and a numeric field with a whole-number double.
const state2 = JSON.parse(JSON.stringify(state1));
const lib = state2.library;
const moved = lib.splice(lib.length - 1, 1)[0];
lib.splice(1, 0, moved);
lib.unshift({ id: 'lib_new_first', title: 'New first', categoryId: lib[0]?.categoryId || 'cat', progress: 0, total: 12 });
lib.splice(Math.floor(lib.length / 2), 0, { id: 'lib_new_mid', title: 'Middle "quoted" éè ☃', rating: 7.5 });
lib.push({ id: 'lib_new_last', title: 'Last', progress: 3, total: 24, modifiedAt: 1794000000000 });
if (lib.length > 6) lib.splice(4, 1);
state2.settings = { ...(state2.settings || {}), v558Probe: true, v558Number: 2.25 };
const recs2 = await api.decompose(state2);

const back = await api.compose([...recs2.values()]);
if (JSON.stringify(back) !== JSON.stringify(state2)) throw Error('website compose round-trip failed');

const samples = ['', 'a', 'MediaFlow', '{"id":"x","n":1}|1024', 'café ☃ 😀', 'x'.repeat(5000)];
const out = {
  generatedFrom: 'MediaFlow website v556 record sync (399-v556-record-sync.js)',
  state1, records1: rows(recs1),
  state2, records2: rows(recs2),
  positions: [
    { ids: ['a', 'b', 'c', 'd'], prev: {}, out: api.positions(['a', 'b', 'c', 'd'], new Map()) },
    { ids: ['d', 'a', 'x', 'b', 'c', 'y'], prev: { a: 0, b: 1024, c: 2048, d: 3072 },
      out: api.positions(['d', 'a', 'x', 'b', 'c', 'y'], new Map(Object.entries({ a: 0, b: 1024, c: 2048, d: 3072 }))) },
    { ids: ['a', 'n1', 'n2', 'n3', 'b'], prev: { a: 0, b: 0.0003 },
      out: api.positions(['a', 'n1', 'n2', 'n3', 'b'], new Map(Object.entries({ a: 0, b: 0.0003 }))) },
  ],
  hashes: samples.map(s => [s, api.hash(s)]),
};
const target = path.join(here, '../../test/fixtures/records-golden.json');
fs.writeFileSync(target, JSON.stringify(out, null, 1));
console.log('wrote', target, 'records1', out.records1.length, 'records2', out.records2.length);
