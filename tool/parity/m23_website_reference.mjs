// AUTO-PINNED READ-ONLY REFERENCE EXCERPTS. This fixture does not ship in Flutter.
// Extracted verbatim from the owner's separate original MediaFlow website.
// Do not edit these copied algorithms to satisfy native tests; refresh only by
// deliberately re-verifying original source with a matching fixture update.
// src/js/features/xp/054-v149-day-streak-xp-multiplier.js | git blob fd0160322a3a7ae07eb2e3f94bb6ee3e010731aa
function v149DateKeyFromSession(s){
  const raw=String(s?.date||'').trim();
  if(/^\d{4}-\d{2}-\d{2}$/.test(raw))return raw;
  const ts=Number(s?.timestamp)||0;
  if(ts>0){
    const d=new Date(ts);
    if(!Number.isNaN(d.getTime()))return d.toISOString().slice(0,10);
  }
  return '';
}
// src/js/features/xp/054-v149-day-streak-xp-multiplier.js | git blob fd0160322a3a7ae07eb2e3f94bb6ee3e010731aa
function v149ShiftDateKey(key,delta){
  if(!/^\d{4}-\d{2}-\d{2}$/.test(String(key||'')))return '';
  const d=new Date(`${key}T12:00:00Z`);
  if(Number.isNaN(d.getTime()))return '';
  d.setUTCDate(d.getUTCDate()+Number(delta||0));
  return d.toISOString().slice(0,10);
}
// src/js/features/xp/054-v149-day-streak-xp-multiplier.js | git blob fd0160322a3a7ae07eb2e3f94bb6ee3e010731aa
function v149BuildStreakMap(sessions){
  const days=new Set();
  for(const s of (Array.isArray(sessions)?sessions:[])){
    if(!s||s.status==='skipped')continue;
    const key=v149DateKeyFromSession(s);
    if(key)days.add(key);
  }

  const map=new Map();
  for(const key of [...days].sort()){
    const prev=v149ShiftDateKey(key,-1);
    map.set(key,(map.get(prev)||0)+1);
  }
  return map;
}
// src/js/features/xp/054-v149-day-streak-xp-multiplier.js | git blob fd0160322a3a7ae07eb2e3f94bb6ee3e010731aa
function v149StreakMultiplier(streak){
  if(levelingSettings().enabled===false)return 1;
  const n=Math.max(0,Math.floor(Number(streak)||0));
  if(n<=1)return 1;
  return Math.round((1+0.10*Math.log2(n))*100)/100;
}
// src/js/features/xp/054-v149-day-streak-xp-multiplier.js | git blob fd0160322a3a7ae07eb2e3f94bb6ee3e010731aa
function v149SessionStreakBonusForState(state){
  const sessions=Array.isArray(state?.sessions)?state.sessions:[];
  const map=v149BuildStreakMap(sessions);
  let bonus=0;

  for(const s of sessions){
    if(!s||s.status==='skipped')continue;
    const stored=Number(s.xp);
    let raw=0;
    if(Number.isFinite(stored)&&stored>0)raw=Math.max(0,stored);
    else{
      const cat=getCategory(s.categoryId);
      raw=Math.max(0,Number(calculateConsumptionXP(
        cat,
        Number(s.actualAmount)||0,
        Number(s.minutes)||0,
        s.healthStatus||'healthy'
      ).xp)||0);
    }

    const streak=map.get(v149DateKeyFromSession(s))||1;
    const total=Math.max(0,Math.round(raw*v149StreakMultiplier(streak)));
    bonus+=Math.max(0,total-raw);
  }

  return Math.round(bonus);
}
// src/js/components/231-v331-per-title-logging-timestamps.js | git blob a14fa28e486827ffc7ccf576117520906239b7b0
function v331LogicalSessionCount(sessions){
  const seen=new Set();
  for(const s of sessions||[]){
    if(!s)continue;
    const key=s.sessionGroupId?`session:${s.sessionGroupId}`:s.batchGroupId?`batch:${s.batchGroupId}`:`entry:${s.id||seen.size}`;
    seen.add(key);
  }
  return seen.size;
}
// src/js/features/xp/037-v120-completion-xp-progression-integrity.js | git blob 0b1d1da1741416f4ffa65aa7270e4d5cc3a7b856
function v120IsCompleted(item){
  return !!(item && (item.status==='completed' || (item.total!=null && Number(item.total)>0 && Number(item.progress)>=Number(item.total))));
}
// src/js/components/267-v369-itemized-logging.js | git blob d1ba6a7a02216aa357d40a2cefd63f2f575b5aa3
function v369ContiguousProgress(start,units,seasonId=null,limit=null){
  const current=Math.max(0,Math.floor(Number(start)||0));
  const relevant=new Set((units||[]).filter(u=>String(u?.seasonId||'')===String(seasonId||''))
    .filter(u=>!u.isRepeat).map(u=>Math.floor(Number(u.number)||0)).filter(n=>n>current));
  const max=Number(limit)>0?Math.max(current,Math.floor(Number(limit))):Number.MAX_SAFE_INTEGER;
  let end=current;
  while(end<max && relevant.has(end+1))end++;
  return end;
}
// src/js/features/logging/008-session-flow.js | git blob 58dae516e673a5cf991ec1a811d4ead356282084
function submitLog(){
  const t=S.currentTask;
  const assignedCat=getCategory(t.categoryId);const enteredAmount=clamp(Number(S.logDraft.amount)||0,0,999999);
  const totalMinutes=clamp(Number(S.logDraft.minutes)||0,0,999999);
  const entries=S.logDraft.entries||[];
  const extra=(S.logDraft.note||'').trim();
  const timestamp=Date.now(), sessionGroupId=S.logDraft?.v369Interface==='itemized'
    ?String(S.logDraft.v369CommitId||(S.logDraft.v369CommitId=uid())):uid();
  const v369Itemized=S.logDraft?.v369Interface==='itemized';

  // v61: actual consumption and recommendation outcome are separate concepts.
  const groups=new Map();
  if(entries.length){
    entries.forEach(e=>{
      const item=e.libraryId?S.library.find(i=>i.id===e.libraryId):null;
      const actualCat=(item&&getCategory(item.categoryId))||assignedCat;
      const qty=Math.max(0,Number(e.qty)||0);
      if(!groups.has(actualCat.id)) groups.set(actualCat.id,{cat:actualCat,entries:[],amount:0,weight:0});
      const g=groups.get(actualCat.id); g.entries.push(e); g.amount+=qty;
      g.weight+=qty*Math.max(1,Number(actualCat.minutesPerUnit)||1);
    });
  }else if(enteredAmount>0){
    groups.set(assignedCat.id,{cat:assignedCat,entries:[],amount:enteredAmount,weight:Math.max(1,enteredAmount*Math.max(1,Number(assignedCat.minutesPerUnit)||1))});
  }

  const grouped=[...groups.values()], totalWeight=grouped.reduce((n,g)=>n+g.weight,0)||1;
  let minutesLeft=totalMinutes;
  grouped.forEach((g,index)=>{
    const actualCat=g.cat, isAssigned=actualCat.id===assignedCat.id;
    const groupMinutes=v369Itemized&&typeof v369Seconds==='function'
      ?g.entries.reduce((n,e)=>n+(Array.isArray(e.v369Units)?e.v369Units.reduce((sum,u)=>sum+v369Seconds(u),0):0),0)/60
      :(index===grouped.length-1?minutesLeft:Math.min(minutesLeft,Math.round(totalMinutes*(g.weight/totalWeight))));
    minutesLeft=Math.max(0,minutesLeft-groupMinutes);
    let status='logged';
    if(isAssigned){
      if(g.amount<t.targetMid) status='partial';
      else if(g.amount>t.targetMid) status='over';
      else status='complete';
    }
    const healthStatus=categoryStatus(actualCat).status;
    const xpCalc=calculateConsumptionXP(actualCat,g.amount,groupMinutes,healthStatus);
    const note=[entriesNote(g.entries),extra].filter(Boolean).join(' — ');
    S.sessions.push({
      id:uid(),timestamp,date:todayISO(),categoryId:actualCat.id,
      assignedCategoryId:assignedCat.id,assignedTargetAmount:t.targetMid,sessionGroupId,
      followedAssignedCategory:isAssigned,targetAmount:isAssigned?t.targetMid:g.amount,
      actualAmount:g.amount,minutes:groupMinutes,note,status,unit:actualCat.unit,
      xp:xpCalc.xp,healthStatus,source:'recommendation',
      ...(v369Itemized?{v369Itemized:true,v369CommitId:sessionGroupId,v369DurationSeconds:Math.round(groupMinutes*60)}:{}),
      titles:g.entries.map(e=>{
        const units=v369Itemized&&Array.isArray(e.v369Units)?e.v369Units.map(u=>({...u})):[];
        return {
          title:cleanTitle(e.title),libraryId:e.libraryId||null,qty:Number(e.qty)||0,repeat:!!e.isRepeat,
          loggedAt:units.length?Math.min(...units.map(u=>Number(u.loggedAt)||timestamp)):v331ValidTimestamp(e.loggedAt)||timestamp,
          ...(v369Itemized?{v369Itemized:true,v369Units:units,v369DurationSeconds:units.reduce((n,u)=>n+(typeof v369Seconds==='function'?v369Seconds(u):0),0)}:{})
        };
      })
    });
  });

  // If none of the actual consumption belonged to the recommended category,
  // preserve the recommendation itself as Skipped without adding fake consumption.
  if(!grouped.some(g=>g.cat.id===assignedCat.id && g.amount>0)){
    S.sessions.push({id:uid(),timestamp,date:todayISO(),categoryId:assignedCat.id,
      assignedCategoryId:assignedCat.id,assignedTargetAmount:t.targetMid,sessionGroupId,
      followedAssignedCategory:false,targetAmount:t.targetMid,actualAmount:0,minutes:0,
      note:'Recommendation not followed',status:'skipped',unit:assignedCat.unit,xp:0,
      healthStatus:categoryStatus(assignedCat).status,source:'recommendation',titles:[]});
  }

  // v165: award System Respect XP once per recommendation/log group.
  // This runs before the normal persist/render path, so there is no extra
  // History scan, save, or render just to award the bonus.
  v165ApplyRespectReward(t,entries,sessionGroupId,assignedCat);

  if(S.logDraft.updateLibrary){
    entries.forEach(e=>{
      const item=e.libraryId?S.library.find(i=>i.id===e.libraryId):findLibraryMatch(assignedCat.id,e.title);
      if(item){
        // v81: repeat consumption counts in History/XP/stats but never pushes main Library progress past completion.
        if(e.isRepeat){ return; }
        if(v369Itemized&&Array.isArray(e.v369Units)&&typeof v369ProjectedTitleProgress==='function'){
          item.progress=v369ProjectedTitleProgress(item,e);
        }else item.progress=(item.progress||0)+(Number(e.qty)||0);
        if(item.total) item.progress=Math.min(item.progress,item.total);
        if(item.total&&item.progress>=item.total&&item.status!=='dropped'){
          item.status='completed'; item.completedAt=item.completedAt||timestamp;
          S.completionTimeline=S.completionTimeline||[];
          if(!S.completionTimeline.some(x=>x.libraryId===item.id)) S.completionTimeline.push({libraryId:item.id,title:cleanTitle(item.title),categoryId:item.categoryId,completedAt:item.completedAt});
        }else if(item.status==='planned') item.status='active';
      }
    });
    normalizeSeasonalLibraryItems(); persistLibrary();
  }
  persistSessions();
  const consumedCategoryIds=grouped.filter(g=>g.amount>0).map(g=>g.cat.id);
  S.currentTask=generateTask(consumedCategoryIds.length?consumedCategoryIds:[assignedCat.id]);
  S.logging=false; persistTask(); render();
}

