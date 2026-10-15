import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=path=>fs.readFileSync(path,'utf8');
const model=read('lib/services/native_m51_task_handoff.dart');
const hero=read('lib/features/dashboard/native_m50_dashboard_task_hero.dart');
const dashboard=read('lib/features/dashboard/dashboard_screen.dart');
const logging=read('lib/features/logging/logging_screen.dart');
const shell=read('lib/app/mediaflow_shell.dart');
const tests=read('test/native_m51_task_handoff_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
for(const [content,markers] of [
  [model,['class NativeM51TaskHandoff','ownerId!=currentOwnerId',
    'identical(catalog,_source)','NativeM50TitleResolution.exact',
    'missingOrAmbiguousTitle','request(MediaFlowCatalog',
    'void dismiss()','notifyListeners()']],
  [hero,['m51-review-in-logging','NativeM50TitleResolution.exact',
    'onReviewTaskInLogging']],
  [dashboard,['onReviewTaskInLogging','NativeM50DashboardTaskHero(']],
  [logging,['m51-handoff-card','m51-handoff-status',
    'm51-review-task-title','m51-dismiss-handoff',
    'controller.inspect(catalog','_details(context,handoff.title!,catalog)',
    'm51-existing-drafts','m51-handoff-warning']],
  [shell,['NativeM51TaskHandoff','taskHandoff!.request',
    'navigate(MediaFlowSection.logging)','taskHandoff:taskHandoff',
    'currentOwnerId:preferenceUserId']],
  [tests,['100k Library stress','replaced snapshot',
    'handoff preserves existing local logging',
    'Dashboard handoff navigates to Logging review',
    'stale source does not select']],
])for(const m of markers)assert(content.includes(m),
  'M51 handoff invariant missing: '+m);
for(const content of [model,hero,dashboard,logging,shell]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(content),
    'M51 must never write account state');
}
for(const m of ['cloudWritesEnabled = false',
    'hasServerSideCas = false','offlineWriteQueueEnabled = false'])
  assert(cloud.includes(m),'M51 modified no-write contract '+m);
console.log('M51: owner-pinned, snapshot-pinned review-only Logging handoff.');
