import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=(name)=>fs.readFileSync(name,'utf8');
const model=read('lib/data/mediaflow_models.dart');
const service=read('lib/services/native_m49_dashboard_task_audit.dart');
const panel=read('lib/features/dashboard/native_m49_dashboard_evidence_panel.dart');
const screen=read('lib/features/dashboard/dashboard_screen.dart');
const shell=read('lib/app/mediaflow_shell.dart');
const tests=read('test/native_m49_dashboard_task_evidence_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
for(const [source,markers] of [
  [model,['class MediaFlowTaskOrderSource','final String libraryId',
    "data['libraryId']","data['v287OrderSource']"]],
  [service,['NativeM49TaskEvidenceStatus',
    'confirmedQueueSource','queueMatchUnverified','sourceConflict',
    'ambiguousLibraryId','missingLibraryId','notInQueue',
    'currentMatch','occurrence==null','annotation.libraryId==id',
    'annotation.categoryId==category','annotation.assignmentId==occurrence.assignmentId',
    'coordinator.preview(','catalog.sessionActive']],
  [panel,['m49-dashboard-evidence','m49-task-rank',
    'm49-status','m49-explanation','m49-saved-first',
    'm49-draft-first','m49-draft-difference',
    'm49-exclusions','m49-open-order','m49-readonly-warning',
    'identical(plan.source,widget.catalog)','expanded?[_details(context)]']],
  [screen,['NativeM49DashboardEvidencePanel(',
    'm49-task-id-label','personalOrderPlan','openPersonalOrder']],
  [shell,['personalOrderPlan: personalOrderPlan',
    'openPersonalOrder: () => navigate(MediaFlowSection.personalOrder)']],
  [tests,['100k titles','duplicate Library IDs',
    'saved annotation and queue source','source mismatches',
    'Dashboard displays saved vs local draft']],
])for(const marker of markers){
  assert(source.includes(marker),'M49 evidence invariant missing: '+marker);
}
for(const source of [model,service,panel,screen,shell]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(source),
    'M49 cannot write production account state');
}
for(const marker of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(cloud.includes(marker),'M49 cloud-write gate violation: '+marker);
}
console.log('M49: exact task-source evidence, lazy Dashboard preview, local-only safety.');
