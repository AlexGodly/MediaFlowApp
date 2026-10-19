// M29 source-pinned, read-only original v410 JavaScript reference functions.
// Original repository: AlexGodly/MediaFlow. No production data or remote calls.
import fs from 'node:fs';
import assert from 'node:assert/strict';
const sourcePins=[{"path":"src/js/features/scheduler/007-scheduler.js","blob":"e31f88e77690197312bf25ab95f32c996cf4e65f"},{"path":"src/js/components/186-v252-seasons-view.js","blob":"824532397930f148054eb8bdc202cb4bd83bf1fe"},{"path":"src/js/components/267-v369-itemized-logging.js","blob":"d1ba6a7a02216aa357d40a2cefd63f2f575b5aa3"},{"path":"src/js/components/288-v394-advanced-logging.js","blob":"ed226e4895db34d0c36e8130676dc456fb97ec9e"},{"path":"src/js/components/245-v348-universal-streak-action-xp.js","blob":"5a436d205417ea36f8c39e896925fefef24c0901"}];
const input=JSON.parse(fs.readFileSync(new URL('../../test/fixtures/m29_business_rules_vectors.json', import.meta.url),'utf8'));
assert.equal(input.schema,'m29-v410-pinned-reference-v1');
let S={}, awarded=[], idCounter=0;
function uid(){return 'synthetic-'+(++idCounter);}
function cleanTitle(x){return String(x||'').trim();}
function clamp(value,lo,hi){return Math.max(lo,Math.min(hi,value));}
function lastSessionFor(id){return schedulerConsumptionSessions().filter(s=>s.categoryId===id)
  .sort((a,b)=>(Number(b.timestamp)||0)-(Number(a.timestamp)||0))[0]||null;}
function daysSince(ts){return ts==null?Infinity:Math.max(0,(Date.now()-Number(ts))/86400000);}
function v274TouchCollection(collection){return collection;}
function v348SnapshotMaps(){return {};}
function v348RaiseNewRewards(){}
function v348Award(kind,qty=1){awarded.push([kind,qty]);return 0;}
let V348_SUPPRESS_IMPORTED_ACTIONS=0,V348_COLLECTION_KNOWN=null,V348_ORDER_KNOWN=null;
function schedulerLogicalEvents(){
  const rows=schedulerConsumptionSessions().slice().sort((a,b)=>(Number(b.timestamp)||0)-(Number(a.timestamp)||0));
  const groups=new Map();
  for(const s of rows){
    const key=s.sessionGroupId ? `group:${s.sessionGroupId}` : `session:${s.id||uid()}`;
    if(!groups.has(key)) groups.set(key,{key,timestamp:Number(s.timestamp)||0,categoryIds:new Set(),sessions:[]});
    const g=groups.get(key);
    g.timestamp=Math.max(g.timestamp,Number(s.timestamp)||0);
    if(s.categoryId) g.categoryIds.add(s.categoryId);
    g.sessions.push(s);
  }
  return [...groups.values()].sort((a,b)=>b.timestamp-a.timestamp);
}

function recentTaskWindow(n){
  return schedulerLogicalEvents().slice(0,n);
}

function schedulerConsumptionSessions(){
  return S.sessions.filter(s=>s && s.status!=='skipped' && ((Number(s.minutes)||0)>0 || (Number(s.actualAmount)||0)>0));
}