// Source function shims for fixture data only:
let S = {}; let nextId = 0; let fixtureCategories = {};
function levelingSettings(){return {enabled:true};}
function cleanTitle(value){return String(value||'').trim();}
function clamp(n,lo,hi){return Math.max(lo,Math.min(hi,n));}
function getCategory(id){return fixtureCategories[id]||{id,unit:'units',minutesPerUnit:1};}
function categoryStatus(_cat){return {status:'healthy'};}
function calculateConsumptionXP(){return {xp:1};}
function uid(){return 'synthetic-'+(++nextId);}
function todayISO(){return '2026-10-14';}
function entriesNote(){return '';}
function persistSessions(){} function persistLibrary(){}
function persistTask(){} function render(){}
function v165ApplyRespectReward(){}
function generateTask(ids){return {categoryId:ids[0],targetMid:2};}
function normalizeSeasonalLibraryItems(){}
function v331ValidTimestamp(value){return Number(value)||0;}

import fs from 'node:fs';
import assert from 'node:assert/strict';
const fixtures=JSON.parse(fs.readFileSync(new URL('../../test/fixtures/m23_source_vectors.json',import.meta.url),'utf8'));
let checked=0;
for(const fixture of fixtures.history){
 assert.equal(v331LogicalSessionCount(fixture.sessions),fixture.expectedLogical,fixture.name+' logical');
 assert.equal(v149SessionStreakBonusForState({sessions:fixture.sessions}),fixture.expectedKnownStreakBonus,fixture.name+' XP');
 checked+=2;
}
for(const fixture of fixtures.completion){
 assert.equal(v120IsCompleted(fixture),fixture.expected,'completion');checked++;
}
for(const fixture of fixtures.contiguous){
 assert.equal(v369ContiguousProgress(fixture.start,fixture.units.map(n=>({number:n,seasonId:null,isRepeat:false})),null,fixture.total),fixture.expected,'contiguous');checked++;
}
for(const fixture of fixtures.grouping){
 fixtureCategories={};const entries=[];const library=[];
 fixture.entries.forEach((e,i)=>{
  fixtureCategories[e.categoryId]={id:e.categoryId,minutesPerUnit:e.minutesPerUnit,unit:'units'};
  const id='title-'+i;library.push({id,categoryId:e.categoryId,title:id});
  entries.push({libraryId:id,title:id,qty:e.qty,isRepeat:false});
 });
 if(!fixtureCategories[fixture.assigned])fixtureCategories[fixture.assigned]={id:fixture.assigned,minutesPerUnit:1,unit:'units'};
 S={currentTask:{categoryId:fixture.assigned,targetMid:fixture.target},
    logDraft:{entries,amount:0,minutes:fixture.minutes,note:'',updateLibrary:false},
    library,sessions:[],completionTimeline:[],logging:true};
 submitLog();
 const got=S.sessions.map(s=>({categoryId:s.categoryId,quantity:s.actualAmount,minutes:s.minutes,status:s.status}));
 assert.deepEqual(got,fixture.expected,fixture.name+' source grouped records');checked++;
}
console.log('M23_SOURCE_REFERENCE_FIXTURES_PASSED='+checked);
