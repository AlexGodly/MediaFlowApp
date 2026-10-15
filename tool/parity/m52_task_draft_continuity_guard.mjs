import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=(p)=>fs.readFileSync(p,'utf8');
const model=read('lib/services/native_m52_task_draft_context.dart');
const card=read('lib/features/logging/native_m52_draft_context_panel.dart');
const logging=read('lib/features/logging/logging_screen.dart');
const standard=read('lib/features/library/native_editing_sheet.dart');
const itemized=read('lib/features/logging/native_itemized_draft_sheet.dart');
const tests=read('test/native_m52_task_draft_context_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
for(const [text,markers] of [
  [model,['class NativeM52TaskDraftContext',
    'NativeM51TaskHandoffView handoff','currentOwnerId!=ownerId',
    'identical(source,catalog)','forTitleId!=titleId',
    'workspace.ownerId!=ownerId','workspace.stale',
    'workspace?.logDraft(titleId)','workspace?.itemizedDraft(titleId)',
    'Existing itemized draft','No units or dates were prefilled']],
  [card,['m52-context-panel','m52-context-heading',
    'm52-draft-continuity','m52-existing-season','m52-no-autofill',
    'contextToken.inspect(']],
  [logging,['m52-logging-context-card','m52-reopen-task-review',
    'm52-clear-context','NativeM52TaskDraftContext.fromHandoff(',
    'm52-details-context','taskContext:taskContext',
    'NativeLogDraftSheet(','NativeItemizedDraftSheet(']],
  [standard,['NativeM52DraftContextPanel(','taskContext',
    'm52-context-panel'.replace('m52-context-panel','method:')]],
  [itemized,['NativeM52DraftContextPanel(','taskContext',
    "method:'itemized/season units'"]],
  [tests,['100k Library','both logging sheets','existing season draft',
    'Logging keeps task context','snapshot','timestamp']],
])for(const marker of markers){
  assert(text.includes(marker),'M52 continuity invariant missing: '+marker);
}
for(const source of [model,card,logging,standard,itemized]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(source),
    'M52 must not introduce any production cloud writes');
}
for(const key of ['cloudWritesEnabled = false','hasServerSideCas = false',
    'offlineWriteQueueEnabled = false']){
  assert(cloud.includes(key),'M52 must retain cloud gates: '+key);
}
console.log('M52 task context: owner- and snapshot-pinned and no draft autofill.');
