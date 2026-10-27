import fs from 'node:fs';
import assert from 'node:assert/strict';

const contract = JSON.parse(fs.readFileSync(
  'docs/parity/v410_settings_data_contract.json', 'utf8'));
const fixture = JSON.parse(fs.readFileSync(
  'test/fixtures/m28_v410_lossless_sample.json', 'utf8'));

assert.equal(contract.baseline, 'MediaFlow v410');
assert.equal(contract.defaultSettings.length, 38);
assert.equal(contract.stateRoots.length, 30);
for (const entry of contract.defaultSettings) {
  assert(Object.hasOwn(fixture.settings, entry.key),
    'Missing default settings preservation vector: '+entry.key);
}
for (const key of ['library','categories','sessions','settings',
  'xpLedger','completionTimeline','activityLog','orderPlan',
  'collections','stopwatch','currentTask','categoryOrder']) {
  assert(Object.hasOwn(fixture,key), 'Missing important source root: '+key);
}
assert(fixture.library[0].seasons[0].futureSeason);
assert(fixture.sessions[0].titles[0].v369Units[0].unknownUnit);
assert(fixture.settings.leveling.futureLedgerConfig);
assert(fixture.v410UnknownRoot);
assert(fixture.orderPlan.unknownQueue);
const read = fs.readFileSync('lib/data/mediaflow_full_state.dart','utf8');
assert(read.includes('class MediaFlowFullState'));
assert(read.includes('encodeForLocalParityTest'));
assert(read.includes('simulateScalarReplacement'));
assert(!read.includes('.from(\'mediaflow_states\')'),
  'M28 lossless layer must not access network');
const cap = fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for (const line of ['cloudWritesEnabled = false',
    'hasServerSideCas = false','offlineWriteQueueEnabled = false']) {
  assert(cap.includes(line), 'Native write gate unexpectedly changed: '+line);
}
console.log('M28 contract guard: 38 settings, 30 root candidates, '
  + 'synthetic nested preservation vectors and cloud safety gate OK.');
