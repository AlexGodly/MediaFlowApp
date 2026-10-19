import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(path, 'utf8');
const audit = read('lib/services/native_m54_transaction_readiness_audit.dart');
const panel = read('lib/features/logging/native_m53_completion_evidence_panel.dart');
const tests = read('test/native_m54_transaction_readiness_audit_test.dart');
const cloud = read('lib/services/native_cas_protocol.dart');
const shared = read('lib/services/native_m30_shared_sync.dart');

for (const marker of [
  'class NativeM54TransactionAudit',
  'NativeM54AuditStatus.invalidContext',
  'NativeM54AuditStatus.categoryMismatch',
  'NativeM54Prerequisite.ownerAndSnapshot',
  'NativeM54Prerequisite.completeDraft',
  'NativeM54Prerequisite.targetMid',
  'NativeM54Prerequisite.categoryGroupedHistory',
  'NativeM54Prerequisite.runtimeAndItemizedTimestamps',
  'NativeM54Prerequisite.experienceAndRespect',
  'NativeM54Prerequisite.libraryAndCompletionTimeline',
  'NativeM54Prerequisite.collectionTraversal',
  'NativeM54Prerequisite.nextTaskGeneration',
  'NativeM54Prerequisite.atomicAccountCommit',
  'mightSkipRecommendation',
  'assignment.traversedTitleIds.contains(titleId)',
  'NativeCloudCapabilities.cloudWritesEnabled',
  'NativeM30Protocol.deployed',
  'bool get canCommit => false',
  'bool get readyForProduction => false',
  'bool get confirmedTaskCompleted => false',
]) assert(audit.includes(marker), 'Missing M54 invariant: ' + marker);

for (const marker of [
  'NativeM54TransactionAudit.inspect(',
  'm54-readiness-',
  'm54-blockers-',
  'm54-no-write-',
  'm54-skip-',
  'Transaction readiness',
]) assert(panel.includes(marker), 'M54 panel missing: ' + marker);

for (const marker of [
  'all ten v410 side-effect prerequisites',
  'Force Queue foreign category',
  'Collection source membership',
  'snapshot replacements and duplicate IDs',
  'repeat consumption',
  '100k Library',
  'm54-readiness-saved',
]) assert(tests.includes(marker), 'M54 test missing: ' + marker);

for (const [name, source] of [
  ['audit', audit], ['panel', panel], ['tests', tests],
]) {
  assert(!/\.upsert\s*\(|\.rpc\s*\(|\.insert\s*\(|\.update\s*\(|\.from\(\s*['"]mediaflow_states/.test(source),
    'Unexpected production write API in M54 ' + name);
}
for (const marker of [
  'cloudWritesEnabled = false',
  'hasServerSideCas = false',
  'offlineWriteQueueEnabled = false',
]) assert(cloud.includes(marker), 'Cloud safety gate changed: ' + marker);
assert(shared.includes('static const bool deployed = false'),
  'Website/native shared protocol must remain undeployed');
console.log('M54 source-backed readiness checks and no-write gates retained.');
