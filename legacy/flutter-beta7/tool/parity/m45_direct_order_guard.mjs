import assert from 'node:assert/strict';
import fs from 'node:fs';
const plan=fs.readFileSync('lib/services/native_m44_personal_order_plan.dart','utf8');
const ui=fs.readFileSync('lib/features/personal_order/native_m45_direct_title_planner.dart','utf8');
const screen=fs.readFileSync('lib/features/personal_order/personal_order_screen.dart','utf8');
const m44=fs.readFileSync('tool/parity/m44_personal_order_plan_guard.mjs','utf8');
const tests=fs.readFileSync('test/native_m45_direct_title_plan_test.dart','utf8');
const cloud=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const [src,markers] of [
  [plan,['_M44Checkpoint(','entry.titleIds','_titleIds',
    'listEquals(base.personalOrderIds,_titleIds)',
    'List<String> get directTitleIds','browseDirectTitlePicker(',
    'void addDirectTitles(','void removeDirectTitles(',
    'void positionDirectTitle(','void moveDirectTitle(',
    'Maximum 200 staged Personal Order changes','bool get mayUpload => false',
    'currentOwnerId!=ownerId','void undo()','void redo()','void discard()']],
  [ui,['class NativeM45DirectTitlePlanner',
    'm45-ordered-tab','m45-available-tab','m45-category-filter',
    'm45-select-visible','m45-apply-bulk','m45-confirm-bulk',
    'm45-position-','m45-undo','m45-redo','m45-discard','m45-preview']],
  [screen,['m45-plan-mode','directPlanMode',
    'NativeM45DirectTitlePlanner','m44-preview-toggle']],
  [tests,['100,000 title source','category-only reorder',
    'interleaved assignment/title operations','stale snapshot and owner',
    'UI confirmed bulk remove']],
  [m44,['owner-pinned','M44']],
])for(const marker of markers)
  assert(src.includes(marker),'M45 missing invariant '+marker);
for(const src of [plan,ui,screen]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(src),
    'M45 cannot write cloud data');
}
for(const marker of ['cloudWritesEnabled = false','hasServerSideCas = false',
  'offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker),'M45 illegal cloud write gate '+marker);
}
console.log('M45: source-pinned direct Personal Order draft + bulk undo safe; writes remain disabled.');
