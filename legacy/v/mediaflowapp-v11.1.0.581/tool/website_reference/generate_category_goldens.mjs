// test/fixtures/category-golden.json and lib/src/logic/category_defaults.g.dart
// from the website: the category editor's save (v283 form + v369 runtime +
// v286 save + v74 order), delete (v283), restore (v171), clear (v282), and the
// constants (DEFAULT_CATEGORIES, COLOR_CHOICES, ICON_CHOICES).
//   node tool/website_reference/generate_category_goldens.mjs <website checkout>
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const site = process.argv[2];
const read = f => fs.readFileSync(path.join(site, 'src/js', f), 'utf8');
function fn(src, name, prefix = 'function ') {
  const at = src.indexOf(prefix + name);
  if (at < 0) throw new Error(name);
  let i = src.indexOf('{', src.indexOf(')', at)), depth = 0, q = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (q) { if (c === '\\') { i++; continue; } if (c === q) q = null; continue; }
    if (c === '/' && src[i + 1] === '/' && src[i - 1] !== ':' && src[i - 1] !== '\\') { i = src.indexOf('\n', i); continue; }
    if (c === '/' && src[i + 1] === '*') { i = src.indexOf('*/', i) + 1; continue; }
    if (c === '"' || c === "'" || c === '`') { q = c; continue; }
    if (c === '{') depth++; else if (c === '}' && --depth === 0) break;
  }
  return src.slice(at, i + 1) + (prefix.startsWith('App.') ? ';' : '') + '\n';
}
function cnst(src, name) {
  const at = src.indexOf('const ' + name + ' =') >= 0 ? src.indexOf('const ' + name + ' =') : src.indexOf('const ' + name + '=');
  let i = src.indexOf('=', at) + 1, depth = 0;
  for (; i < src.length; i++) {
    const c = src[i];
    if ('[{('.includes(c)) depth++; else if (']})'.includes(c)) depth--;
    else if (c === ';' && depth === 0) break;
  }
  return src.slice(at, i + 1).replace(/^const /, 'var ') + '\n';
}
const constantsSrc = read('core/constants/001-constants.js');
const util = read('utils/006-util.js');
const v144 = read('components/category/049-v144-reusable-category-icon-color-palettes.js');
const v200 = read('components/cover/136-v200-category-default-missing-covers.js');
const v171 = read('components/category/073-v171-category-recovery-default-identity.js');
const v283 = read('components/217-v283-category-modal-sidebar-collection-card-fixes.js');
const v286 = read('components/220-v286-category-persistence-runtime-cache.js');
const v369 = read('components/267-v369-itemized-logging.js');
const v282 = read('components/216-v282-category-collections-stability.js');
const v369Patch = v369.slice(v369.indexOf('function v369ReadCategorySeconds'), v369.indexOf("const v369SettingsRenderer"));

const code = [
  cnst(constantsSrc, 'DEFAULT_CATEGORIES'), cnst(constantsSrc, 'COLOR_CHOICES'), cnst(constantsSrc, 'ICON_CHOICES'),
  fn(util, 'clamp'), fn(util, 'cleanTitle'),
  fn(v144, 'v144SafeIconUrl'), fn(v200, 'v200SafeCategoryCoverUrl'), fn(v200, 'v200CategoryMissingCoverUrl'),
  'function v74SyncCategoryOrder(){S.categoryOrder=(S.categories||[]).map(c=>c.id);return S.categoryOrder;}\n',
  'function persistCategories(){ v74SyncCategoryOrder(); S.settings=S.settings||{}; S.settings.categoryOrder=S.categoryOrder.slice(); return saveState(); }\n',
  fn(v171, 'v171Clone'), fn(v171, 'v171NormalizeCategoryRecovery'), fn(v171, 'v171EnsureCategoryState'),
  fn(v171, 'v171MissingDefaultCategories'), fn(v171, 'v171RestoreDefaultCategories', 'async function '), fn(v171, 'v171RestoreLastDeletedCategory', 'async function '),
  fn(v283, 'v283ReadCategoryForm'),
  v369Patch,
  fn(v286, 'v286InvalidateCategoryRuntimeCaches'),
  fn(v286, 'saveCategoryModal=function', 'App.'),
  fn(v283, 'confirmDeleteCategory=function', 'App.'),
  // v171's delete wrapper (the website loads v283 after it, so the slot is
  // never recorded there; the app records it so Restore works).
  'const v171Base=App.confirmDeleteCategory;App.confirmDeleteCategory=' + fn(v171, 'confirmDeleteCategory=async function', 'App.').replace(/^App\.confirmDeleteCategory=/, '').replace('v171ConfirmDeleteCategoryBase', 'v171Base'),
  fn(v282, 'v282Yield', 'async function '), fn(v282, 'v282ConfirmCategoryClear', 'async function '),
].join('');

