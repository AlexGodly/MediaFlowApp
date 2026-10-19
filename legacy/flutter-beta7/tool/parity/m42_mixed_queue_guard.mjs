import assert from 'node:assert/strict';
import fs from 'node:fs';
const model=fs.readFileSync('lib/data/mediaflow_models.dart','utf8');
const codec=fs.readFileSync('lib/data/mediaflow_state_codec.dart','utf8');
const repo=fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const library=fs.readFileSync('lib/services/native_m37_library_plan.dart','utf8');
const collections=fs.readFileSync('lib/services/native_m40_collection_plan.dart','utf8');
const service=fs.readFileSync('lib/services/native_m42_mixed_queue.dart','utf8');
const panel=fs.readFileSync('lib/features/personal_order/native_m42_mixed_queue_panel.dart','utf8');
const screen=fs.readFileSync('lib/features/personal_order/personal_order_screen.dart','utf8');
const tests=fs.readFileSync('test/native_m42_mixed_queue_test.dart','utf8');
const cloud=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const [src, markers] of [
  [model,['categoryQueues = const {}','createdAt = 0','final Map<String, List<String>> categoryQueues']],
  [codec,["orderPlan['categoryQueues']","categoryQueues: Map.unmodifiable"]],
  [repo,['categoryQueues: decoded.categoryQueues']],
  [library,['categoryQueues: source.categoryQueues']],
  [collections,['categoryQueues: base.categoryQueues','mayUpload => false']],
  [service,['class NativeM42MixedQueues','tokensForCategory(',
    'slotsForCategory(','recommendationSequence(','placementsForTitle(',
    'diagnosticsForCategory(','collectionPosition','seenRecommended']],
  [panel,['m42-collection-','m42-category','m42-queue-count',
    'm42-readonly-disclaimer','m42-mixed-queue-entries']],
  [screen,['NativeM42MixedQueuePanel','m42-mixed-mode','m42-direct-mode']],
  [tests,['50,000 Library titles','v287 Collection blocks remain ONE queue slot',
    'native UI switches between legacy direct and mixed queues']],
]) for(const marker of markers)
  assert(src.includes(marker),'M42 missing source/feature: '+marker);
for(const src of [service,panel,screen]) {
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(src),
    'M42 must not issue production writes');
}
for(const marker of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker),'M42 forbidden CAS/write toggle '+marker);
}
console.log('M42: read-only mixed queue and scoped ranks; production writes disabled.');
