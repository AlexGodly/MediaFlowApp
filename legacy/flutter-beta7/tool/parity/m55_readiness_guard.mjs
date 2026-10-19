// Milestone 55: fail-closed release readiness against the pinned M26 source
// inventory and prior validated M54 evidence. No network or production writes.
import assert from 'node:assert/strict';
import fs from 'node:fs';
const text=p=>fs.readFileSync(p,'utf8');
const json=p=>JSON.parse(text(p));
const features=json('docs/parity/v410_feature_inventory.json');
const journeys=json('docs/parity/v410_interaction_matrix.json');
const contract=json('docs/parity/v410_settings_data_contract.json');
const manifest=json('docs/parity/v410_source_manifest.json');
const report=json('docs/parity/m55_release_readiness.json');
const dart=text('lib/services/native_m55_readiness.dart');
const panel=text('lib/features/settings/native_m55_release_readiness_panel.dart');
const settings=text('lib/features/settings/native_settings_screen.dart');
const tests=text('test/native_m55_release_readiness_test.dart');
const cloud=text('lib/services/native_cas_protocol.dart');
const shared=text('lib/services/native_m30_shared_sync.dart');
const doc=text('docs/MILESTONE_55.md');
const readme=text('README.md');
const auditDoc=text('docs/V410_PARITY_AUDIT.md');
const uniq=(a,name)=>assert.equal(new Set(a).size,a.length,'Duplicate '+name);

assert.equal(manifest.version,'410');
assert.equal(features.sourceBaseline,'MediaFlow v410');
assert.equal(journeys.baseline,'MediaFlow v410');
assert.equal(contract.baseline,'MediaFlow v410');
assert.equal(report.baseline,'MediaFlow v410');
assert.equal(report.schemaVersion,1);
assert.equal(report.decision,'blocked');
assert.equal(report.productionReleaseAuthorized,false);
assert.equal(report.fullWebsiteParityCertified,false);
assert.equal(report.realProductionCloudWritesEnabled,false);
assert.equal(report.featureEvidence.surfaces,features.features.length);
assert.equal(report.featureEvidence.domains,new Set(features.features.map(f=>f.domain)).size);
assert.equal(report.featureEvidence.certifiedSurfaces,features.features.filter(f=>f.parityVerified).length);
assert.equal(report.journeyEvidence.total,journeys.cases.length);
assert.equal(report.journeyEvidence.certified,journeys.cases.filter(f=>f.verified).length);
assert.deepEqual(report.journeyEvidence.pendingIds,journeys.cases.filter(f=>!f.verified).map(f=>f.id));
assert.equal(report.dataEvidence.baseSettingsKeys,contract.defaultSettings.length);
assert.equal(report.dataEvidence.settingsCenterSections,contract.settingsCenterSections.length);
assert.equal(report.dataEvidence.candidateStateRoots,contract.stateRoots.length);
assert.equal(report.dataEvidence.verifiedCloudRoots,contract.stateRoots.filter(x=>x.cloudStoredVerified).length);
assert.equal(report.dataEvidence.originalWebNativeWritesCompatible,contract.syncRequirements.websiteWriteCompatibilityVerified);
assert.equal(report.dataEvidence.serverAtomicCasDeployed,contract.syncRequirements.atomicCompareAndSwapForAllWritersDeployed);
assert.deepEqual(report.screenshotEvidence.stillRequired,journeys.requiredFutureScreenshots);
assert.equal(report.screenshotEvidence.referenceSourceImages,journeys.sourceScreenshots.length);

const counts={foundation:0,read_only:0,draft_only:0,partial:0,missing:0};
for(const f of features.features)counts[f.nativeStatus]++;
assert.deepEqual(report.featureEvidence.scaffoldStatusCounts,counts);
assert.equal(report.domainReviews.length,21);
const domainIds=[...new Set(features.features.map(f=>f.domain))];
assert.deepEqual(report.domainReviews.map(d=>d.id),domainIds);
for(const domain of report.domainReviews){
 const selected=features.features.filter(f=>f.domain===domain.id);
 const flow=journeys.cases.filter(f=>f.domain===domain.id);
 assert.equal(domain.surfaceCount,selected.length);
 assert.equal(domain.certifiedSurfaceCount,selected.filter(f=>f.parityVerified).length);
 assert.deepEqual(domain.pendingFeatureIds,selected.filter(f=>!f.parityVerified).map(f=>f.id));
 assert.deepEqual(domain.journeyIds,flow.map(f=>f.id));
 assert.equal(domain.certifiedJourneys,flow.filter(f=>f.verified).length);
 const statuses={};
 for(const f of selected)statuses[f.nativeStatus]=(statuses[f.nativeStatus]||0)+1;
 assert.deepEqual(domain.scaffoldStatuses,statuses);
}
uniq(report.releaseGates.map(g=>g.id),'release gate');
assert.equal(report.releaseGates.length,12);
for(const gate of report.releaseGates){
 assert.equal(gate.status,'blocked','Gate must never auto-promote: '+gate.id);
 assert(['P0','P1'].includes(gate.priority));
 assert(gate.reason.length>45 && gate.exitCriteria.length>45);
}
const critical=['feature-certification','journey-certification','shared-sync',
  'logging-history-xp','import-export','signed-distribution'];
