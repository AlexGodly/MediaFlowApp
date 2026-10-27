// M56 inventory guard: compare pinned website source-path metadata, native
// projections, and safety flags. This checks a partial source audit, not
// an exhaustive live writer search or provisioned staging database.
import fs from 'node:fs';
import assert from 'node:assert/strict';

const text=p=>fs.readFileSync(p,'utf8');
const json=p=>JSON.parse(text(p));
const audit=json('docs/parity/m56_writer_inventory.json');
const source=json('docs/parity/v410_source_manifest.json');
const settings=json('docs/parity/v410_settings_data_contract.json');
const m55=json('docs/parity/m55_release_readiness.json');
const native=text('lib/services/native_m56_sync_inventory.dart');
const panel=text('lib/features/settings/native_m56_sync_preflight_panel.dart');
const suite=text('test/native_m56_sync_preflight_test.dart');
const rehearsal=text('tool/parity/m56_staging_rehearsal.mjs');
const screen=text('lib/features/settings/native_settings_screen.dart');
const cloud=text('lib/services/native_cas_protocol.dart');
const protocol=text('lib/services/native_m30_shared_sync.dart');
const workflow=text('.github/workflows/native-ci.yml');
const doc=text('docs/MILESTONE_56.md');
const readme=text('README.md');
const uniq=(items,label)=>assert.equal(new Set(items).size,items.length,'Non-unique '+label);
const modules=new Set([...source.baseBuildModules,...source.runtimeModules]);
const kinds=new Set([
 'direct_cloud_writer','cloud_write_caller','direct_cloud_write_caller',
 'state_mutator_to_autosave','local_file_export','runtime_override_to_review',
 'cloud_read_only','device_local_only','test_only_simulation',
 'production_capability_gate'
]);
assert.equal(audit.sourceBaseline,'MediaFlow v410');
assert.equal(audit.websiteSource.repository,'AlexGodly/MediaFlow');
assert.equal(audit.websiteSource.ref,'410');
assert.equal(audit.schemaVersion,1);
assert.equal(audit.milestone,56);
assert.equal(audit.exhaustive,false,'Do not certify untraced dynamic writers');
assert.equal(audit.status,'incomplete_writer_discovery_do_not_cut_over');
for(const field of ['productionTouched','actualStagingProvisioned','cloudWritesEnabled',
  'cutoverAuthorized','serverProtocolDeployed'])assert.equal(audit[field],false,
    'M56 attempted to authorize '+field);
assert.equal(audit.writerSurfaces.length,18);
uniq(audit.writerSurfaces.map(w=>w.id),'writer surface ids');
for(const w of audit.writerSurfaces){
 assert(['website','native'].includes(w.client));
 assert(kinds.has(w.kind),'Invalid writer kind '+w.id);
 assert(['critical','high'].includes(w.risk));
 assert(w.entrypoint.length>3);
 assert(w.behavior.length>25);
 assert(w.cutoverRequirement.length>25);
 assert(w.stateRoots.length>0);
 assert(['confirmed','partially_traced'].includes(w.evidence));
 assert(w.source.path && !w.source.path.includes('..'));
 if(w.client==='website'){
   assert(modules.has(w.source.path),'Website path not in M26 assembled source order: '+w.source.path);
   assert.match(w.source.gitBlobSha,/^[0-9a-f]{40}$/);
 }else{
   assert(w.source.path.startsWith('lib/'),'Native writer path outside lib/');
   assert(fs.existsSync(w.source.path),'No native source for '+w.id);
   assert.equal(w.source.gitBlobSha,undefined);
 }
 assert(native.includes("id: '"+w.id+"'"), 'Missing native writer projection '+w.id);
 assert(native.includes("sourcePath: '"+w.source.path+"'"),
   'Missing native source path '+w.source.path);
}
assert(audit.writerSurfaces.some(w=>w.id==='web-cloud-rawset'
  && w.kind==='direct_cloud_writer'));
assert(audit.writerSurfaces.some(w=>w.id==='web-backup-export'
  && w.kind==='local_file_export'));
