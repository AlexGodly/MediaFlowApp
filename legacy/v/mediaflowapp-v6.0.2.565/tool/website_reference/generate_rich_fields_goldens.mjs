// test/fixtures/rich-fields-golden.json: the website's title editor "rich
// metadata" fields (v178 capture + apply, v176 text/date cleaning) for
// sample edits, including which fields become MANUAL.
//   node tool/website_reference/generate_rich_fields_goldens.mjs <website checkout>
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const site = process.argv[2];
const read = f => fs.readFileSync(path.join(site, 'src/js', f), 'utf8');
function fn(src, name) {
  const at = src.indexOf('function ' + name + '(');
  if (at < 0) throw new Error(name);
  let i = src.indexOf('{', src.indexOf(')', at)), depth = 0, q = null;
  for (; i < src.length; i++) {
    const c = src[i];
    if (q) { if (c === '\\') { i++; continue; } if (c === q) q = null; continue; }
    if (c === '/' && src[i + 1] === '/' && src[i - 1] !== ':' && src[i - 1] !== '\\') { i = src.indexOf('\n', i); continue; }
    if (c === '"' || c === "'" || c === '`') { q = c; continue; }
    if (c === '{') depth++; else if (c === '}' && --depth === 0) break;
  }
  return src.slice(at, i + 1) + '\n';
}
const v176 = read('pages/library/085-v176-dense-library-rows-rich-imported-metadata.js');
const v178 = read('legacy/093-v178-editable-rich-imported-metadata.js');
const ed = read('pages/library/094-add-rich-fields-to-the-normal-library-editor.js');
const fields = v178.slice(v178.indexOf('const V178_EDITABLE_RICH_FIELDS'), v178.indexOf('];', v178.indexOf('const V178_EDITABLE_RICH_FIELDS')) + 2);
const code = [fields, fn(v176, 'v176SafeText'), fn(v176, 'v176DateValue'), fn(v178, 'v178ManualMap'), fn(v178, 'v178CommaText'), fn(v178, 'v178CsvList'),
  fn(ed, 'v178CaptureEditorValues'), fn(ed, 'v178ComparableRichValue'), fn(ed, 'v178ApplyManualEditorValues')].join('');

const inputs = (o) => ({
  'l-rich-year': '', 'l-rich-format': '', 'l-rich-duration': '', 'l-rich-release-date': '', 'l-rich-season': '', 'l-rich-age-rating': '',
  'l-rich-community-score': '', 'l-rich-source': '', 'l-rich-demographic': '', 'l-rich-studios': '', 'l-rich-producers': '',
  'l-rich-genres': '', 'l-rich-themes': '', 'l-rich-synopsis': '', ...o,
});
const before = {
  id: 't1', title: 'Frieren', year: 2023, mediaFormat: 'TV', durationMinutes: 24, releaseDate: '2023-09-29', seasonLabel: 'Fall 2023',
  ageRating: 'PG-13', communityScore: 9.1, mediaSource: 'Manga', demographic: 'Shounen', studios: ['Madhouse'], producers: [],
  genres: ['Adventure', 'Drama'], themes: [], synopsis: 'An elf mage.', richMetadataManual: { genres: true, coverUrl: true, bogus: 'yes' }, modifiedAt: 5,
};
const blank = { id: 't2', title: 'New' };
const cases = [
  { name: 'unchanged', item: before, inputs: inputs({ 'l-rich-year': '2023', 'l-rich-format': 'TV', 'l-rich-duration': '24', 'l-rich-release-date': '2023-09-29',
    'l-rich-season': 'Fall 2023', 'l-rich-age-rating': 'PG-13', 'l-rich-community-score': '9.1', 'l-rich-source': 'Manga', 'l-rich-demographic': 'Shounen',
    'l-rich-studios': 'Madhouse', 'l-rich-genres': 'Adventure, Drama', 'l-rich-synopsis': 'An elf mage.' }) },
  { name: 'edits and cleaning', item: before, inputs: inputs({ 'l-rich-year': '12023', 'l-rich-format': '  <b>TV</b>  Series ', 'l-rich-duration': '-5',
    'l-rich-release-date': 'aired 2023-09-29 (JP)', 'l-rich-season': 'Fall 2023', 'l-rich-age-rating': '', 'l-rich-community-score': '87', 'l-rich-source': 'Manga',
    'l-rich-demographic': 'Shounen', 'l-rich-studios': 'Madhouse, , Madhouse, Studio&nbsp;X', 'l-rich-producers': 'Aniplex',
    'l-rich-genres': 'Adventure, Drama, Fantasy', 'l-rich-themes': 'x'.repeat(130), 'l-rich-synopsis': 'Line<br>two' }) },
  { name: 'new title', item: blank, inputs: inputs({ 'l-rich-year': '1999', 'l-rich-genres': 'Action', 'l-rich-community-score': 'abc', 'l-rich-release-date': '1999-04-03T00:00:00Z' }) },
  { name: 'cleared', item: before, inputs: inputs({}) },
];
const out = [];
for (const c of cases) {
  const ctx = { __now: 1762600000000 };
  ctx.Date = class extends Date { static now() { return ctx.__now; } };
  ctx.document = { getElementById: id => (id in c.inputs ? { value: c.inputs[id] } : null) };
  vm.createContext(ctx);
  vm.runInContext(code + `globalThis.api={capture:v178CaptureEditorValues,apply:v178ApplyManualEditorValues};`, ctx);
  const captured = ctx.api.capture();
  const item = JSON.parse(JSON.stringify(c.item));
  const changed = ctx.api.apply(item, JSON.parse(JSON.stringify(c.item)), captured);
  out.push({ ...c, expected: { captured: JSON.parse(JSON.stringify(captured)), changed, item: JSON.parse(JSON.stringify(item)) } });
}
const here = path.dirname(new URL(import.meta.url).pathname);
fs.writeFileSync(path.join(here, '../../test/fixtures/rich-fields-golden.json'), JSON.stringify({ fields: vm.runInNewContext(fields + ';V178_EDITABLE_RICH_FIELDS'), cases: out }, null, 1) + '\n');
console.log(JSON.stringify(out[1].expected.item));
console.log(JSON.stringify(out[2].expected.item));
