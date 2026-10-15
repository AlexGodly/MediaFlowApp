import assert from 'node:assert/strict';
import fs from 'node:fs';
const load=(path)=>fs.readFileSync(path,'utf8');
const model=load('lib/services/native_m48_task_coordination.dart');
const panel=load('lib/features/personal_order/native_m48_task_coordination_panel.dart');
const mixed=load('lib/features/personal_order/native_m42_mixed_queue_panel.dart');
const screen=load('lib/features/personal_order/personal_order_screen.dart');
const tests=load('test/native_m48_task_coordination_test.dart');
const cloud=load('lib/services/native_cas_protocol.dart');
const reference=load('lib/services/native_m43_recommendation_audit.dart');
for(const [src,markers] of [
  [model,['class NativeM48TaskCoordination',
    'NativeM48PriorityPolicy.enabled','NativeM48PriorityPolicy.disabled',
    'NativeM48PriorityPolicy.unknown',
    'excludedIds','currentTaskMatchesCategory',
    'afterSuccessfulCollectionConsumption',
    'wouldAdvanceCollection','List.unmodifiable',
    'MediaFlowCatalog(','traversedTitleIds:List.unmodifiable']],
  [panel,['m48-task-coordination','m48-priority-state',
    'm48-exclusion-input','m48-first-candidate',
    'm48-fallback','m48-simulate-switch',
    'm48-next-candidate','m48-saved-first','m48-local-first']],
  [mixed,['NativeM48TaskCoordinationPanel','savedCatalog',
    'm42-readonly-disclaimer','m43-focused-']],
  [screen,['savedCatalog:showLocalPreview ? data : null',
    'plan:editingMixed ? plan : null']],
  [reference,['NativeM43RecommendationAudit','recommendations']],
  [tests,['priority tri-state','hypothetical exclusions',
    'successful Collection consumption','100k Library',
    'local draft queue','UI shows policy']],
]) {
  for(const marker of markers)
    assert(src.includes(marker),'M48 parity invariant missing: '+marker);
}
for(const src of [model,panel,mixed,screen]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(src),
    'M48 must not issue production writes');
}
for(const marker of ['cloudWritesEnabled = false',
    'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(cloud.includes(marker),'M48 forbidden cloud-write setting '+marker);
}
console.log('M48: queue/task preview is read-only and production writes remain off.');
