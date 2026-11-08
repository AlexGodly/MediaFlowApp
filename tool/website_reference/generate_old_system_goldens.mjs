// Generates test/fixtures/old-system-golden.json by running the website's own
// Old System files (pages/old-system/057-v153-old-system.js and
// 076-old-system-date-view.js) in a sandbox with stand-ins for the rest of the
// app. Each scenario applies a sequence of actions; the fixture records the
// saved `oldSystem` (exactly as the website writes it) after each one, plus
// the History replay (View, Date View, Stats).
//
//   node tool/website_reference/generate_old_system_goldens.mjs <website checkout>
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const site = process.argv[2];
if (!site) { console.error('usage: generate_old_system_goldens.mjs <MediaFlow website checkout>'); process.exit(2); }
const dir = path.join(site, 'src/js');
const read = f => fs.readFileSync(path.join(dir, f), 'utf8');
const units = read('core/constants/001-constants.js').match(/const UNITS = \{[\s\S]*?\n\};/)[0];
const NOW = 1762600000000;
// The website's v153EnsureOldSystem swaps S.oldSystem for a fresh copy on
// every call. v153ApplyConsumption holds the old copy while it looks up the
// rules (which calls Ensure again), so the rule costs and the transaction it
// writes afterwards are lost: the category goes up, nothing is subtracted and
// Undo has nothing to undo. The app does what the page means to do; this
// variant keeps the same object so the fixture shows that. Every other action
// writes the same with or without it (checked below).
const KEEP_IDENTITY = `{const base=v153EnsureOldSystem;v153EnsureOldSystem=function(){const cur=S.oldSystem;const out=base();if(cur&&typeof cur==='object'&&cur!==out){for(const k of Object.keys(cur))delete cur[k];Object.assign(cur,out);S.oldSystem=cur;}return S.oldSystem;};}`;

function run(sc, keepIdentity) {
  const ctx = {
    console, Date: class extends Date { static now() { return ctx.__now; } },
    __now: NOW, __uid: 0, __balanceInput: '',
  };
  vm.createContext(ctx);
  vm.runInContext(`
${units}
let S={categories:${JSON.stringify(sc.categories)},sessions:${JSON.stringify(sc.sessions || [])},oldSystem:${JSON.stringify(sc.oldSystem ?? null)}};
function uid(){return 'u'+(++globalThis.__uid);}
function unitLabel(unitKey,count){const u=UNITS[unitKey]||UNITS.episodes;return count===1?u.singular:u.label;}
function getCategory(id){return S.categories.find(c=>c.id===id)||{id,name:'(removed category)',icon:'❔',color:'#555',unit:'episodes',target:1,minutesPerUnit:10,weight:1,enabled:false};}
function escapeHtml(s){return String(s);}
function saveState(){} function render(){} function showToast(){} function fmtMinutes(m){return m+'m';}
const document={getElementById(){return {value:globalThis.__balanceInput};}};
const ICONS={},NAV_ITEMS=[],MOBILE_MORE_NAV=[];const App={setView(){}};
function renderView(){} function persistSessions(){} function mfCommit(){} function mfRestoreCore(){} function snapshot(){return {};}
async function loadAll(){} function v46ApplyState(){} function mergeStates(){return {};} function v148BackupManifest(){return {};}
function v144CategoryIconHtml(){return '';}
${read('pages/old-system/057-v153-old-system.js')}
${read('pages/old-system/076-old-system-date-view.js')}
${keepIdentity ? KEEP_IDENTITY : ''}
globalThis.api={
  act(a){
    globalThis.__now=a.at||globalThis.__now;
    switch(a.op){
      case 'toggle':v153ToggleCategory(a.id);break;
      case 'addRule':v153AddRule();break;
      case 'updateRule':v153UpdateRule(a.id,a.key,a.value);break;
      case 'removeRule':v153RemoveRule(a.id);break;
      case 'setBalance':globalThis.__balanceInput=a.value;v153SetBalance(a.id);break;
      case 'consume':v153EnsureOldSystem();S.oldSystemUI.consumeCategoryId=a.id;S.oldSystemUI.consumeAmount=a.amount;v153ApplyConsumption();break;
      case 'undo':v153Undo();break;
      case 'mode':App.v153SetOldSystemMode(a.mode);break;
      case 'date':v173SetOldSystemDate(a.key,a.value);break;
      case 'clearDates':v173ClearOldSystemDates();break;
    }
    return JSON.stringify(S.oldSystem);
  },
  replay(dateRange){
    const c=dateRange?v173BuildOldSystemCacheForRows(v173OldSystemDateRows()):v153BuildHistoryCache();
    const o=m=>Object.fromEntries([...m.entries()].map(([k,v])=>[k,Math.round(v*1e6)/1e6]));
    return {rawTotals:o(c.rawTotals),sessionCounts:o(c.sessionCounts),minuteTotals:o(c.minuteTotals),
      simulatedBalances:o(c.simulatedBalances),simulatedSpent:o(c.simulatedSpent),activityRows:c.activityRows};
  },
  normalized(){return JSON.stringify(v153NormalizeOldSystem(S.oldSystem));}
};`, ctx);
  const steps = sc.actions.map(a => ({ action: a, oldSystem: ctx.api.act(a) }));
  return { steps, view: ctx.api.replay(false), dateView: ctx.api.replay(true), normalized: ctx.api.normalized() };
}

