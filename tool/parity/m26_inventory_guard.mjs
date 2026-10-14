// M26 fail-closed source inventory guard. No API/database writes.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const read = p => JSON.parse(fs.readFileSync(p,'utf8'));
const manifest=read('docs/parity/v410_source_manifest.json');
const inventory=read('docs/parity/v410_feature_inventory.json');
const contract=read('docs/parity/v410_settings_data_contract.json');
const flows=read('docs/parity/v410_interaction_matrix.json');
const unique=(a,name)=>assert.equal(new Set(a).size,a.length,'Duplicate '+name);
const safePath=p=>typeof p==='string'&&!p.includes('..')&&!p.startsWith('/')&&/^[a-zA-Z0-9._/-]+$/.test(p);
const domains=[
'authentication','shell-navigation','dashboard','library-crud','library-views',
'seasons-metadata','logging','batch-log','history','progression','statistics',
'collections','personal-order','settings','themes','data-management',
'cloud-sync','scheduler','old-system','platform-native','performance-security'
];
assert.equal(manifest.version,'410');
assert.equal(inventory.sourceBaseline,'MediaFlow v410');
assert.equal(contract.baseline,'MediaFlow v410');
assert.equal(flows.baseline,'MediaFlow v410');
assert.equal(manifest.baseBuildModules.length,144);
assert.equal(manifest.runtimeModules.length,157);
assert.equal(manifest.activeStylesheets.length,140);
assert.equal(manifest.defaultSettingsKeys.length,38);
assert(manifest.activeStylesheets.includes('assets/css/222-v410-mobile-dock-sheet.css'));
assert(manifest.activeStylesheets.includes('assets/css/221-v409-mobile-floating-actions.css'));
assert(manifest.sourcePins.length>=7);
for(const p of manifest.sourcePins){assert(safePath(p.path));assert.match(p.gitBlobSha,/^[a-f0-9]{40}$/);}
const modules=[...manifest.baseBuildModules,...manifest.runtimeModules];
unique(modules,'source modules');
for(const p of [...modules,...manifest.activeStylesheets])assert(safePath(p),'Unsafe source path '+p);
unique(manifest.defaultSettingsKeys,'source default key');
const statuses=new Set(['foundation','read_only','draft_only','partial','missing']);
assert(inventory.features.length>=300);
unique(inventory.features.map(f=>f.id),'feature ID');
const discovered=[...new Set(inventory.features.map(f=>f.domain))];
for(const d of domains)assert(discovered.includes(d),'Missing domain '+d);
for(const f of inventory.features){
 assert.match(f.id,/^[a-z-]+\.\d{3}$/);
 assert(statuses.has(f.nativeStatus),'Unknown native status '+f.id);
 assert.equal(f.parityVerified,false,'Unverified features cannot be declared complete: '+f.id);
 assert(f.manualVerificationRequired);
 assert(f.targetMilestone>=27&&f.targetMilestone<=55);
 assert(f.feature.length>=4&&f.acceptance.length>=70);
 assert(Array.isArray(f.sourceEvidence)&&f.sourceEvidence.length>0);
 for(const p of f.sourceEvidence)assert(modules.includes(p),'Unpinned source '+f.id+': '+p);
 for(const p of f.nativeEvidence)assert(safePath(p)&&fs.existsSync(p),'Missing native evidence '+f.id+': '+p);
}
unique(contract.defaultSettings.map(s=>s.key),'contract setting key');
assert.deepEqual(contract.defaultSettings.map(s=>s.key).sort(),[...manifest.defaultSettingsKeys].sort());
assert.deepEqual([...contract.settingsCenterSections].sort(),[...manifest.settingsCenterSections].sort());
assert(contract.stateRoots.length>=25);
unique(contract.stateRoots.map(s=>s.key),'candidate state key');
for(const root of contract.stateRoots){
 assert(['persistent_candidate','UI_or_device_transient','unverified'].includes(root.kind));
 assert.equal(root.cloudStoredVerified,false);
}
assert.equal(contract.syncRequirements.nativeWebEditsEnabled,false);
assert.equal(contract.syncRequirements.atomicCompareAndSwapForAllWritersDeployed,false);
assert.equal(contract.syncRequirements.websiteWriteCompatibilityVerified,false);
assert(flows.cases.length>=50);
unique(flows.cases.map(f=>f.id),'flow IDs');
const tested=new Set();
for(const flow of flows.cases){
 assert.match(flow.id,/^FLOW-\d{3}$/);
 assert(domains.includes(flow.domain));tested.add(flow.domain);
 assert(flow.steps.length>=2&&flow.expected.length>=35);
 assert(['phone','tablet','desktop'].every(d=>flow.devices.includes(d)));
 assert(flow.variants.length>0);
 assert.equal(flow.verified,false);
 assert.equal(flow.automationStatus,'pending');
 assert(flow.targetMilestone>=27&&flow.targetMilestone<=55);
}
for(const d of domains)assert(tested.has(d),'No interaction flow for '+d);
assert(flows.sourceScreenshots.length>=5);
assert(flows.requiredFutureScreenshots.length>=6);
assert.equal(inventory.isFullParityCertification,false);
console.log('M26_PARITY_AUDIT_GUARD_PASSED');
console.log(JSON.stringify({base:manifest.baseBuildModules.length,overrides:manifest.runtimeModules.length,
 css:manifest.activeStylesheets.length,settings:manifest.defaultSettingsKeys.length,
 stateRoots:contract.stateRoots.length,domains:discovered.length,
 features:inventory.features.length,flows:flows.cases.length,
 verified:inventory.features.filter(x=>x.parityVerified).length,
 conclusion:'SOURCE_INVENTORY_ONLY_NOT_COMPLETED_PARITY'},null,2));
