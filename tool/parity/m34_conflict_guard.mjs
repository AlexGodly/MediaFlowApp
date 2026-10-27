import assert from 'node:assert/strict';
import fs from 'node:fs';
const repo=fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const review=fs.readFileSync('lib/services/native_m34_conflict_review.dart','utf8');
const coordinator=fs.readFileSync('lib/services/native_m33_draft_coordinator.dart','utf8');
const store=fs.readFileSync('lib/services/native_m33_draft_store.dart','utf8');
const ui=fs.readFileSync('lib/features/settings/native_m34_conflict_center_panel.dart','utf8');
const flags=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const mark of ['reviewOfflineDraftConflicts','resolveOfflineDraftConflicts',
  'replaceForResolution',".select('state_data,updated_at')"]){
  assert(repo.includes(mark),'Missing M34 repository connection '+mark);
}
assert(!/\.upsert\(|\.insert\(|\.update\(|\.delete\(|\.rpc\(/.test(repo));
for(const mark of ['beforePriority','desiredPriority','cloudPriority',
  'changedElsewhere','alreadyDesired','missing','duplicated','queueDigest',
  'anchorChanged','mayUpload => false']){
  assert(review.includes(mark),'Incomplete M34 conflict report '+mark);
}
for(const mark of ['inspectDetailed','resolveDetailed','fetchFreshCloudRow',
  'cloudDigest(cloud)','recreateOperationIds','discardOperationIds',
  "'mixedManual'",'replaceStored!']){
  assert(coordinator.includes(mark),'Missing M34 safe manual action '+mark);
}
assert(store.includes('forgetPreviousOnReplace')&&
  store.includes('AesGcm.with256bits'));
for(const mark of ['Conflict Resolution Center','Review fresh cloud',
  'Before:','Your draft:','Cloud:','Confirm','No cloud updates']){
  assert(ui.includes(mark),'Missing M34 UI element '+mark);
}
for(const flag of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(flags.includes(flag),'A cloud-write gate changed: '+flag);
}
console.log('M34: user-confirmed local per-title conflict choices; no cloud mutation or automatic replay.');
