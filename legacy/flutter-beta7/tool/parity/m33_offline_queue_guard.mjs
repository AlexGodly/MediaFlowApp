import fs from 'node:fs';
import assert from 'node:assert/strict';
const repo=fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const store=fs.readFileSync('lib/services/native_m33_draft_store.dart','utf8');
const queue=fs.readFileSync('lib/services/native_m33_offline_queue.dart','utf8');
const coord=fs.readFileSync('lib/services/native_m33_draft_coordinator.dart','utf8');
const ui=fs.readFileSync('lib/features/settings/native_m33_offline_draft_panel.dart','utf8');
const flags=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
const docs=fs.readFileSync('docs/MILESTONE_33.md','utf8');
for(const method of ['keepOfflinePriorityDrafts','loadOfflineDraftQueue',
  'inspectOfflineDraftQueue','discardOfflineDraftQueue']) assert(repo.includes(method));
assert(repo.includes(".select('state_data,updated_at')"));
assert(!/\.upsert\(|\.insert\(|\.update\(|\.delete\(|\.rpc\(/.test(repo));
assert(store.includes('AesGcm.with256bits')&&store.includes('PlatformOfflineKeyVault'));
assert(store.includes('mediaflow-m33-device-drafts-aes256-v1'));
for(const keyword of ['mayUpload => false','missingOrDuplicateTitle',
  'unrelatedCloudChanges','titleConflict','needsManualCloudReview'])
  assert(queue.includes(keyword));
assert(!coord.includes('supabase_flutter'));
assert(ui.includes('Review against cloud')&&
  ui.includes('does not apply or upload changes'));
for(const flag of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false'])
  assert(flags.includes(flag));
assert(docs.includes('PARTIAL')&&docs.includes('not done'));
console.log('M33: encrypted owner-scoped device drafts, manual comparison only; production writes/replay disabled.');
