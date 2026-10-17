import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=p=>fs.readFileSync(p,'utf8');
const service=read('lib/services/native_logging_recommend_queue.dart');
const ui=read('lib/features/logging/native_logging_recommends_card.dart');
const tests=read('test/native_logging_recommend_queue_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
for(const [src,checks] of [
  [service,['abstract final class NativeLoggingRecommendQueue',
    'static const pageSize=5','static const maxBrowse=50',
    'catalog.prioritizePersonalOrder!=true','counts[entry.title.id]!=1',
    'offset+pageSize<maxBrowse','Personal Order queue preview only']],
  [ui,['logging-browse-recommendation-queue',
    'logging-queue-browser','logging-queue-next','logging-queue-previous',
    'logging-queue-disclaimer','logging-queue-use-',
    'widget.onUse(entry.title)','showQueue=!showQueue']],
  [tests,['100k library','ambiguous title IDs',
    '320px queue browser','never replaces saved task']],
])for(const v of checks)assert(src.includes(v),'Beta 2 queue guard: '+v);
for(const src of [service,ui]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(src),
    'Recommendation browse must remain read-only');
}
for(const v of ['cloudWritesEnabled = false',
    'hasServerSideCas = false','offlineWriteQueueEnabled = false']){
  assert(cloud.includes(v),'Production write gate modified: '+v);
}
console.log('Beta 2: bounded Personal Order previews, exact-ID safety, no writes');