const cats = [
  { id: 'anime', name: 'Anime', unit: 'episodes' },
  { id: 'manga', name: 'Manga', unit: 'chapters' },
  { id: 'books', name: 'Books', unit: 'pages' },
  { id: 'games', name: 'Games', unit: 'hours' },
];
const sessions = [
  { id: 's1', categoryId: 'anime', actualAmount: 3, minutes: 72, timestamp: NOW - 5 * 86400000, date: '2026-11-03', status: 'complete' },
  { id: 's2', categoryId: 'manga', actualAmount: 12, minutes: 40, timestamp: NOW - 4 * 86400000, date: '2026-11-04', status: 'complete' },
  { id: 's3', categoryId: 'anime', actualAmount: 2, minutes: 48, timestamp: NOW - 3 * 86400000, date: '2026-11-05', status: 'partial' },
  { id: 's4', categoryId: 'books', actualAmount: 30, minutes: 50, timestamp: NOW - 2 * 86400000, date: '2026-11-06', status: 'skipped' },
  { id: 's5', categoryId: 'deleted', actualAmount: 9, minutes: 9, timestamp: NOW - 2 * 86400000, date: '2026-11-06', status: 'complete' },
  { id: 's6', categoryId: 'books', actualAmount: 25, minutes: 45, timestamp: NOW - 86400000, status: 'complete' },
];
const scenarios = [
  {
    name: 'categories, rules, consumption, balance, undo, modes and dates',
    categories: cats, sessions,
    actions: [
      { op: 'toggle', id: 'anime' }, { op: 'toggle', id: 'manga' }, { op: 'toggle', id: 'books', at: NOW + 1000 },
      { op: 'addRule', at: NOW + 2000 },
      { op: 'updateRule', id: 'u1', key: 'fromAmount', value: '3' },
      { op: 'updateRule', id: 'u1', key: 'toAmount', value: 2 },
      { op: 'updateRule', id: 'u1', key: 'toCategoryId', value: 'anime' },
      { op: 'updateRule', id: 'u1', key: 'fromAmount', value: '0' },
      { op: 'addRule' }, { op: 'updateRule', id: 'u2', key: 'fromCategoryId', value: 'books' },
      { op: 'consume', id: 'manga', amount: 4, at: NOW + 3000 },
      { op: 'consume', id: 'anime', amount: 2.5, at: NOW + 4000 },
      { op: 'setBalance', id: 'books', value: '1234.5678', at: NOW + 5000 },
      { op: 'setBalance', id: 'books', value: 'abc' },
      { op: 'undo', at: NOW + 6000 },
      { op: 'mode', mode: 'view' }, { op: 'mode', mode: 'date' }, { op: 'mode', mode: 'nope' },
      { op: 'date', key: 'dateFrom', value: '2026-11-04' }, { op: 'date', key: 'dateTo', value: 'garbage' },
      { op: 'consume', id: 'games', amount: 1 },
      { op: 'toggle', id: 'manga', at: NOW + 7000 },
    ],
  },
  {
    name: 'saved data from older versions is normalized',
    categories: cats, sessions,
    oldSystem: {
      enabledCategoryIds: ['anime', 'anime', 'gone', 'books'],
      balances: { anime: '5', books: 'NaN', manga: -2 },
      rules: [
        { id: 'r1', fromCategoryId: 'books', toCategoryId: 'anime', fromAmount: -4, toAmount: 0, createdAt: 5 },
        { id: 'r2', fromCategoryId: 'anime', toCategoryId: 'anime' },
        { fromCategoryId: 'manga', toCategoryId: 'anime', fromAmount: 2 },
      ],
      transactions: [{ id: 't1', timestamp: 7, amount: 'x', deltas: [{ categoryId: 'anime', delta: 2 }, { categoryId: '', delta: 1 }, { categoryId: 'books', delta: 'bad' }] }],
      mode: 'stats', modifiedAt: 99, dateFrom: '2026-01-01', dateTo: '2026-13', extra: 'dropped',
    },
    actions: [{ op: 'consume', id: 'anime', amount: 1, at: NOW + 10 }, { op: 'undo' }, { op: 'clearDates' }],
  },
];
const out = { generatedFrom: 'pages/old-system (v153 + v173)', now: NOW, scenarios: scenarios.map(sc => {
  const fixed = run(sc, true), raw = run(sc, false);
  const differs = fixed.steps.map((st, i) => st.oldSystem !== raw.steps[i].oldSystem ? i : -1).filter(i => i >= 0);
  return { ...sc, expected: fixed, websiteAsIs: { differingSteps: differs, steps: raw.steps.map(x => x.oldSystem) } };
}) };
const here = path.dirname(new URL(import.meta.url).pathname);
fs.writeFileSync(path.join(here, '../../test/fixtures/old-system-golden.json'), JSON.stringify(out, null, 1) + '\n');
for (const sc of out.scenarios) console.log(sc.name, sc.expected.steps.length, 'steps; differ as-is at', sc.websiteAsIs.differingSteps.map(i => sc.actions[i].op + '#' + i).join(', '));
