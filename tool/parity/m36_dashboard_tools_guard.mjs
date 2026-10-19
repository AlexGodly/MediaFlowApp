import assert from 'node:assert/strict';
import fs from 'node:fs';

const model=fs.readFileSync('lib/services/native_m36_dashboard_tools.dart','utf8');
const ui=fs.readFileSync('lib/features/dashboard/native_m36_dashboard_tools_panel.dart','utf8');
const dashboard=fs.readFileSync('lib/features/dashboard/dashboard_screen.dart','utf8');
const shell=fs.readFileSync('lib/app/mediaflow_shell.dart','utf8');
const repository=fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const flags=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const mark of ['NativeM36Stopwatch','NativeM36RuntimeCalculator',
  'previousTotal','continueResult','proposedLoggingMinutes',
  'NativeM36RuntimeMode.multi','Stopwatch()']){
  assert(model.includes(mark),'M36 calculator missing '+mark);
}
for(const mark of ['STOPWATCH','RUNTIME CALCULATOR','RATE YOUR LIBRARY',
  'MISSING COVERS','Continue with result','Previous total',
  'Skip suggestion','preview only']){
  assert(ui.includes(mark),'M36 dashboard interface missing '+mark);
}
assert(dashboard.includes('NativeM36DashboardToolsPanel('));
assert(shell.includes('dashboardTools.dispose()'));
assert(shell.includes('dashboardTools: dashboardTools'));
assert(!/\.upsert\(|\.insert\(|\.update\(|\.delete\(|\.rpc\(/.test(repository));
for(const mark of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(flags.includes(mark),'Production write gate changed');
}
console.log('M36: local-only stopwatch, v256 runtime math and read-only review queues; no cloud writes.');
