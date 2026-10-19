// M24: pinned verbatim original MediaFlow source subset (not production runtime).
// Source blob SHAs identify original website code used for fixture parity.
import fs from 'node:fs';
import assert from 'node:assert/strict';
process.env.TZ = 'UTC';
const DEFAULT_SETTINGS={leveling:{unitXP:{},rotationMultiplier:{},loggingCompletionBonusXP:0}};
let S={};
function levelingSettings(){return S.settings.leveling;}
// src/js/features/xp/037-v120-completion-xp-progression-integrity.js | blob SHA 0b1d1da1741416f4ffa65aa7270e4d5cc3a7b856
function v120EnsureXPState(){
  S.settings=S.settings||{};
  S.settings.leveling=Object.assign({},DEFAULT_SETTINGS.leveling,S.settings.leveling||{});
  S.settings.leveling.unitXP=Object.assign({},DEFAULT_SETTINGS.leveling.unitXP,S.settings.leveling.unitXP||{});
  S.settings.leveling.rotationMultiplier=Object.assign({},DEFAULT_SETTINGS.leveling.rotationMultiplier,S.settings.leveling.rotationMultiplier||{});
  S.xpLedger=Object.assign({libraryAdditions:{},libraryEdits:{},manualCovers:{},logCompletions:{}},S.xpLedger||{});
  for(const k of ['libraryAdditions','libraryEdits','manualCovers','logCompletions']){
    if(!S.xpLedger[k] || typeof S.xpLedger[k]!=='object' || Array.isArray(S.xpLedger[k])) S.xpLedger[k]={};
  }
}
// src/js/features/xp/037-v120-completion-xp-progression-integrity.js | blob SHA 0b1d1da1741416f4ffa65aa7270e4d5cc3a7b856
function v120LoggedCompletionXP(){
  return Math.max(0,Math.round(Number(levelingSettings().loggingCompletionBonusXP)||0));
}
// src/js/features/xp/037-v120-completion-xp-progression-integrity.js | blob SHA 0b1d1da1741416f4ffa65aa7270e4d5cc3a7b856
function v120AwardLoggedCompletionXP(itemId){
  if(!itemId || levelingSettings().enabled===false) return 0;
  v120EnsureXPState();
  const ledger=S.xpLedger.logCompletions;
  if(Object.prototype.hasOwnProperty.call(ledger,itemId)) return 0;
  const xp=v120LoggedCompletionXP();
  ledger[itemId]=xp; // Store even 0 so changing Settings later cannot re-award an old completion.
  return xp;
}
// src/js/components/231-v331-per-title-logging-timestamps.js | blob SHA a14fa28e486827ffc7ccf576117520906239b7b0
function v331ValidTimestamp(value){
  const n=Number(value);
  return Number.isFinite(n)&&n>=946684800000&&n<=Date.now()+86400000?n:0;
}
// src/js/components/231-v331-per-title-logging-timestamps.js | blob SHA a14fa28e486827ffc7ccf576117520906239b7b0
function v331EventDate(session,row){
  // Use each row's own day for its consumption card; the containing
  // session retains its original calendar group and Statistics count.
  const ts=v331ValidTimestamp(row?.loggedAt);
  const raw=String(session?.date||'');
  const day=/^\d{4}-\d{2}-\d{2}$/.test(raw)?new Date(`${raw}T12:00:00`):null;
  return ts?new Date(ts):day&&Number.isFinite(day.getTime())?day:new Date(Number(session?.timestamp)||Date.now());
}
const cases=JSON.parse(fs.readFileSync(new URL('../../test/fixtures/m24_ledger_clock_vectors.json',import.meta.url),'utf8'));
let tested=0;
for(const f of cases.completionLedgers){
 S={settings:{leveling:{enabled:f.enabled,loggingCompletionBonusXP:f.rate}},xpLedger:{logCompletions:{...f.existing}}};
 const got=f.ops.map(id=>v120AwardLoggedCompletionXP(id));
 assert.deepEqual(got,f.awards, f.name+' award amounts');
 assert.deepEqual(S.xpLedger.logCompletions,f.ledger,f.name+' ledger state');
 tested+=2;
}
for(const f of cases.historyClocks){
 const realNow=Date.now;
 Date.now=()=>f.now;
 try {
  const record={date:f.sessionDate,timestamp:f.sessionTimestamp};
  const row={loggedAt:f.rowTimestamp};
  assert.equal(v331EventDate(record,row).getTime(),f.expected,f.name);
  tested++;
 } finally {Date.now=realNow;}
}
console.log('M24_PINNED_SOURCE_FIXTURES_PASSED='+tested);
