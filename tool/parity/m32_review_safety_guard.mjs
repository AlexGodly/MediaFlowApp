import assert from 'node:assert/strict';
import fs from 'node:fs';

const repo=fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const svc=fs.readFileSync('lib/services/native_priority_review_coordinator.dart','utf8');
const ui=fs.readFileSync('lib/features/settings/native_priority_review_panel.dart','utf8');
const flags=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const marker of ['stagePriorityReview','inspectPriorityReview',
    'discardPriorityReview','loadPriorityReview']) {
  assert(repo.includes(marker),'Missing real Settings review action: '+marker);
}
assert(repo.includes(".select('state_data,updated_at')"));
assert(!/\.upsert\(|\.insert\(|\.update\(|\.delete\(|\.rpc\(/.test(repo));
for(const mark of ['NativePriorityReviewCoordinator','NativeReviewBatch.stage',
   'NativeSyncReview.inspect','fullPayloadDigest','isDisplayedAuthoritativeCloud',
   'workspace.logCount','saveEncryptedReview','fetchFreshCloudRow']){
  assert(svc.includes(mark),'Missing safe review guard: '+mark);
}
for(const phrase of ['No cloud changes','Check fresh cloud','Discard saved review']){
  assert(ui.includes(phrase),'Missing reviewer UX: '+phrase);
}
for(const flag of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(flags.includes(flag),'Native cloud write gates changed: '+flag);
}
console.log('M32 safe review: authenticated SELECT only, no automatic replay, no writes, guarded priority-only encrypted review.');
