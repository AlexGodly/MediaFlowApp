import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=path=>fs.readFileSync(path,'utf8');
const dashboard=read('lib/features/dashboard/dashboard_screen.dart');
const hero=read('lib/features/dashboard/native_m50_dashboard_task_hero.dart');
const display=read('lib/services/native_m50_task_display.dart');
const evidence=read('lib/features/dashboard/native_m49_dashboard_evidence_panel.dart');
const tests=read('test/native_m50_dashboard_task_hero_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
for(const [source,markers] of [
  [dashboard,['NativeM50DashboardTaskHero(','NativeM49DashboardEvidencePanel(',
    'NativeM36DashboardToolsPanel(','openHistory']],
  [hero,['m50-task-hero','m50-compact-layout','m50-wide-layout',
    'm50-task-poster','m50-task-progress','m50-readonly-note',
    'm50-open-personal-order','m50-browse-library','m49-task-id-label',
    'm50-task-source-claim','bounds.maxWidth>=620','Image.network(']],
  [display,['NativeM50TitleResolution.ambiguousId',
    'NativeM50TitleResolution.missingId','NativeM50TitleResolution.missingTitle',
    'catalog.sessionActive','candidate.id!=task.libraryId',
    "uri.scheme!='https'","uri.userInfo.isNotEmpty",
    'total.isFinite','progress.isFinite','clamp(0.0,1.0)']],
  [evidence,['m49-dashboard-evidence','m49-saved-first']],
  [tests,['320px/360px','wide desktop','unrelated covers','live Dashboard',
    'only an exact, unique Library ID']],
])for(const marker of markers){
  assert(source.includes(marker),'M50 invariant missing: '+marker);
}
for(const source of [dashboard,hero,display]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(source),
    'M50 task presentation must remain read-only');
}
for(const marker of ['cloudWritesEnabled = false',
    'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(cloud.includes(marker),'Cloud gate was changed: '+marker);
}
console.log('M50: responsive task presentation, safe exact-ID cover, no cloud mutations.');
