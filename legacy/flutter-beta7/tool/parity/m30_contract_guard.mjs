import fs from 'node:fs';
import assert from 'node:assert/strict';

// This is a static local guard, not an API authorization or deployment check.
const source=fs.readFileSync('lib/services/native_m30_shared_sync.dart','utf8');
const caps=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
const docs=fs.readFileSync('docs/MILESTONE_30.md','utf8');
const tests=fs.readFileSync('test/native_m30_shared_sync_test.dart','utf8');
assert(source.includes("version = 'mediaflow-shared-sync-v1-review-only'"));
assert(source.includes('static const bool deployed = false'));
assert(source.includes('NativeM30SimulatedSharedServer'));
assert(source.includes('NativeM30Result.legacyWriteBlocked'));
assert(source.includes('expectedRevision')&&source.includes('expectedDigest'));
assert(source.includes('operationId')&&source.includes('fingerprint'));
assert(!source.includes("supabase_flutter")&&!source.includes(".from('mediaflow_states')"));
for (const phrase of ['cloudWritesEnabled = false',
  'hasServerSideCas = false', 'offlineWriteQueueEnabled = false']) {
  assert(caps.includes(phrase),'Native write gate changed: '+phrase);
}
for (const term of ['website','Android','Windows','UPSERT','RLS',
  'idempotency','backup','rollback','revision']) {
  assert(docs.toLowerCase().includes(term.toLowerCase()),
    'Missing coordinated migration rule: '+term);
}
assert(tests.includes('web then Android'));
assert(tests.includes('retry after lost response'));
assert(tests.includes('1000 sequential'));
console.log('M30 contract gate: no transport, no production writes, '
  +'cross-writer migration, idempotency and conflict tests present.');
