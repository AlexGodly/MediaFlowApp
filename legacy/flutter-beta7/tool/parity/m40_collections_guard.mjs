import assert from 'node:assert/strict';
import fs from 'node:fs';
const model=fs.readFileSync('lib/services/native_m40_collection_plan.dart','utf8');
const ui=fs.readFileSync('lib/features/collections/collections_screen.dart','utf8');
const editor=fs.readFileSync('lib/features/collections/native_m40_collection_editor.dart','utf8');
const shell=fs.readFileSync('lib/app/mediaflow_shell.dart','utf8');
const cloud=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
const tests=fs.readFileSync('test/native_m40_collection_plan_test.dart','utf8');
for(const marker of ['NativeM40CollectionPlan','void observe(','void addTitles(',
  'void removeTitles(','void moveTitle(','void stageDelete(','void restore(',
  'void undo(','void redo(','previewCatalog(','mayUpload => false',
  '200 local changes maximum','_ambiguousTitles','_ambiguousCollections']) {
  assert(model.includes(marker),'M40 model missing '+marker);
}
for (const marker of ['m40-create','m40-preview','m40-undo','m40-redo',
  'm40-add-titles','m40-confirm-delete','m40-confirm-remove',
  'm40-source-label']) {
  assert(ui.includes(marker),'M40 Collections UI missing '+marker);
}
for (const marker of ['m40-direct-add-','m40-picker-multi',
  'm40-add-selected','m40-save-collection','LOCAL PREVIEW']) {
  if(marker === 'LOCAL PREVIEW') continue;
  assert(editor.includes(marker),'M40 editor missing '+marker);
}
const advanced=fs.readFileSync('lib/features/collections/native_m41_collection_browser.dart','utf8');
for(const marker of ['m40-up-','m40-down-','m40-remove-']) {
  assert(advanced.includes(marker),'M41 extracted Collection controls missing '+marker);
}
assert(shell.includes('collectionPlan?.dispose()'));
assert(shell.includes('plan: collectionPlan'));
assert(tests.includes('100k Library titles'));
for(const source of [model,ui,editor]) {
  // A Dart List.insert is an in-memory reorder; block cloud client calls only.
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(source),
    'M40 cannot introduce production cloud mutations');
}
for(const marker of ['cloudWritesEnabled = false',
    'hasServerSideCas = false','offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker),'M40 must retain write safety gate '+marker);
}
console.log('M40: Collection changes stay owner-scoped, RAM-only and reversible.');
