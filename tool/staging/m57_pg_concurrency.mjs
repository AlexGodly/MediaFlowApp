// M57: connect ONLY to localhost ephemeral CI PostgreSQL.
// Uses fabricated owners and JSON; never accepts a remote database URI.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import crypto from 'node:crypto';
assert.equal(process.env.PGHOST,'127.0.0.1',
  'M57 tests require localhost; remote Supabase is forbidden');
const BASE_ARGS=['-h','127.0.0.1','-U','postgres','-d','postgres',
  '-X','-A','-t','-v','ON_ERROR_STOP=1'];
const env={...process.env,PGPASSWORD:'m57_ephemeral_ci'};
const run=(sql)=>execFileSync('psql',[...BASE_ARGS,'-c',sql],
  {encoding:'utf8',env}).trim().split('\n').filter(Boolean).at(-1);
const concurrent=(sql)=>new Promise((resolve,reject)=>{
  const p=spawn('psql',[...BASE_ARGS,'-c',sql],{env});
  let out='',err='';
  p.stdout.on('data',d=>out+=d);
  p.stderr.on('data',d=>err+=d);
  p.on('error',reject);
  p.on('close',code=>{
    if(code!==0)return reject(new Error(err));
    resolve(out.trim().split('\n').filter(Boolean).at(-1));
  });
});
const A='11111111-1111-4111-8111-111111111111';
const B='22222222-2222-4222-8222-222222222222';
const login=owner=>\`SET ROLE authenticated; SET request.jwt.claim.sub='\${owner}';\`;
const read=owner=>{
  const fields=run(\`\${login(owner)} SELECT revision||'|'||state_digest FROM public.m57_stage_read();\`);
  const [revision,digest]=fields.split('|');
  return {revision:Number(revision),digest};
};
const commitSql=(owner,anchor,op,next)=>\`\${login(owner)}
  SELECT status||'|'||COALESCE(revision::text,'') FROM public.m57_stage_commit(
    '\${op}'::uuid,\${anchor.revision},'\${anchor.digest}',
    '\${JSON.stringify(next).replaceAll("'","''")}'::jsonb);\`;
const before=read(A);
const nextDoc={library:[{id:'A',priority:'medium',unknownFuture:{nested:[1,null,true]}}],
  sessions:[],xpLedger:{events:[]},futureRoot:'opaque',stagingOnlyVersion:'m57'};
const result=await Promise.all([
  concurrent(commitSql(A,before,crypto.randomUUID(),nextDoc)),
  concurrent(commitSql(A,before,crypto.randomUUID(),
    {...nextDoc,stagingOnlyVersion:'other-device'})),
]);
assert.deepEqual(result.map(v=>v.split('|')[0]).sort(),['applied','conflict']);
assert.equal(read(A).revision,before.revision+1);
assert.equal(read(B).revision,1);
const rows=Number(run(\`SELECT count(*) FROM m57_staging.operation_receipts
 WHERE owner_id='\${A}';\`));
assert.equal(rows,2,'One existing SQL test receipt and one concurrent receipt');
const unreadable=run(\`SELECT state_data->>'futureRoot' FROM
  m57_staging.account_states WHERE owner_id='\${A}';\`);
assert.equal(unreadable,'opaque');
console.log('M57_POSTGRES_CONCURRENT_CLIENTS_PASSED',
 JSON.stringify({results:result,ownerARevision:read(A).revision,
 ownerBRevision:read(B).revision,receiptRows:rows}));
