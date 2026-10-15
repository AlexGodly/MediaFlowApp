import assert from 'node:assert/strict';
import fs from 'node:fs';
const plan=fs.readFileSync('lib/services/native_m44_personal_order_plan.dart','utf8');
const planner=fs.readFileSync('lib/features/personal_order/native_m44_assignment_planner.dart','utf8');
const screen=fs.readFileSync('lib/features/personal_order/personal_order_screen.dart','utf8');
const shell=fs.readFileSync('lib/app/mediaflow_shell.dart','utf8');
const tests=fs.readFileSync('test/native_m44_personal_order_plan_test.dart','utf8');
const cloud=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const [source,markers] of [
  [plan,['class NativeM44PersonalOrderPlan extends ChangeNotifier',
    'bool get mayUpload => false','void observe(',
    'currentOwnerId!=ownerId','_stale=true','_checkpoint()',
    'void undo()','void redo()','void discard()',
    'String addCollection(','void setRules(','void setPosition(',
    'void move(','void resetTraversal(','void remove(',
    'MediaFlowCatalog previewCatalog(','Maximum 200 staged']],
  [planner,['class NativeM44AssignmentPlanner',
    'm44-plan','m44-undo','m44-redo','m44-discard',
    'm44-add-assignment','m44-picker-search',
    'm44-set-position-','m44-remove-',
    'm44-reset-','m44-preview','_confirm(']],
  [screen,['m44-plan-mode','m44-preview-toggle',
    'NativeM44AssignmentPlanner','plan?.observe(data,currentOwnerId:',
    'plan.hasChanges && plan.canEdit','NativeM42MixedQueuePanel']],
  [shell,['NativeM44PersonalOrderPlan','personalOrderPlan?.dispose()',
    'plan: personalOrderPlan','currentOwnerId: preferenceUserId']],
  [tests,['stale source quarantines edits','owner switch fails closed',
    'mixed queue moves preserve direct relative slots',
    'local assignment picker, undo and preview',
    'for(var i=0;i<50000;i++)']],
]) {
  for(const marker of markers) {
    assert(source.includes(marker),'M44 missing guard marker: '+marker);
  }
}
for(const source of [plan,planner,screen]) {
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(source),
    'M44 new code must never write cloud account state');
}
for(const marker of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker),'M44 dangerous cloud write change: '+marker);
}
console.log('M44: owner-pinned, reversible, RAM-only Personal Order planner; cloud writes disabled.');
