import assert from 'node:assert/strict';
import fs from 'node:fs';
const plan=fs.readFileSync('lib/services/native_m37_library_plan.dart','utf8');
const screen=fs.readFileSync('lib/features/library/library_screen.dart','utf8');
const editor=fs.readFileSync('lib/features/library/native_m37_library_plan_ui.dart','utf8');
const shell=fs.readFileSync('lib/app/mediaflow_shell.dart','utf8');
const repo=fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const flags=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const s of ['NativeM37LibraryPlan','void create(','void edit(','stageDelete',
  'restoreDeleted','void undo(','void redo(','previewCatalog',
  '_stale','mayUpload => false']){
  assert(plan.includes(s),'M37 model missing '+s);
}
for(const s of ['m37-new-title','m37-preview-toggle','m37-bulk-delete',
  'm37-select-visible','m37-review-plan','m37-preview-warning']){
  assert(screen.includes(s),'M37 Library UI missing '+s);
}
assert(editor.includes('DEVICE-ONLY PREVIEW'));
assert(editor.includes('Discard entire local plan'));
assert(shell.includes('libraryPlan?.dispose()'));
assert(shell.includes('changePlan: libraryPlan'));
assert(!/\.upsert\(|\.insert\(|\.update\(|\.delete\(|\.rpc\(/.test(repo));
for(const s of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(flags.includes(s),'Dangerous cloud gate '+s);
}
console.log('M37: reversible local Library CRUD preview only; actual account writes disabled.');
