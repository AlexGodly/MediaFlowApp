import assert from 'node:assert/strict';
import fs from 'node:fs';
const model=fs.readFileSync('lib/data/mediaflow_models.dart','utf8');
const codec=fs.readFileSync('lib/data/mediaflow_state_codec.dart','utf8');
const repository=fs.readFileSync('lib/data/mediaflow_library_repository.dart','utf8');
const m37=fs.readFileSync('lib/services/native_m37_library_plan.dart','utf8');
const m40=fs.readFileSync('lib/services/native_m40_collection_plan.dart','utf8');
const audit=fs.readFileSync('lib/services/native_m43_recommendation_audit.dart','utf8');
const widget=fs.readFileSync('lib/features/personal_order/native_m43_recommendation_audit_panel.dart','utf8');
const panel=fs.readFileSync('lib/features/personal_order/native_m42_mixed_queue_panel.dart','utf8');
const tests=fs.readFileSync('test/native_m43_recommendation_audit_test.dart','utf8');
const cloud=fs.readFileSync('lib/services/native_cas_protocol.dart','utf8');
for(const [src,markers] of [
  [model,['this.prioritizePersonalOrder','final bool? prioritizePersonalOrder;']],
  [codec,["settings['prioritizePersonalOrder'] is bool"]],
  [repository,['prioritizePersonalOrder: decoded.prioritizePersonalOrder']],
  [m37,['prioritizePersonalOrder: source.prioritizePersonalOrder']],
  [m40,['prioritizePersonalOrder: base.prioritizePersonalOrder','mayUpload => false']],
  [audit,['class NativeM43RecommendationAudit',
    'firstEligibleWithExclusions(','placementsForTitle(','searchTitles(',
    'Already traversed','Category does not match',
    'Already recommended from an earlier queue slot']],
  [widget,['m43-first-eligible','m43-jump-first','m43-rank-search',
    'm43-jump-','m43-preview-exclusions','m43-ranking-explorer']],
  [panel,['NativeM43RecommendationAuditPanel',
    'm43-clear-focus','m43-focused-','focusedToken']],
  [tests,['50,000','first v287 recommendation',
    'first candidate jumps to its exact Collection queue block',
    'rank lookup shows skipped reasons']],
])for(const marker of markers)
  assert(src.includes(marker),'M43 missing source guard marker '+marker);
for(const src of [audit,widget,panel]){
  assert(!/\.upsert\(|\.rpc\(|\.from\(\s*['"]mediaflow_states/.test(src),
    'M43 cannot write account data');
}
for(const marker of ['cloudWritesEnabled = false',
  'hasServerSideCas = false','offlineWriteQueueEnabled = false']) {
  assert(cloud.includes(marker),'M43 cloud safety gate changed: '+marker);
}
console.log('M43: scoped rank/source evidence and v287 priority switch remain read-only.');
