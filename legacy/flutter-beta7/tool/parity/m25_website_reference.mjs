// M25 - Pinned original MediaFlow v348 and v149 behavior (synthetic inputs ONLY).
// v348 source blob: 5a436d205417ea36f8c39e896925fefef24c0901
// v149 source blob: fd0160322a3a7ae07eb2e3f94bb6ee3e010731aa
import fs from 'node:fs';
import assert from 'node:assert/strict';
let S={};let syntheticStreak=1;let nextId=0;
function levelingSettings(){return S.settings.leveling;}
function v149ProspectiveTodayStreak(){return syntheticStreak;}
function computeDayStreak(){return syntheticStreak;}
function uid(){return 'synthetic-'+(++nextId);}
function v334InvalidateXP(){}
const V348_REWARD_DEFAULTS={
  collectionAddTitleXP:8,
  orderAddTitleXP:6,
  orderAddCollectionXP:12,
  orderReorderTitleXP:4,
  orderReorderCollectionXP:6,
  collectionReorderTitleXP:4,
  batchLogXP:15,
  globalStreakMultiplierEnabled:true
};
function v149StreakMultiplier(streak){
  if(levelingSettings().enabled===false)return 1;
  const n=Math.max(0,Math.floor(Number(streak)||0));
  if(n<=1)return 1;
  return Math.round((1+0.10*Math.log2(n))*100)/100;
}
// VERBATIM v348Enabled
function v348Enabled(){return S.settings?.leveling?.enabled!==false;}
// VERBATIM v348Multiplier
function v348Multiplier(){
  if(!v348Enabled()||S.settings?.leveling?.globalStreakMultiplierEnabled===false)return 1;
  const streak=typeof v149ProspectiveTodayStreak==='function'?v149ProspectiveTodayStreak():computeDayStreak();
  return Math.max(1,Number(v149StreakMultiplier(streak))||1);
}
// VERBATIM v348Multiply
function v348Multiply(amount){return Math.max(0,Math.round((Number(amount)||0)*v348Multiplier()));}
// VERBATIM v348Rate
function v348Rate(key){
  const raw=Number(S.settings?.leveling?.[key]??V348_REWARD_DEFAULTS[key]);
  return Number.isFinite(raw)?Math.max(0,Math.min(100000,raw)):Number(V348_REWARD_DEFAULTS[key]||0);
}
// VERBATIM v348Ledger
function v348Ledger(){
  S.xpLedger=S.xpLedger||{};
  for(const key of ['v348ActionEvents','v348LibraryAdditionBonus','v348LibraryCompletionBonus','v348EventMeta']){
    const x=S.xpLedger[key];if(!x||typeof x!=='object'||Array.isArray(x))S.xpLedger[key]={};
  }
  return S.xpLedger;
}
// VERBATIM v348Award
function v348Award(kind,amount=1,details={}){
  if(!v348Enabled())return 0;
  const quantity=Math.max(0,Math.round(Number(amount)||0));if(!quantity)return 0;
  const xp=v348Multiply(quantity*v348Rate(kind));if(!xp)return 0;
  const l=v348Ledger();const key=kind+':'+(typeof uid==='function'?uid():Date.now()+'_'+Math.random());
  l.v348ActionEvents[key]=xp;
  l.v348EventMeta[key]={kind,baseXP:quantity*v348Rate(kind),multiplier:v348Multiplier(),xp,timestamp:Date.now(),source:v348SourceLabel(kind),details:String(details?.description||'').slice(0,300),subjectId:String(details?.subjectId||''),quantity};
  v334InvalidateXP();
  return xp;
}
// VERBATIM v348SourceLabel
function v348SourceLabel(kind){
  const labels={collectionAddTitleXP:'Collection · added titles',collectionReorderTitleXP:'Collection · reordered titles',orderAddTitleXP:'Personal Order · added titles',orderAddCollectionXP:'Personal Order · assigned Collection',orderReorderTitleXP:'Personal Order · reordered titles',orderReorderCollectionXP:'Personal Order · reordered Collections',batchLogXP:'Batch Log bonus',libraryAdditions:'Library · new title',libraryEdits:'Library · edited title',manualCovers:'Library · manual cover',ratings:'Rating reward',v334StartedTitles:'First title start',v335FirstEpisodeRewards:'First episode',v334CollectionCreates:'Collection created',v334CollectionEdits:'Collection edited',logCompletions:'Log completion bonus'};
  return labels[kind]||String(kind);
}
// VERBATIM v348MapValues
function v348MapValues(map){return Object.values(map||{}).reduce((s,n)=>s+Math.max(0,Number(n)||0),0);}
// VERBATIM v348ExtraXP
function v348ExtraXP(ledger){
  return v348MapValues(ledger?.v348ActionEvents)+v348MapValues(ledger?.v348LibraryAdditionBonus)+v348MapValues(ledger?.v348LibraryCompletionBonus);
}
// VERBATIM v348SnapshotMaps
function v348SnapshotMaps(keys){const l=v348Ledger();return Object.fromEntries(keys.map(key=>[key,{...(l[key]||{})}]));}
// VERBATIM v348RaiseNewRewards
function v348RaiseNewRewards(snapshot){
  if(!v348Enabled())return;
  const l=v348Ledger();let changed=false;
  for(const [key,before] of Object.entries(snapshot)){
    const after=l[key]||{};
    for(const [id,value] of Object.entries(after)){
      const prior=Number(before[id])||0,added=Math.max(0,(Number(value)||0)-prior);
      if(added>0){
        const mult=v348Multiplier(),xp=v348Multiply(added),inc=xp-added;
        if(inc>0){after[id]=Number(value)+inc;changed=true;}
        const metaId=key+':'+id+':'+Date.now()+':'+(typeof uid==='function'?uid():Math.random());
        l.v348EventMeta[metaId]={kind:key,baseXP:added,multiplier:mult,xp,timestamp:Date.now(),source:v348SourceLabel(key),subjectId:id};
        changed=true;
      }
    }
  }
  if(changed)v334InvalidateXP();
}
// Exact website v348 global streak switch wrapper:
const v348StreakBase=v149StreakMultiplier;
v149StreakMultiplier=function(streak){
  if(S.settings?.leveling?.globalStreakMultiplierEnabled===false)return 1;
  return v348StreakBase.apply(this,arguments);
};
const fixtures=JSON.parse(fs.readFileSync(new URL('../../test/fixtures/m25_action_xp_vectors.json',import.meta.url),'utf8'));
let verified=0;
for(const f of fixtures.actions){
 S={settings:{leveling:{...f.leveling}},xpLedger:{}};
 syntheticStreak=f.streak;
 assert.equal(v348Rate(f.kind),f.expectedRate,f.name+' rate');
 assert.equal(v348Multiplier(),f.expectedMultiplier,f.name+' multiplier');
 const awarded=v348Award(f.kind,f.amount,{description:'synthetic'});
 assert.equal(awarded,f.expectedXp,f.name+' award');
 verified+=3;
}
for(const f of fixtures.ledgerExtras){
 S={settings:{leveling:{enabled:true}},xpLedger:f.ledger};
 assert.equal(v348ExtraXP(S.xpLedger),f.expected,f.name+' extra totals');
 verified++;
}
for(const f of fixtures.increments){
 S={settings:{leveling:{...f.leveling}},xpLedger:{libraryEdits:{unit:f.after}}};
 syntheticStreak=f.streak;
 v348RaiseNewRewards({libraryEdits:{unit:f.before}});
 assert.equal(S.xpLedger.libraryEdits.unit-f.after,f.expectedExtra,f.name+' incremental bonus');
 verified++;
}
console.log('M25_ORIGINAL_JS_PARITY_FIXTURES_PASSED='+verified);