function categoryBalance(cat){
  const enabled=(typeof v186ScopeCategories==='function'?v186ScopeCategories('scheduler'):S.categories.filter(c=>c.enabled));
  const weightTotal=enabled.reduce((a,c)=>a+Math.max(0.25,Number(c.weight)||1),0) || 1;
  const desiredShare=Math.max(0.25,Number(cat.weight)||1)/weightTotal;
  const all=schedulerConsumptionSessions();
  const now=Date.now();

  // Recent behavior matters most, but lifetime history remains a real signal.
  const windows=[
    {days:3, weight:.35, minMinutes:60},
    {days:7, weight:.25, minMinutes:120},
    {days:30, weight:.20, minMinutes:240},
    {days:null, weight:.20, minMinutes:1}
  ];

  let ratioSum=0, usedWeight=0;
  const detail={};
  for(const w of windows){
    const rows=w.days==null ? all : all.filter(x=>Number(x.timestamp)>=now-w.days*86400000);
    const totalMinutes=rows.reduce((a,x)=>a+Math.max(0,Number(x.minutes)||0),0);
    const catMinutes=rows.filter(x=>x.categoryId===cat.id).reduce((a,x)=>a+Math.max(0,Number(x.minutes)||0),0);
    const key=w.days==null?'lifetime':`${w.days}d`;
    const actualShare=totalMinutes>0 ? catMinutes/totalMinutes : 0;
    const ratio=desiredShare>0 ? actualShare/desiredShare : 1;
    detail[key]={totalMinutes,catMinutes,actualShare,ratio};
    if(totalMinutes>=w.minMinutes){ ratioSum+=Math.min(6,ratio)*w.weight; usedWeight+=w.weight; }
  }

  const consumptionRatio=usedWeight>0 ? ratioSum/usedWeight : 1;
  const last=lastSessionFor(cat.id);
  const daysIdle=daysSince(last?last.timestamp:null);
  return {desiredShare,consumptionRatio,daysIdle,detail};
}

function computeScores(excludeIds){
  excludeIds = excludeIds || [];
  const st = S.settings;
  let pool = (typeof v186ScopeCategories==='function'?v186ScopeCategories('scheduler'):S.categories.filter(c=>c.enabled)).filter(c=>!excludeIds.includes(c.id));
  if(pool.length===0) pool = (typeof v186ScopeCategories==='function'?v186ScopeCategories('scheduler'):S.categories.filter(c=>c.enabled));
  const recentWindow = recentTaskWindow(6);
  const logicalChron = schedulerLogicalEvents();

  return pool.map(cat=>{
    const last = lastSessionFor(cat.id);
    const dSince = daysSince(last ? last.timestamp : null);
    const neglectBonus = last ? Math.min(st.neglectCap, dSince*st.neglectRate) : st.neglectCap;

    // v90: a category can count at most once per user logging action, even when
    // that action produced several category-specific session rows.
    const occurrences = recentWindow.filter(e=>e.categoryIds.has(cat.id)).length;
    const repetitionPenalty = occurrences * st.repetitionPenalty;

    // Consecutive use is also measured in logical logging actions. A mixed log
    // therefore says “these categories were consumed together”, not that they
    // were consumed as several arbitrary back-to-back sessions.
    let logicalStreakLen=0;
    for(const e of logicalChron){
      if(e.categoryIds.has(cat.id)) logicalStreakLen++;
      else break;
    }
    const consecutivePenalty = logicalStreakLen * st.consecutivePenalty;

    const balance=categoryBalance(cat);
    // Ratio 1 = on balance. Above 1 = category owns too much consumption time.
    // Below 1 = underrepresented. Cap both sides so one binge never permanently locks a category out.
    const overRatio=Math.max(0,balance.consumptionRatio-1);
    const underRatio=Math.max(0,1-balance.consumptionRatio);
    const saturationPenalty=Math.min(70,overRatio*st.saturationWeight*2.2);
    const balanceBonus=Math.min(28,underRatio*st.neglectCap*.55);

    const seasonalBonus = cat.seasonal ? (st.seasonalBonus + st.seasonalFreshCount*4) : 0;
    const weightScore = cat.weight * 8;
    const raw = weightScore + neglectBonus + balanceBonus + seasonalBonus - repetitionPenalty - consecutivePenalty - saturationPenalty;
    const floored = Math.max(raw, 1.5);
    const jitter = floored * (Math.random()*st.randomness*2 - st.randomness);
    const final = Math.max(floored + jitter, 0.5);

    const reasons = [];
    if(!last) reasons.push({t:'Never consumed yet', w: st.neglectCap});
    else if(dSince>=1) reasons.push({t:`Neglected for ${Math.floor(dSince)}d`, w: neglectBonus});
    if(balance.consumptionRatio>=1.35) reasons.push({t:'Overrepresented across your consumption history — cooling off',w:-saturationPenalty});
    else if(balance.consumptionRatio<=.70 && last) reasons.push({t:'Underrepresented in your overall consumption — catching up',w:balanceBonus});
    if(cat.seasonal && st.seasonalFreshCount>0) reasons.push({t:`${st.seasonalFreshCount} seasonal title(s) have fresh episodes`, w: seasonalBonus});
    else if(cat.seasonal) reasons.push({t:'Time-sensitive — airing now', w: seasonalBonus});
    if(repetitionPenalty+consecutivePenalty>4) reasons.push({t:'Appeared often in recent tasks', w: -(repetitionPenalty+consecutivePenalty)});
    reasons.sort((a,b)=>Math.abs(b.w)-Math.abs(a.w));

    return {cat, score: final, reasons: reasons.slice(0,3), debug:{neglectBonus,repetitionPenalty,consecutivePenalty,saturationPenalty,seasonalBonus,weightScore,balanceBonus,balanceRatio:balance.consumptionRatio}};
  });
}

