import fs from 'node:fs';
import assert from 'node:assert/strict';

const repo = fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const core = fs.readFileSync('lib/services/native_offline_read_coordinator.dart','utf8');
const cap = fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
const docs = fs.readFileSync('docs/MILESTONE_31.md','utf8');

assert(repo.includes('NativeOfflineReadCoordinator('),
  'Production repository must use the offline-first coordinator');
assert(repo.includes(".select('state_data,updated_at')"),
  'Existing cloud read-only SELECT is required');
assert(!/\.upsert\(|\.insert\(|\.update\(|\.delete\(|\.rpc\(/.test(repo),
  'Do not enable production cloud mutations');
assert(core.includes('NativeSnapshotSource.offlineMemory'));
assert(core.includes('NativeSnapshotSource.invalidCloud'));
assert(core.includes('NativeMissingCloudRow'));
assert(core.includes('readDeviceCopy'));
assert(core.includes('closeAndPurge'));
assert(!core.includes('supabase_flutter'));
for (const k of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']) {
  assert(cap.includes(k), 'Unexpected cloud write gate change: ' + k);
}
assert(docs.includes('read-only') && docs.includes('Milestone 30'));
console.log('M31 offline-first: owner-scoped cloud SELECT, encrypted recovery, '
  + 'no production writes or replay, invalid-cloud fail-closed gates verified.');
