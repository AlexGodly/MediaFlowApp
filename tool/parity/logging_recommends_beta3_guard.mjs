import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=p=>fs.readFileSync(p,'utf8');
const service=read('lib/services/native_logging_recommends.dart');
const ui=read('lib/features/logging/native_logging_recommends_card.dart');
const tests=read('test/native_logging_queue_filters_beta3_test.dart');
const cloud=read('lib/services/native_cas_protocol.dart');
const release=JSON.parse(read('tool/releases/current.json'));
for(const [src,markers] of [
 [service,['browseQueueCatalog(','maxCandidates<1||maxCandidates>500',
   'catalog.prioritizePersonalOrder!=true',
   'display.resolution!=NativeM50TitleResolution.exact',
   'duplicates.contains(id)','List.unmodifiable(results)']],
 [ui,['logging-queue-search','logging-queue-filter-',
   'NativeRecommendationSelectionFilter.notAdded',
   'NativeRecommendationSelectionFilter.alreadyAdded',
   'logging-queue-count','logging-queue-next-page',
   'logging-queue-previous-page','logging-queue-limit-note',
   '_queueCandidates??=NativeLoggingRecommendation.browseQueueCatalog(',
   '_queuePageSize=5','widget.selectedIds.contains(',
   'NativeLoggingRecommendSource.savedTask']],
 [tests,['100k titles','320px queue','missing saved title',
   'queue supports search, pagination']],
])for(const m of markers)assert(src.includes(m),'Beta3 invariant missing: '+m);
for(const src of [service,ui])
 assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(src),
 'Logging recommendations cannot write Supabase');
for(const key of ['cloudWritesEnabled = false',
    'offlineWriteQueueEnabled = false','hasServerSideCas = false'])
 assert(cloud.includes(key),'Production write safety gate must stay shut');
assert(['app-v1.0.0-beta.3','app-v1.0.0-beta.4'].includes(release.tag));
console.log('Beta3 queue search/filter/pages + no account writes verified.');