// ---- NEXT ORIGINAL SOURCE BLOCK ----

function suggestedAmount(cat){
  const t=Math.max(1,Number(cat.target)||1);
  const balance=categoryBalance(cat);
  const ratio=balance.consumptionRatio;
  const idle=balance.daysIdle;

  // Amount is self-correcting too: overconsumed categories shrink, neglected ones grow.
  // Recent windows dominate, lifetime history prevents a long binge from being forgotten overnight.
  let mult=1;
  if(ratio>=2.5) mult*=.50;
  else if(ratio>=1.8) mult*=.62;
  else if(ratio>=1.35) mult*=.78;
  else if(ratio<=.45) mult*=1.35;
  else if(ratio<=.70) mult*=1.18;

  // Time since last consumption adds a gradual catch-up boost with diminishing returns.
  if(Number.isFinite(idle)){
    if(idle>=60) mult*=1.65;
    else if(idle>=30) mult*=1.50;
    else if(idle>=14) mult*=1.32;
    else if(idle>=7) mult*=1.18;
  }else{
    mult*=1.5;
  }

  // Keep correction gradual. MediaFlow should rebalance over rotations, not create giant debt sessions.
  mult=clamp(mult,.45,2.0);
  const center=Math.max(1,Math.round(t*mult));
  let low,high;
  if(center<=2){ low=center; high=center; }
  else{
    low=Math.max(1,Math.round(center*.85));
    high=Math.max(low,Math.round(center*1.15));
  }

  const direction=mult<.9?'reduced':mult>1.1?'increased':'normal';
  return {low,high,multiplier:mult,direction,balanceRatio:ratio,daysIdle:idle};
}

// ---- NEXT ORIGINAL SOURCE BLOCK ----

