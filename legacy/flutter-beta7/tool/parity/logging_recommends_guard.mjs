import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=p=>fs.readFileSync(p,'utf8');
const service=read('lib/services/native_logging_recommends.dart');
const widget=read('lib/features/logging/native_logging_recommends_card.dart');
const logging=read('lib/features/logging/logging_screen.dart');
const tests=read('test/native_logging_recommends_test.dart');
const browseTests=read('test/native_logging_queue_browse_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
for(const [src,markers] of [
  [service,['NativeM50TaskDisplay.fromCatalog','NativeM50TitleResolution.exact',
    'catalog.prioritizePersonalOrder!=true','personalOrderPreview',
    'matches!=1','missing or ambiguous','not a confirmed']],
  [widget,['MEDIAFLOW RECOMMENDS','logging-use-recommended-title',
    'logging-recommends-category','logging-recommends-evidence',
    'logging-recommends-selected','widget.onUse(title!)']],
  [logging,['NativeLoggingRecommendsCard(','_selectedIds.add(recommended.id)',
    '_details(context,recommended,data)']],
  [tests,['320px card','missing or duplicate','queue preview only']],
  [service,['browseQueue(','limit<1||limit>8','duplicates.contains(id)',
    'excludedIds.contains(id)','display.resolution!=NativeM50TitleResolution.exact']],
  [widget,['logging-browse-queue','logging-queue-disclaimer',
    'logging-use-queue-','_queueCandidates','_queueCandidates=null',
    'widget.selectedIds.contains(entry.title!.id)']],
  [logging,['_statusOptions','_statusOptions=data.library.map(']],
  [browseTests,['320','duplicates, blocked saved tasks',
    'does not alter account','queue browsing is capped']],
]){
  for(const marker of markers)assert(src.includes(marker),'Required r1 invariant missing: '+marker);
}
for(const src of [service,widget,logging]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(src),
    'Recommendation must not write production data');
}
for(const marker of ['cloudWritesEnabled = false','hasServerSideCas = false',
    'offlineWriteQueueEnabled = false']){
  assert(cloud.includes(marker),'Production cloud write gate must stay closed');
}
console.log('Native Logging Recommends: exact-ID, read-only fallback, no cloud writes.');
