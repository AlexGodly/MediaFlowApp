// M56: isolated, deterministic rehearsal over synthetic fixture bytes ONLY.
// This is not a Supabase, SQL, RLS, or deployed server implementation.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import crypto from 'node:crypto';

const inventory=JSON.parse(fs.readFileSync('docs/parity/m56_writer_inventory.json','utf8'));
const fixture=JSON.parse(fs.readFileSync('test/fixtures/m28_v410_lossless_sample.json','utf8'));
const copy=value=>structuredClone(value);
const digest=value=>crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const result=(status,revision=null,receipt=null)=>({status,revision,receipt});

// In-memory test-only model of minimum server behavior. Never accepts a DB URL.
class ShadowServer {
  constructor(){this.rows=new Map();this.receipts=new Map();}
  seed(owner,wire){this.rows.set(owner,{revision:8,wire:copy(wire),updatedAt:'2026-10-15T08:00:00Z'});}
  read(actor,owner=actor){if(!actor||actor!==owner)return null;const r=this.rows.get(owner);return r?copy(r):null;}
  legacyUpsert(){return result('legacy_direct_write_denied');}
  commit({actor,owner,base,operationId,intent,abortAfterValidation=false}){
    if(!actor||!owner||actor!==owner)return result('owner_mismatch');
    const row=this.rows.get(owner);
    if(!row)return result('missing_account_row');
    if(typeof operationId!=='string'||!operationId.trim())return result('invalid_operation');
    if(!intent||!['priority','transaction','restore'].includes(intent.kind))return result('unsupported_intent');
    const fingerprint=digest({owner,intent});
    const receiptKey=owner+'/'+operationId;
    const prior=this.receipts.get(receiptKey);
    if(prior)return prior.fingerprint===fingerprint?copy(prior.response):result('operation_id_poisoned');
    if(!base||row.revision!==base.revision||digest(row.wire)!==base.digest)return result('stale_snapshot');
    const next=copy(row.wire);
    if(intent.kind==='priority'){
      const item=next.library.find(x=>x.id===intent.titleId);
      if(!item||!['low','medium','high'].includes(intent.priority))return result('invalid_title_or_priority');
      item.priority=intent.priority;
    }else if(intent.kind==='transaction'){
      const item=next.library.find(x=>x.id===intent.titleId);
      if(!item)return result('invalid_title');
      const units=intent.units;
      if(!Number.isInteger(units)||units<1)return result('invalid_consumption');
      item.progress+=units;
      next.sessions.push({id:'stage-'+operationId,categoryId:item.categoryId,titleId:item.id,amount:units});
      next.xpLedger.stageSynthetic=(next.xpLedger.stageSynthetic||0)+units;
      next.currentTask={...(next.currentTask||{}),stageTaskReceipt:operationId};
      next.orderPlan={...(next.orderPlan||{}),stageTraversalReceipt:operationId};
    }else if(intent.kind==='restore'){
      // Staging-only requires explicit validation of provided synthetic wire.
      if(!intent.validatedBackup||typeof intent.wire!=='object'||Array.isArray(intent.wire))
        return result('invalid_backup');
      for(const key of Object.keys(next))delete next[key];
      Object.assign(next,copy(intent.wire));
    }
    if(abortAfterValidation)return result('interrupted_before_atomic_commit');
    const updated={revision:row.revision+1,wire:next,updatedAt:row.updatedAt};
    // Single in-memory assignment, pretending that a DB transaction would commit
    // state and receipt atomically. PostgreSQL durability remains unverified.
    const response=result('applied',updated.revision,{
      owner,operationId,revision:updated.revision,digest:digest(updated.wire)});
    this.rows.set(owner,updated);
    this.receipts.set(receiptKey,{fingerprint,response:copy(response)});
    return copy(response);
  }
}
const server=new ShadowServer();
const owner='owner-a';server.seed(owner,fixture);
const base=(user=owner)=>{const row=server.read(user);return row?{revision:row.revision,digest:digest(row.wire)}:null;};
const recorded=[];
const prove=(id,fn)=>{fn();recorded.push(id);};
const baseline=base();
const stagedServer=new ShadowServer();stagedServer.seed(owner,fixture);
prove('lost-update-web-native',()=>{
  const a=server.commit({actor:owner,owner,base:baseline,operationId:'web-1',
    intent:{kind:'priority',titleId:'v410-1',priority:'low'}});
  assert.equal(a.status,'applied');
  const b=server.commit({actor:owner,owner,base:baseline,operationId:'android-1',
    intent:{kind:'priority',titleId:'v410-2',priority:'medium'}});
  assert.equal(b.status,'stale_snapshot');
  assert.equal(server.read(owner).wire.library[1].priority,'low');
});
prove('same-time-changed-wire',()=>{
  const before=stagedServer.read(owner),snap=baseline;
  assert.equal(server.read(owner).updatedAt,before.updatedAt);
  assert.notEqual(digest(server.read(owner).wire),digest(before.wire));
  assert.equal(server.commit({actor:owner,owner,base:snap,operationId:'stale-same-timestamp',
    intent:{kind:'priority',titleId:'v410-1',priority:'high'}}).status,'stale_snapshot');
});
prove('retry-lost-ack',()=>{
  const anchor=base();
  const intent={kind:'transaction',titleId:'v410-1',units:2};
  const first=server.commit({actor:owner,owner,base:anchor,operationId:'lost-ack',intent});
  assert.equal(first.status,'applied');
  const retry=server.commit({actor:owner,owner,base:anchor,operationId:'lost-ack',intent});
  assert.deepEqual(retry,first);
  assert.equal(server.read(owner).wire.sessions.length,fixture.sessions.length+1);
});
prove('operation-id-reuse',()=>{
  const conflict=server.commit({actor:owner,owner,base:base(),operationId:'lost-ack',
    intent:{kind:'transaction',titleId:'v410-1',units:5}});
  assert.equal(conflict.status,'operation_id_poisoned');
});
prove('foreign-owner',()=>{
  const bad=server.commit({actor:'owner-b',owner,base:base(),operationId:'foreign',
    intent:{kind:'priority',titleId:'v410-1',priority:'high'}});
  assert.equal(bad.status,'owner_mismatch');
  assert.equal(server.read('owner-b',owner),null);
});
prove('old-web-direct-upsert',()=>{
  assert.equal(server.legacyUpsert().status,'legacy_direct_write_denied');
});
prove('missing-cloud-row',()=>{
  assert.equal(server.commit({actor:'empty',owner:'empty',
    base:{revision:1,digest:'none'},operationId:'seed-unsafe',
    intent:{kind:'priority',titleId:'v410-1',priority:'low'}}).status,
    'missing_account_row');
});
prove('invalid-compressed-wire',()=>{
  assert.throws(()=>JSON.parse('{invalid'),SyntaxError);
  assert.equal(server.commit({actor:owner,owner,base:base(),operationId:'invalid-backup',
    intent:{kind:'restore',validatedBackup:false,wire:{}}}).status,'invalid_backup');
});
prove('backup-restore-race',()=>{
  const anchor=base(),newer=server.commit({actor:owner,owner,base:anchor,operationId:'concurrent',
    intent:{kind:'priority',titleId:'v410-2',priority:'high'}});
  assert.equal(newer.status,'applied');
  const restore=server.commit({actor:owner,owner,base:anchor,operationId:'restore-old',
    intent:{kind:'restore',validatedBackup:true,wire:fixture}});
  assert.equal(restore.status,'stale_snapshot');
  assert.equal(server.read(owner).wire.library[1].priority,'high');
});
prove('offline-reconnect',()=>{
  const offlineDraft={owner,anchor:base(),intent:{kind:'priority',titleId:'v410-1',priority:'medium'}};
  server.commit({actor:owner,owner,base:offlineDraft.anchor,operationId:'other-device',
    intent:{kind:'priority',titleId:'v410-2',priority:'medium'}});
  assert.equal(server.commit({actor:owner,owner,base:offlineDraft.anchor,
    operationId:'reconnect-replayed-without-revalidation',intent:offlineDraft.intent}).status,'stale_snapshot');
});
prove('atomic-logging-side-effects',()=>{
  const before=server.read(owner);
  const interrupted=server.commit({actor:owner,owner,base:base(),operationId:'abort',
    intent:{kind:'transaction',titleId:'v410-1',units:8},abortAfterValidation:true});
  assert.equal(interrupted.status,'interrupted_before_atomic_commit');
  assert.deepEqual(server.read(owner),before);
  const successful=server.commit({actor:owner,owner,base:base(),operationId:'atomic',
    intent:{kind:'transaction',titleId:'v410-1',units:3}});
  assert.equal(successful.status,'applied');
  const current=server.read(owner).wire;
  assert.equal(current.sessions.length,fixture.sessions.length+2);
  assert.equal(current.currentTask.stageTaskReceipt,'atomic');
  assert.equal(current.orderPlan.stageTraversalReceipt,'atomic');
  assert.equal(current.v410UnknownRoot.secretFutureField,fixture.v410UnknownRoot.secretFutureField);
  assert.equal(current.library[0].unknownMarker,99);
});
prove('cross-account-device-switch',()=>{
  const oldDraft={actor:owner,owner,base:base(),operationId:'stale-user',
    intent:{kind:'priority',titleId:'v410-1',priority:'low'}};
  assert.equal(server.commit({...oldDraft,actor:'owner-b'}).status,'owner_mismatch');
  assert.equal(server.read('owner-b',owner),null);
});
assert.deepEqual(recorded.map(x=>x).sort(),
  inventory.threatScenarios.map(x=>x.id).sort(),
  'Every listed threat must have an explicit rehearsal');
assert.equal(inventory.actualStagingProvisioned,false);
assert.equal(inventory.cutoverAuthorized,false);
assert.equal(inventory.serverProtocolDeployed,false);
assert.equal(inventory.exhaustive,false);
console.log('M56_SHADOW_STAGING_REHEARSAL_PASSED');
console.log(JSON.stringify({scenarios:recorded.length,implementation:'ISOLATED_IN_MEMORY_ONLY',
  backend:'NO DATABASE CONNECTED',conclusion:'NOT STAGING DEPLOYED OR PRODUCTION SAFE'},null,2));
