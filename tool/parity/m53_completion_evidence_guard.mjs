import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=(p)=>fs.readFileSync(p,'utf8');
const svc=read('lib/services/native_m53_task_completion_evidence.dart');
const card=read('lib/features/logging/native_m53_completion_evidence_panel.dart');
const ctx=read('lib/features/logging/native_m52_draft_context_panel.dart');
const std=read('lib/features/library/native_editing_sheet.dart');
const unit=read('lib/features/logging/native_itemized_draft_sheet.dart');
const tests=read('test/native_m53_task_completion_evidence_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
for(const [source,markers] of [
  [svc,['NativeM53EvidenceStatus.differentCategory',
    'NativeM53EvidenceStatus.withinBand',
    'NativeM53EvidenceStatus.belowBand',
    'NativeM53EvidenceStatus.aboveBand',
    'NativeM53EvidenceStatus.unknownTarget',
    'NativeM53EvidenceSource.standardPreview',
    'NativeM53EvidenceSource.itemizedPreview',
    'title.categoryId!=task.categoryId',
    'targetMid','confirmedTaskCompleted=>false',
    'canSubmit=>false','canAdvanceCollection=>false',
    'canAwardRespect=>false','confirmedXp=>null']],
  [card,['m53-evidence-','m53-status-',
    'm53-band-progress-','m53-no-commit-',
    'NativeM53TaskCompletionEvidence.evaluate(']],
  [ctx,['NativeM53CompletionEvidencePanel(',
    'showCompletionEvidence']],
  [std,['NativeM53CompletionEvidencePanel(',
    'standardPreview:hypothetical',"variant:'live-standard'"]],
  [unit,['NativeM53CompletionEvidencePanel(',
    'itemizedPreview:preview',"variant:'live-itemized'"]],
  [tests,['100k Library','Force Queue',
    'unknown or inconsistent','repeat consumption',
    'itemized counts selected','task band','standard and itemized live']],
])for(const marker of markers){
  assert(source.includes(marker),'M53 guard missing '+marker);
}
for(const source of [svc,card,ctx,std,unit]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(source),
    'No account writes are permitted in M53');
}
for(const key of ['cloudWritesEnabled = false',
    'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(cloud.includes(key),'M53 cannot enable '+key);
}
console.log('M53: v410 targetMid is unavailable; comparisons are evidence-only.');