assert(audit.writerSurfaces.some(w=>w.id==='web-logging-submit'));
assert(audit.writerSurfaces.some(w=>w.id==='web-full-backup-restore'));
assert(audit.writerSurfaces.some(w=>w.id==='web-sync-now'));
assert(audit.writerSurfaces.some(w=>w.id==='native-locked-cloud-writes'));
assert.equal(audit.writerSurfaces.filter(w=>w.client==='website').length,14);
assert.equal(audit.writerSurfaces.filter(w=>w.client==='native').length,4);
assert.equal(audit.pendingDiscovery.length,8);
assert.equal(audit.stagingReadiness.length,8);
uniq(audit.stagingReadiness.map(x=>x.id),'staging check IDs');
for(const check of audit.stagingReadiness){
 assert.equal(check.verified,false);
 assert(check.reason.length>25);
 assert(native.includes("NativeM56StagingCheck('"+check.id+"'"),
   'Missing native staging check '+check.id);
}
for(const item of audit.pendingDiscovery)
 assert(native.includes("'"+item.replaceAll("'","\\'")+"'"),
   'Native outstanding discovery missing '+item);
assert.equal(audit.threatScenarios.length,12);
uniq(audit.threatScenarios.map(x=>x.id),'threat IDs');
for(const threat of audit.threatScenarios){
 assert(threat.expected.length>27);
 assert(rehearsal.includes("prove('"+threat.id+"'"),
   'No model rehearsal for '+threat.id);
}
for(const [field,num] of [
 ['writerSurfaces',audit.writerSurfaces.length],
 ['rehearsalScenarios',audit.threatScenarios.length],
 ['unresolvedDiscoveryTasks',audit.pendingDiscovery.length],
 ['unresolvedStagingChecks',audit.stagingReadiness.length],
]) assert(native.includes('static const int '+field+' = '+num+';'),field);
for(const flag of ['sourceAuditExhaustive','stagingEnvironmentProvisioned',
 'productionCloudWritesEnabled','serverProtocolDeployed','cutoverAuthorized',
 'readyForStaging','readyForProduction'])
 assert(native.includes('static const bool '+flag+' = false;'),flag);
for(const marker of ['m56-sync-preflight-panel','m56-sync-cutover-blocked',
 'm56-staging-checks','m56-writer-surfaces','m56-no-write-action','m56-discovery-list'])
 assert(panel.includes(marker),'Missing read-only diagnostics '+marker);
assert(screen.includes('const NativeM56SyncPreflightPanel()'));
assert(suite.includes('NativeM30Protocol.deployed'));
assert(suite.includes('NativeCloudCapabilities.cloudWritesEnabled'));
assert(suite.includes('m56-sync-cutover-blocked'));
assert(doc.includes('STAGING NOT PROVISIONED'));
assert(readme.includes('Milestone 56'));
assert(workflow.includes('node tool/parity/m56_sync_inventory_guard.mjs'));
assert(workflow.includes('node tool/parity/m56_staging_rehearsal.mjs'));
assert.equal(settings.syncRequirements.nativeWebEditsEnabled,false);
assert.equal(settings.syncRequirements.atomicCompareAndSwapForAllWritersDeployed,false);
assert.equal(settings.syncRequirements.websiteWriteCompatibilityVerified,false);
assert.equal(m55.productionReleaseAuthorized,false);
for(const flag of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false'])
 assert(cloud.includes(flag),'Existing write gate changed');
assert(protocol.includes('static const bool deployed = false'));
for(const [name,src] of [['audit Dart',native],['panel',panel],['Dart tests',suite]]){
 for(const term of [".upsert(", ".insert(", ".update(", ".delete(", ".rpc("])
   assert(!src.includes(term),'M56 '+name+' includes a cloud mutation call '+term);
}
for(const forbidden of ['createClient(', 'process.env.', 'fetch(', 'https.request', 'writeFileSync('])
 assert(!rehearsal.includes(forbidden),'Rehearsal gained non-synthetic side effect '+forbidden);
console.log('M56_SYNC_INVENTORY_GUARD_PASSED');
console.log(JSON.stringify({sourceBaseline:audit.sourceBaseline,
  writerSurfaces:audit.writerSurfaces.length,website:audit.writerSurfaces.filter(x=>x.client==='website').length,
  native:audit.writerSurfaces.filter(x=>x.client==='native').length,
  threatCases:audit.threatScenarios.length,unresolvedDiscovery:audit.pendingDiscovery.length,
  blockedStagingPrerequisites:audit.stagingReadiness.length,
  status:'INVENTORY_INCOMPLETE_STAGING_UNPROVISIONED_WRITES_DISABLED'},null,2));