async function run(state, actions) {
  const fields = {};
  const ctx = {
    console, JSON, Math, Number, String, Array, Object, Map, Set, Promise, URL, setTimeout,
    S: JSON.parse(JSON.stringify(state)), App: {}, __uid: 0, __now: 1762600000000,
  };
  ctx.Date = class extends Date { static now() { return ctx.__now; } };
  ctx.document = { getElementById: id => (id in fields ? { value: fields[id], checked: fields[id] === true, dataset: {} } : null) };
  vm.createContext(ctx);
  vm.runInContext(`function uid(){return 'u'+(++globalThis.__uid);} function saveState(){} function render(){} function renderModal(){}
    function showToast(t){globalThis.__toast=t;} function v283CloseModal(){} function v283RefreshAfterCategoryMutation(){}
    function getCategory(id){return S.categories.find(c=>String(c.id)===String(id))||null;}
    var V241_CATEGORY_REF,V241_CATEGORY_LEN,V241_CATEGORY_MAP; function v53InvalidateLibraryCache(){}
    ${code}`, ctx);
  const steps = [];
  for (const a of actions) {
    ctx.__now = a.at || ctx.__now;
    ctx.__toast = '';
    for (const k of Object.keys(fields)) delete fields[k];
    if (a.op === 'save') {
      Object.assign(fields, a.form);
      vm.runInContext(`App.saveCategoryModal(${JSON.stringify(a.id || '')},null)`, ctx);
    } else if (a.op === 'delete') {
      await vm.runInContext(`App.confirmDeleteCategory(${JSON.stringify(a.id)},null)`, ctx);
    } else if (a.op === 'restoreDeleted') {
      await vm.runInContext('v171RestoreLastDeletedCategory()', ctx);
    } else if (a.op === 'restoreDefaults') {
      await vm.runInContext('v171RestoreDefaultCategories()', ctx);
    } else if (a.op === 'clear') {
      await vm.runInContext(`v282ConfirmCategoryClear(${JSON.stringify(a.id)},null)`, ctx);
    }
    const S = ctx.S;
    steps.push({ toast: ctx.__toast, state: JSON.parse(JSON.stringify({
      categories: S.categories, categoryOrder: S.categoryOrder ?? null, settings: S.settings ?? null,
      categoryRecovery: S.categoryRecovery ?? null, library: S.library ?? null, activityLog: S.activityLog ?? null,
    })) });
  }
  return { constants: JSON.parse(JSON.stringify({ defaults: ctx.DEFAULT_CATEGORIES, colors: ctx.COLOR_CHOICES, icons: ctx.ICON_CHOICES })), steps };
}