function v252Num(value,fallback=0){const n=Number(value);return Number.isFinite(n)?Math.max(0,Math.round(n)):fallback;}
function v252SeasonNumberValue(value){
  if(value===null||value===undefined||String(value).trim()==='')return null;
  const n=Number(value);return Number.isFinite(n)?Math.max(0,Math.round(n)):null;
}
function v252SeasonLabel(season,index=0){
  const name=cleanTitle(String(season?.name||season?.title||'').trim());
  if(name)return name;
  const n=v252SeasonNumberValue(season?.number);
  if(n===0)return 'Specials';
  if(n!=null)return `Season ${n}`;
  return `Season ${index+1}`;
}
function v252NormalizeSeason(raw,index=0,source='manual'){
  const row=(raw&&typeof raw==='object')?raw:{};
  const number=v252SeasonNumberValue(row.number??row.season??row.season_number??row.seasonNumber);
  const explicitTotal=row.total??row.totalEpisodes??row.total_episodes??row.total_episodes_count??row.episodes_count??row.episode_count;
  const total=(explicitTotal===null||explicitTotal===undefined||String(explicitTotal).trim()==='')?null:v252Num(explicitTotal,0);
  let progress=v252Num(row.progress??row.watchedEpisodes??row.watched_episodes??row.watched_episodes_count??row.episodes_watched,0);
  if(total!=null&&total>0)progress=Math.min(progress,total);
  return {
    id:String(row.id||row.seasonId||row.season_id||v252SeasonUid()),
    number,
    name:v252SeasonLabel(Object.assign({},row,{number}),index),
    progress,
    total:total!=null&&total>0?total:(total===0?0:null),
    source:String(row.source||source||'manual'),
    manual:row.manual===true||String(row.source||source||'')==='manual',
    synthetic:row.synthetic===true
  };
}
function v252SortSeasons(rows){
  return rows.map((s,i)=>({s,i})).sort((a,b)=>{
    const an=a.s.number,bn=b.s.number;
    if(an==null&&bn==null)return a.i-b.i;
    if(an==null)return 1;if(bn==null)return -1;
    return an-bn||a.i-b.i;
  }).map(x=>x.s);
}
function v252NormalizeSeasons(raw,source='manual'){
  const list=Array.isArray(raw)?raw:[];
  const seen=new Set();
  const out=[];
  list.forEach((row,index)=>{
    const s=v252NormalizeSeason(row,index,source);
    let key=s.number!=null?`n:${s.number}`:`name:${String(s.name||'').toLowerCase()}`;
    if(seen.has(key))key=`${key}:${index}`;
    seen.add(key);out.push(s);
  });
  return v252SortSeasons(out);
}
function v252Seasons(item){return v252NormalizeSeasons(item?.seasons,item?.seasonSource||'manual');}
function v252HasSeasons(item){return v252Seasons(item).length>0;}
function v252SeasonAggregate(rows){
  const seasons=v252NormalizeSeasons(rows);
  let progress=0,total=0,knownTotals=0;
  for(const season of seasons){
    progress+=v252Num(season.progress,0);
    const t=season.total==null?0:v252Num(season.total,0);
    total+=t;if(t>0)knownTotals++;
  }
  return {progress,total:total>0?total:null,knownTotals,count:seasons.length};
}

// ---- NEXT ORIGINAL SOURCE BLOCK ----

function v252SeasonOffset(item,seasonId){
  const seasons=v252Seasons(item);let offset=0;
  for(const season of seasons){
    if(String(season.id)===String(seasonId))break;
    offset+=season.total!=null&&Number(season.total)>0?Number(season.total):Number(season.progress)||0;
  }
  return Math.max(0,Math.round(offset));
}

// ---- NEXT ORIGINAL SOURCE BLOCK ----

function v369Seconds(unit){
  if(Number.isFinite(Number(unit?.durationSeconds)))return Math.max(0,Math.floor(Number(unit.durationSeconds)));
  return Math.max(0,Math.round((Number(unit?.minutes)||0)*60));
}

// ---- NEXT ORIGINAL SOURCE BLOCK ----

function v394ExactContiguous(units,base){
  const sorted=[...units].map(u=>Math.floor(Number(u.number)||0)).sort((a,b)=>a-b);
  return sorted.every((n,i)=>n===base+i+1);
}

// ---- NEXT ORIGINAL SOURCE BLOCK ----

function v394RuntimeForEntry(e){
  const actual=(e.v369Units||[]).reduce((n,u)=>n+v369Seconds(u),0);
  if(e.v394RuntimeManual && (e.v369Units||[]).length){
    const total=Number(e.v394RuntimeSeconds);
    if(Number.isFinite(total)&&total>=0)return Math.round(total);
  }
  return actual;
}

// ---- NEXT ORIGINAL SOURCE BLOCK ----