for(const id of critical)assert(report.releaseGates.some(g=>g.id===id&&g.status==='blocked'));
assert.equal(report.nextMilestones.length,15);
assert.deepEqual(report.nextMilestones.map(m=>m.milestone),
  Array.from({length:15},(_,i)=>56+i));
for(const milestone of report.nextMilestones){
 assert.equal(milestone.kind,'proposed_follow_on_not_authorized_production_rollout');
 assert(milestone.relatedGateIds.length>0);
 for(const id of milestone.relatedGateIds)assert(report.releaseGates.some(g=>g.id===id));
}
assert.equal(report.provenance.previousValidation.automatedTestsPassed,393);
assert.match(report.provenance.previousValidation.status,/previous milestone/i);
assert.equal(report.provenance.previousValidation.iosSignedBuild,'not run');
assert.equal(report.signOff.startsWith('HOLD:'),true);
const dartCheck=(pattern,value)=>assert(dart.includes(pattern),
  'M55 Dart immutable projection missing: '+value);
for(const field of [
 ['inventorySurfaces',report.featureEvidence.surfaces],
 ['inventoriedDomains',report.featureEvidence.domains],
 ['certifiedSurfaces',report.featureEvidence.certifiedSurfaces],
 ['inventoriedJourneys',report.journeyEvidence.total],
 ['certifiedJourneys',report.journeyEvidence.certified],
 ['defaultSettingsKeys',report.dataEvidence.baseSettingsKeys],
 ['candidateStateRoots',report.dataEvidence.candidateStateRoots],
])dartCheck('static const int '+field[0]+' = '+field[1]+';',field[0]);
for(const flag of ['productionReleaseAuthorized','fullWebsiteParityCertified','productionCloudWritesEnabled'])
 dartCheck('static const bool '+flag+' = false;',flag);
dartCheck('static bool get canPublishProduction => false;', 'no production');
const nativeDomains=[...dart.matchAll(/NativeM55DomainAudit\(id:'([^']+)',surfaces:(\d+),certified:(\d+),journeys:(\d+),verifiedJourneys:(\d+),scaffold:'([^']+)'\)/g)]
 .map(m=>({id:m[1],surfaces:Number(m[2]),certified:Number(m[3]),journeys:Number(m[4]),verifiedJourneys:Number(m[5]),scaffold:m[6]}));
assert.equal(nativeDomains.length,report.domainReviews.length);
for(let i=0;i<nativeDomains.length;i++){
 const actual=nativeDomains[i],expected=report.domainReviews[i];
 assert.equal(actual.id,expected.id);
 assert.equal(actual.surfaces,expected.surfaceCount);
 assert.equal(actual.certified,expected.certifiedSurfaceCount);
 assert.equal(actual.journeys,expected.journeyIds.length);
 assert.equal(actual.verifiedJourneys,expected.certifiedJourneys);
 assert.equal(actual.scaffold,Object.keys(expected.scaffoldStatuses).join(', '));
}
for(const gate of report.releaseGates)
 assert(dart.includes("NativeM55ReleaseBlocker('"+gate.id+"','"+gate.priority+"'"),
   'Missing Flutter gate '+gate.id);
for(const planned of report.nextMilestones)
 assert(dart.includes("'M"+planned.milestone+" — "), 'Missing follow-on milestone '+planned.milestone);
for(const marker of ['m55-release-blocked','m55-domain-audit',
   'm55-release-gates','m55-no-writes','m55-future-roadmap'])
 assert(panel.includes(marker),'Missing UI marker '+marker);
assert(settings.includes('const NativeM55ReleaseReadinessPanel()'));
assert(tests.includes('NativeM55Readiness.canPublishProduction'));
assert(tests.includes('NativeCloudCapabilities.cloudWritesEnabled'));
assert(tests.includes('m55-readiness-panel'));
assert(readme.includes('Milestone 55'));
assert(doc.includes('NOT RELEASE READY'));
assert(auditDoc.includes('MILESTONE_55.md'));
for(const [name,source] of [['Dart audit',dart],['UI panel',panel],['tests',tests]]){
 assert(!/\.upsert\s*\(|\.rpc\s*\(|\.insert\s*\(|\.from\(\s*['"]mediaflow_states/.test(source),
   name+' must not add production account writes');
}
for(const flag of ['cloudWritesEnabled = false','hasServerSideCas = false','offlineWriteQueueEnabled = false'])
 assert(cloud.includes(flag),'Production write gate changed: '+flag);
assert(shared.includes('static const bool deployed = false'));
console.log('M55_READINESS_AUDIT_PASSED');
console.log(JSON.stringify({
 baseline:report.baseline,features:report.featureEvidence.surfaces,
 certified:report.featureEvidence.certifiedSurfaces,
 domains:report.featureEvidence.domains,journeys:report.journeyEvidence.total,
 verifiedJourneys:report.journeyEvidence.certified,
 sourceStatuses:counts,releaseGatesBlocked:report.releaseGates.length,
 decision:report.decision,plannedFollowOnMilestones:report.nextMilestones.length,
 statement:'AUDIT COMPLETE, WEBSITE PARITY AND PRODUCTION RELEASE NOT CERTIFIED'
},null,2));
