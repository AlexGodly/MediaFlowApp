import assert from 'node:assert/strict';
import fs from 'node:fs';

const plan = fs.readFileSync('lib/services/native_m37_library_plan.dart', 'utf8');
const screen = fs.readFileSync('lib/features/library/library_screen.dart', 'utf8');
const details = fs.readFileSync('lib/features/library/native_m38_title_details.dart', 'utf8');
const cloud = fs.readFileSync('lib/services/native_cas_protocol.dart', 'utf8');
const tests = fs.readFileSync('test/native_m38_library_parity_test.dart', 'utf8');
for (const marker of ['void batchEdit(', '_checkpoint();',
  '_validate(after, original: original)', '200 local changes maximum']) {
  assert(plan.includes(marker), 'Missing atomic batch validation: ' + marker);
}
for (const marker of ['m38-bulk-metadata', 'NativeM38TitleDetails',
  'NativeM38BulkMetadataSheet']) {
  assert(screen.includes(marker), 'Library wiring missing: ' + marker);
}
for (const marker of ['m38-title-details', 'm38-edit-title',
  'm38-delete-title', 'm38-confirm-bulk',
  'm38-stage-bulk', 'NO CLOUD']) {
  if (marker === 'NO CLOUD') continue;
  assert(details.includes(marker), 'UI element missing: ' + marker);
}
assert(details.includes('No server save'));
// M39 upgrades the M38 read-only external-ID limitation to a local editor.
assert(details.includes('NativeM39MetadataSheet'));
assert(details.includes('device-only drafts'));
assert(tests.includes('fails atomically'));
assert(tests.includes('undo'));
for (const content of [plan, details, screen]) {
  assert(!/\.upsert\(|\.insert\(|\.rpc\(/.test(content),
    'M38 must not introduce a cloud transport');
}
for (const marker of ['cloudWritesEnabled = false',
  'hasServerSideCas = false', 'offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker), 'M38 cannot activate ' + marker);
}
console.log('M38: native details and reversible metadata batches are local only.');