function v348CollectionIds(c){const list=Array.isArray(c?.order)&&c.order.length?c.order:c?.titleIds;return (Array.isArray(list)?list:[]).map(String);}
function v348SeedCollections(){V348_COLLECTION_KNOWN=new Map((S.collections||[]).filter(c=>c?.id).map(c=>[String(c.id),v348CollectionIds(c)]));}
const v348TouchCollectionBase=v274TouchCollection;
v274TouchCollection=function(c){
  if(!c?.id)return v348TouchCollectionBase.apply(this,arguments);
  if(!V348_COLLECTION_KNOWN)v348SeedCollections();
  const id=String(c.id),before=V348_COLLECTION_KNOWN.get(id);
  const rewards=v348SnapshotMaps(['v334CollectionCreates','v334CollectionEdits']);
  const result=v348TouchCollectionBase.apply(this,arguments);
  v348RaiseNewRewards(rewards);
  const after=v348CollectionIds(c);
  if(before && !V348_SUPPRESS_IMPORTED_ACTIONS && String(S.view||'')==='collections'){
    const previous=new Set(before),added=after.filter(x=>!previous.has(x));
    if(added.length)v348Award('collectionAddTitleXP',added.length,{subjectId:id,description:added.map(tid=>(S.library||[]).find(it=>String(it.id)===tid)?.title||tid).slice(0,8).join(', ')});
    const oldCommon=before.filter(x=>after.includes(x)),newCommon=after.filter(x=>previous.has(x));
    if(oldCommon.length>1&&oldCommon.join('\0')!==newCommon.join('\0'))v348Award('collectionReorderTitleXP',1,{subjectId:id,description:String(c.title||'Collection')});
  }
  V348_COLLECTION_KNOWN.set(id,after);
  return result;
};

// Observe canonical Personal Order writes across List/Tabs/drag/numeric inputs.
// Snapshot the previous saved sequence before each mutation, compare at the
// actual save touch, and never pay for unrelated display-only preference edits.

// ---- NEXT ORIGINAL SOURCE BLOCK ----

