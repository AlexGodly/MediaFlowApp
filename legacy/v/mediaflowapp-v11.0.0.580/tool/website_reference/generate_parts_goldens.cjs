#!/usr/bin/env node
/* Golden fixtures for titles logged by parts (website v577), from the REAL
 * website: its Batch Log in "Progress reached" mode, filled the way its form
 * fills rows (pick the title, then each part's reached number), on the seed
 * account with a by-parts title. test/parts_golden_test.dart requires the app
 * to write the same records.
 *   MF_ROOT=/path/to/MediaFlow node tool/website_reference/generate_parts_goldens.cjs
 * (MF_ROOT: a built website checkout; uses its tests/harness.) */
'use strict';
const fs=require('node:fs'),path=require('node:path');
const ROOT=process.env.MF_ROOT;
if(!ROOT)throw Error('Set MF_ROOT to a built MediaFlow website checkout');
const {openApp}=require(path.join(ROOT,'tests/harness/app.cjs'));
const OUT=path.resolve(__dirname,'../../test/fixtures');
const seed=JSON.parse(fs.readFileSync(path.join(__dirname,'seed-account.json'),'utf8'));
const proto=seed.library[0];

function account(){
  const a=JSON.parse(JSON.stringify(seed));
  a.library=[
    {...proto,id:'lib_parts',title:'Valorant',categoryId:'tv',status:'active',progress:45,total:null,mf577LogMode:'parts',
      mf565Unit:'sessions',mf565SecondsPerUnit:1800,seasonSource:'manual',seasonViewEnabled:true,seasons:[
        {id:'pc',number:null,name:'Competitive',progress:41,total:null,source:'manual',manual:true,synthetic:false,mf577Kind:'Mode',mf577Unit:'matches',mf577SecondsPerUnit:2400},
        {id:'pu',number:null,name:'Unrated',progress:4,total:10,source:'manual',manual:true,synthetic:false,mf577Kind:'Mode'},
        {id:'pd',number:null,name:'Deathmatch',progress:0,total:null,source:'manual',manual:true,synthetic:false,mf577Kind:'Mode',mf577SecondsPerUnit:600}]},
    {...proto,id:'lib_plain',title:'Plain Show',categoryId:'tv',status:'active',progress:3,total:10},
  ];
  a.sessions=[];
  delete a.resumeStateV285;delete a.currentTask;a.sessionActive=false;
  return a;
}
const SCENARIOS=[
  // Two parts of one title in one row, plus a normal title.
  ['parts-batch',[{libraryId:'lib_parts',parts:[{id:'pc',reached:44},{id:'pu',reached:6}]},{libraryId:'lib_plain',reached:5}]],
  // A part capped at its total, and a part with its own time.
  ['parts-capped',[{libraryId:'lib_parts',parts:[{id:'pu',reached:12},{id:'pd',reached:3}]}]],
];
const strip=s=>{const o=JSON.parse(JSON.stringify(s));for(const k of ['resumeStateV285','savedAt','portableExtras','__mfAndroidCompanionDraftV1','v556','mf556'])delete o[k];return o;};

(async()=>{
  for(const [name,rows] of SCENARIOS){
    const app=await openApp({state:account()});
    const p=app.page;
    try{
      await p.waitForTimeout(800);
      const fx=await p.evaluate(async rows=>{
        const S=__MF.S(),get=__MF.get,snap=()=>JSON.parse(JSON.stringify(get('snapshot')()));
        const before=snap(),now=Date.now();
        S.view='batch';
        S.batchDraft={rows:rows.map(()=>({libraryId:'',query:'',qty:1,minutes:0})),note:'parts golden',date:get('todayISO')(),v179Mode:'progress'};
        rows.forEach((r,i)=>{
          App.selectBatchTitle(i,r.libraryId);
          if(r.parts){
            const want=r.parts.map(x=>x.id);
            for(const id of want)if(!(S.batchDraft.rows[i].mf577Parts||[]).some(m=>m.id===id))App.mf577BatchToggle(i,id);
            for(const m of [...(S.batchDraft.rows[i].mf577Parts||[])])if(!want.includes(m.id))App.mf577BatchToggle(i,m.id);
            for(const x of r.parts)App.mf577BatchSet(i,x.id,x.reached);
          }else App.v179UpdateBatchProgress(i,r.reached);
        });
        const filled=JSON.parse(JSON.stringify(S.batchDraft.rows));
        App.submitBatchLog();
        await new Promise(r=>setTimeout(r,1500));
        return {now,before,after:snap(),filled};
      },rows);
      const out={now:fx.now,timezone:'UTC',note:'parts golden',rows,filled:fx.filled,before:strip(fx.before),after:strip(fx.after)};
      fs.writeFileSync(path.join(OUT,'log-'+name+'.json'),JSON.stringify(out,null,1)+'\n');
      console.log(name,out.before.sessions.length,'->',out.after.sessions.length,'sessions');
    }finally{await app.close();}
  }
})().catch(e=>{console.error(e);process.exit(1);});
