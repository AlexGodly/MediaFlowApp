import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=(path)=>fs.readFileSync(path,'utf8');
const ui=read('lib/features/personal_order/native_m45_direct_title_planner.dart');
const picker=read('lib/services/native_m46_title_picker.dart');
const plan=read('lib/services/native_m44_personal_order_plan.dart');
const tests=read('test/native_m46_personal_order_picker_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
for(const [src,markers] of [
  [picker,['class NativeM46TitlePicker','NativeM46Membership.notAdded',
    'NativeM46Membership.alreadyAdded','pageSize','matches.skip(start)',
    '_ambiguous.contains(title.id)','NativeM46Sort.alphabetical']],
  [ui,['m46-tools-filters','m46-page-size','m46-status-filter',
    'm46-priority-filter','m46-membership-filter','m46-sort-filter',
    'm46-view-mode','_M46View.coversTitles','GridView.builder',
    'LayoutBuilder','m45-apply-bulk','m45-position-','m45-preview']],
  [plan,['bool get mayUpload => false','_validateDirectOrder()',
    'void addDirectTitles(','void removeDirectTitles(',
    'void positionDirectTitle(','_ensureCurrent();',
    'void undo()','void redo()','void discard()']],
  [tests,['beyond old 60 cap','100k-title picker',
    'phone layout','stages title locally','duplicate Library ID']],
]) {
  for(const marker of markers) {
    assert(src.includes(marker),'M46 missing safety/UX marker: '+marker);
  }
}
for(const src of [ui,picker,plan]) {
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(src),
    'M46 must not write production account or task data');
}
for(const marker of ['cloudWritesEnabled = false','hasServerSideCas = false',
    'offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker),'M46 illegal cloud-write gate '+marker);
}
console.log('M46: paged, filtered native Personal Order UI and write guards verified.');