const base = {
  categories: [
    { id: 'anime', name: 'Anime', icon: '🌸', type: 'video', unit: 'episodes', target: 4, weight: 4, minutesPerUnit: 24, color: '#FF5D9E', seasonal: true, enabled: true, custom: false, extra: 'kept' },
    { id: 'books', name: 'Books', icon: '📚', type: 'reading', unit: 'pages', target: 30, weight: 2, minutesPerUnit: 2, color: '#5AA9E6', enabled: true, custom: true, missingDefaultCoverUrl: 'https://x.example/b.png', missingDefaultCoverModifiedAt: 5 },
  ],
  settings: { theme: 'dark' },
  library: [{ id: 't1', title: 'A', categoryId: 'books' }, { id: 't2', title: 'B', categoryId: 'anime' }, { id: 't3', title: 'C', categoryId: 'books' }],
  activityLog: [],
};
const form = (o) => ({
  'm-name': 'Name', 'm-icon': '', 'm-icon-url': '', 'm-type': 'video', 'm-unit': 'episodes', 'm-target': '1', 'm-weight': '3',
  'm-mpu': '20', 'm-seasonal': false, 'm-color': '#e8607a', 'm-enabled': true, 'm-missing-default-cover': '',
  'm-runtime-hours': '0', 'm-runtime-minutes': '20', 'm-runtime-seconds': '0', ...o,
});
const scenarios = [
  {
    name: 'edit, new, runtime, icon link, cover link, clamps',
    actions: [
      { op: 'save', id: 'anime', at: 1762600001000, form: form({ 'm-name': '  Seasonal  ', 'm-icon': '🌸', 'm-type': 'video', 'm-target': '6', 'm-weight': '9', 'm-runtime-hours': '0', 'm-runtime-minutes': '23', 'm-runtime-seconds': '40', 'm-seasonal': true, 'm-color': '#ff5d9e' }) },
      { op: 'save', id: 'books', at: 1762600002000, form: form({ 'm-name': 'Books', 'm-icon-url': 'https://cdn.example/i.svg', 'm-type': 'reading', 'm-unit': 'pages', 'm-target': '0', 'm-weight': '', 'm-runtime-hours': '0', 'm-runtime-minutes': '0', 'm-runtime-seconds': '0', 'm-color': 'red', 'm-missing-default-cover': 'https://x.example/b.png', 'm-enabled': false }) },
      { op: 'save', id: 'books', at: 1762600003000, form: form({ 'm-name': '', 'm-icon': ' ', 'm-icon-url': 'javascript:alert(1)', 'm-missing-default-cover': 'https://y.example/c.png', 'm-runtime-hours': '1', 'm-runtime-minutes': '75', 'm-runtime-seconds': '-3' }) },
      { op: 'save', id: '', at: 1762600004000, form: form({ 'm-name': 'Podcasts', 'm-icon': '🎧', 'm-type': 'listening', 'm-unit': 'episodes', 'm-target': '2.5', 'm-weight': '2', 'm-color': '#abc', 'm-runtime-hours': '0', 'm-runtime-minutes': '45', 'm-runtime-seconds': '0' }) },
      { op: 'save', id: '', at: 1762600005000, form: form({ 'm-name': 'Bad', 'm-missing-default-cover': 'ftp://nope' }) },
    ],
  },
  {
    name: 'delete, restore, defaults, clear',
    actions: [
      { op: 'delete', id: 'anime', at: 1762600010000 },
      { op: 'restoreDeleted', at: 1762600011000 },
      { op: 'restoreDeleted', at: 1762600012000 },
      { op: 'delete', id: 'books', at: 1762600013000 },
      { op: 'restoreDefaults', at: 1762600014000 },
      { op: 'clear', id: 'anime', at: 1762600015000 },
      { op: 'clear', id: 'anime', at: 1762600016000 },
    ],
  },
];
const out = { base, scenarios: [] };
let constants;
for (const sc of scenarios) {
  const r = await run(base, sc.actions);
  constants = r.constants;
  out.scenarios.push({ ...sc, expected: r.steps });
}
out.constants = constants;
const here = path.dirname(new URL(import.meta.url).pathname);
fs.writeFileSync(path.join(here, '../../test/fixtures/category-golden.json'), JSON.stringify(out, null, 1) + '\n');
// Dart constants for the app.
const dart = `// GENERATED by tool/website_reference/generate_category_goldens.mjs from the
// website's core/constants (DEFAULT_CATEGORIES, COLOR_CHOICES, ICON_CHOICES).
// Do not edit by hand.

const kDefaultCategoriesJson = ${JSON.stringify(JSON.stringify(constants.defaults)).replace(/\$/g, '\\$')};
const kColorChoices = <String>${JSON.stringify(constants.colors)};
const kIconChoices = <String>${JSON.stringify(constants.icons)};
`;
fs.writeFileSync(path.join(here, '../../lib/src/logic/category_defaults.g.dart'), dart);
for (const sc of out.scenarios) console.log(sc.name, sc.expected.map(s => s.toast).join(' | '));
console.log(JSON.stringify(out.scenarios[0].expected[1].state.categories[1]));
console.log(JSON.stringify(out.scenarios[0].expected[3].state.categories[2]), out.scenarios[0].expected[3].state.categoryOrder);
