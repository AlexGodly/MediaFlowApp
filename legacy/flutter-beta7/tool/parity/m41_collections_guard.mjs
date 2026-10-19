import assert from 'node:assert/strict';
import fs from 'node:fs';
const model=fs.readFileSync('lib/data/mediaflow_models.dart','utf8');
const codec=fs.readFileSync('lib/data/mediaflow_state_codec.dart','utf8');
const repo=fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const preview=fs.readFileSync('lib/services/native_m40_collection_plan.dart','utf8');
const logic=fs.readFileSync('lib/services/native_m41_collection_browser.dart','utf8');
const ui=fs.readFileSync('lib/features/collections/native_m41_collection_browser.dart','utf8');
const screen=fs.readFileSync('lib/features/collections/collections_screen.dart','utf8');
const tests=fs.readFileSync('test/native_m41_collections_browse_test.dart','utf8');
const cloud=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const [file,markers] of [
  [model,['MediaFlowCollectionAssignment','traversedTitleIds']],
  [codec,["orderPlan['collectionAssignments']"]],
  [repo,['collectionAssignments: decoded.collectionAssignments']],
  [preview,['collectionAssignments: base.collectionAssignments','mayUpload => false']],
  [logic,['browseCollection(','inspectCollectionOrderImpact(','NativeM41BrowseOptions']],
  [ui,['m41-confirm-bulk-remove','m41-order-impact','m41-view',
    'm41-per-page','m41-category','m41-rating','m41-select-visible']],
  [screen,['NativeM41CollectionBrowser','onMove:','onRemove:']],
  [tests,['bulk removal is confirmation-gated','pagination respects',
    'v287 assignment map is decoded']],
]) {
  for(const marker of markers)assert(file.includes(marker),'Missing '+marker);
}
for(const content of [preview,logic,ui,screen]) {
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(content),
    'No Collection changes may write account state');
}
for(const marker of ['cloudWritesEnabled = false',
    'hasServerSideCas = false','offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker),'Unsafe write toggle '+marker);
}
console.log('M41: v287 assignments audited read-only; native Collection batch stays local.');
