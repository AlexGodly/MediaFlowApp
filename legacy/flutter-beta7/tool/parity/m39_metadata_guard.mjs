import assert from 'node:assert/strict';
import fs from 'node:fs';
const m = fs.readFileSync('lib/services/native_m39_metadata.dart','utf8');
const raw = fs.readFileSync('lib/data/mediaflow_full_state.dart','utf8');
const fields = fs.readFileSync('lib/services/native_m37_library_plan.dart','utf8');
const ui = fs.readFileSync('lib/features/library/native_m39_metadata_sheet.dart','utf8');
const details = fs.readFileSync('lib/features/library/native_m38_title_details.dart','utf8');
const cloud = fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
const tests = fs.readFileSync('test/native_m39_metadata_test.dart','utf8');
for (const marker of ['v377', 'validId', 'applyIdChanges',
  'validateSeasons','aggregate','sameSeasons']) {
  assert(m.includes(marker),'M39 source parity contract missing '+marker);
}
for (const marker of ['simulateTitleMetadata',
  'NativeSnapshotCodec.equivalent(restored,_state)',
  'v377ManualExternalIds', 'future']) {
  if (marker === 'future') continue;
  assert(raw.includes(marker), 'M39 lossless simulation missing '+marker);
}
for (const marker of ['void editM39(', 'seasons: before.seasons',
  'manualExternalIds: before.manualExternalIds']) {
  assert(fields.includes(marker),'M39 local planner missing '+marker);
}
assert(ui.includes('LOCAL PREVIEW ONLY'));
assert(ui.includes('m39-stage-metadata'));
assert(details.includes('m39-edit-metadata'));
assert(tests.includes('unknown nested metadata'));
for (const content of [ui,fields,raw,m]) {
  assert(!/\.upsert\(|\.insert\(|\.rpc\(/.test(content),
    'M39 may not add account write transport');
}
for (const marker of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker),'Unsafe cloud toggle '+marker);
}
console.log('M39: v377 IDs, v252 seasons and local-only lossless metadata simulation.');