function v348OrderSnapshot(){
  const p=S.orderPlan||{};
  return {titles:(p.titleIds||[]).map(String),assignments:(p.collectionAssignments||[]).map(a=>String(a?.id||'')).filter(Boolean),queues:Object.fromEntries(Object.entries(p.categoryQueues||{}).map(([k,q])=>[k,Array.isArray(q)?q.map(String):[]]))};
}
function v348SeedOrder(){V348_ORDER_KNOWN=v348OrderSnapshot();}
function v348CompareOrder(){
  const next=v348OrderSnapshot(),prev=V348_ORDER_KNOWN;
  if(!prev||V348_SUPPRESS_IMPORTED_ACTIONS||String(S.view||'')!=='order'){V348_ORDER_KNOWN=next;return;}
  const titles=new Set(prev.titles),nowTitles=new Set(next.titles);
  const addedTitleIds=next.titles.filter(x=>!titles.has(x)),added=addedTitleIds.length;
  if(added)v348Award('orderAddTitleXP',added,{description:addedTitleIds.map(id=>(S.library||[]).find(it=>String(it.id)===id)?.title||id).slice(0,8).join(', ')});
  const oldCommon=prev.titles.filter(x=>nowTitles.has(x)),newCommon=next.titles.filter(x=>titles.has(x));
  if(oldCommon.length>1&&oldCommon.join('\0')!==newCommon.join('\0'))v348Award('orderReorderTitleXP',1,{description:'Reordered Personal Order title sequence'});
  const assignments=new Set(prev.assignments),nowAssignments=new Set(next.assignments);
  const newlyAssignedIds=next.assignments.filter(x=>!assignments.has(x)),newlyAssigned=newlyAssignedIds.length;
  if(newlyAssigned)v348Award('orderAddCollectionXP',newlyAssigned,{description:newlyAssignedIds.map(id=>{const a=(S.orderPlan?.collectionAssignments||[]).find(r=>String(r.id)===id);return (S.collections||[]).find(c=>String(c.id)===String(a?.collectionId))?.title||id;}).slice(0,8).join(', ')});
  if(!newlyAssigned){
    const allKeys=new Set([...Object.keys(prev.queues),...Object.keys(next.queues)]);
    for(const key of allKeys){
      const old=prev.queues[key]||[],current=next.queues[key]||[];
      const oldCollections=old.filter(x=>x.startsWith('c:')&&current.includes(x));
      const newCollections=current.filter(x=>x.startsWith('c:')&&old.includes(x));
      const positionChanged=oldCollections.some(token=>old.indexOf(token)!==current.indexOf(token));
      if((oldCollections.length>1&&oldCollections.join('\0')!==newCollections.join('\0'))||positionChanged){v348Award('orderReorderCollectionXP',1,{description:'Moved Collection queue position'});break;}
    }
  }
  V348_ORDER_KNOWN=next;
}
const originalNow=Date.now;
Date.now=()=>input.scheduler.nowMillis;
try {
  const plan=input.scheduler;
  S={categories:structuredClone(plan.categories),settings:structuredClone(plan.settings),
    sessions:plan.sessions.map(s=>({...s,timestamp:plan.nowMillis-s.daysAgo*86400000}))};
  const logical=schedulerLogicalEvents();
  assert.equal(logical.length,plan.expected.logicalEventCount,'v90 logical events');
  assert.deepEqual([...logical[0].categoryIds].sort(),plan.expected.groupedTopCategories);
  for(const cat of S.categories){
    const suggestion=suggestedAmount(cat);
    assert.deepEqual({low:suggestion.low,high:suggestion.high,direction:suggestion.direction},
      plan.expected.suggested[cat.id], 'suggestedAmount '+cat.id);
    const score=computeScores([]).find(x=>x.cat.id===cat.id)?.score;
    assert(score>=plan.expected.scores[cat.id].min&&score<=plan.expected.scores[cat.id].max,
      'source scheduler score '+cat.id+': '+score);
  }
  S.sessions=[];
  const empty=suggestedAmount(S.categories[0]);
  assert.deepEqual({low:empty.low,high:empty.high,direction:empty.direction},
    (({low,high,direction})=>({low,high,direction}))(input.emptyScheduler.expected.anime));
  assert.equal(computeScores([])[0].score,input.emptyScheduler.expected.anime.score);

  const season=input.seasons,s=v252NormalizeSeasons(season.rows);
  assert.deepEqual(s.map(x=>x.id),season.expected.ids);
  assert.deepEqual(s.map(x=>x.number),season.expected.numbers);
  assert.deepEqual(s.map(x=>x.name),season.expected.names);
  assert.deepEqual(s.map(x=>x.progress),season.expected.progress);
  assert.deepEqual(v252SeasonAggregate(season.rows),season.expected.aggregate);
  assert.equal(v252SeasonOffset({seasons:season.rows},'s2'),season.expected.s2Offset);

  const adv=input.advanced;
  assert.equal(v394ExactContiguous(adv.contiguous,adv.base),adv.expected.exact);
  assert.equal(v394ExactContiguous(adv.gapped,adv.base),adv.expected.gapExact);
  assert.equal(v394RuntimeForEntry({v369Units:adv.units}),adv.expected.seconds);
  assert.equal(v394RuntimeForEntry({v369Units:adv.units,
    v394RuntimeManual:true,v394RuntimeSeconds:360}),adv.expected.manualSeconds);

  const col=input.actions.collection;
  S={view:'collections',collections:[{id:'c1',title:'Synthetic',
    titleIds:[...col.before]}],library:[]};
  v348SeedCollections(); S.collections[0].order=[...col.after];
  awarded=[];v274TouchCollection(S.collections[0]);
  assert.deepEqual(awarded,col.expected,'v348 collection reward triggers');

  const o=input.actions.order;
  S={view:'order',collections:[],library:[],orderPlan:{
    titleIds:[...o.beforeTitles],collectionAssignments:structuredClone(o.beforeAssignments),
    categoryQueues:structuredClone(o.beforeQueues)}};
  v348SeedOrder();awarded=[];
  S.orderPlan.titleIds=[...o.afterTitles];
  S.orderPlan.collectionAssignments=structuredClone(o.afterAssignments);
  v348CompareOrder();
  S.orderPlan.categoryQueues=structuredClone(o.afterQueues);
  v348CompareOrder();
  assert.deepEqual(awarded,o.expected,'v348 order reward triggers');
  console.log('M29_PINNED_SOURCE_FIXTURES_PASSED=4_domains');
} finally {Date.now=originalNow;}
