import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=(path)=>fs.readFileSync(path,'utf8');
const plan=read('lib/services/native_m44_personal_order_plan.dart');
const queue=read('lib/services/native_m42_mixed_queue.dart');
const panel=read('lib/features/personal_order/native_m42_mixed_queue_panel.dart');
const screen=read('lib/features/personal_order/personal_order_screen.dart');
const tests=read('test/native_m47_mixed_queue_edit_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
for(const [src,markers] of [
  [plan,['void positionMixedToken(','void moveMixedToken(',
    '_assertCategory(categoryId)','_validateDirectOrder();',
    'sourceIndexes.length!=directIds.length','_checkpoint();',
    '_titleIds=nextTitles','_queues[categoryId]=ordered',
    'mayUpload => false','void undo()','void redo()','void discard()']],
  [panel,['m47-up-','m47-down-','m47-position-',
    'm47-member-prev-','m47-member-next-','memberPageSize=20',
    'm47-undo','m47-redo','m47-discard',
    'm42-readonly-disclaimer','m47-edit-warning',
    'm43-focused-','NativeM43RecommendationAuditPanel']],
  [screen,['m47-edit-toggle','mixedEditMode',
    'plan:editingMixed ? plan : null','m44-preview-toggle',
    'm47-stale-warning']],
  [queue,['tokensForCategory(','seenRecommended',
    'recommendationSequence(']],
  [tests,['100k Library','Collection member pager',
    'direct crossing direct title','stale owner fail closed',
    'mixed editor stages Collection move']],
]) {
  for(const marker of markers)
    assert(src.includes(marker),'M47 invariant missing: '+marker);
}
for(const src of [plan,panel,screen,queue]) {
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(src),
    'M47 forbids account writes');
}
for(const marker of ['cloudWritesEnabled = false',
    'hasServerSideCas = false','offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker),'M47 forbidden production write gate: '+marker);
}
console.log('M47: atomic mixed queue editing, bounded members, no-cloud-write safety.');
