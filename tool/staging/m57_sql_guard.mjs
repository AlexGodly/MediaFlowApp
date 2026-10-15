// M57: CI safety guard only; no SQL or network execution.
import assert from 'node:assert/strict';
import fs from 'node:fs';
const read=p=>fs.readFileSync(p,'utf8');
const sql=read('tool/staging/m57_ephemeral_atomic_sync.sql');
const pg=read('test/staging/m57_pg_integration.sql');
const race=read('tool/staging/m57_pg_concurrency.mjs');
const workflow=read('.github/workflows/m57-postgres-staging.yml');
const native=read('lib/services/native_cas_protocol.dart');
const shared=read('lib/services/native_m30_shared_sync.dart');
const documentation=read('docs/MILESTONE_57.md');
const files=['tool/staging/m57_ephemeral_atomic_sync.sql',
  'test/staging/m57_pg_integration.sql',
  'tool/staging/m57_pg_concurrency.mjs'];
const must=(value,phrase,name)=>assert(value.includes(phrase),
  name+' missing: '+phrase);
for(const f of files)assert(fs.existsSync(f),f);
must(sql,'CREATE SCHEMA IF NOT EXISTS m57_staging','SQL');
must(sql,'m57_staging.operation_receipts','SQL');
assert.equal(sql.split('CREATE TABLE IF NOT EXISTS m57_staging.operation_receipts').length,2,
  'SQL receipts must have a single definition');
assert.equal(sql.split('CREATE OR REPLACE FUNCTION m57_staging.commit_state').length,2,
  'SQL commit function must have a single definition');
must(sql,"CHECK (state_digest ~ '^[0-9a-f]{64}$'),",'SQL');
must(sql,'CREATE TRIGGER m57_digest_before_state_write','SQL');
must(sql,'m57_staging.set_state_digest()','SQL');
must(sql,'FOR UPDATE','SQL');
must(sql,'auth.uid()','SQL');
must(sql,'SECURITY DEFINER SET search_path =','SQL');
must(sql,'SECURITY INVOKER SET search_path =','SQL');
must(sql,'REVOKE ALL ON ALL TABLES IN SCHEMA m57_staging','SQL');
must(sql,'GRANT EXECUTE ON FUNCTION public.m57_stage_commit','SQL');
must(sql,'operation_id_mismatch','SQL');
must(sql,'replayed','SQL');
must(sql,'conflict','SQL');
must(sql,'pg_catalog.sha256','SQL');
must(sql,'pg_catalog.jsonb_build_array','SQL');
assert(!sql.includes('CREATE TABLE public.mediaflow_states'));
assert(!sql.includes('UPDATE public.mediaflow_states'));
assert(!sql.includes('INSERT INTO public.mediaflow_states'));
assert(!sql.includes('ALTER TABLE public.mediaflow_states'));
assert(!sql.includes('DROP TABLE public.mediaflow_states'));
assert(!sql.includes('GRANT ALL ON ALL TABLES'));
assert(!sql.includes('SECURITY DEFINER SET search_path = public'));
must(pg,'CREATE ROLE authenticated','pg test');
must(pg,'SET ROLE authenticated','pg test');
must(pg,'SET ROLE anon','pg test');
must(pg,'Operation ID poisoning','pg test');
must(pg,'unknownFuture','pg test');
must(pg,'M57_POSTGRES_STAGING_SQL_ASSERTIONS_PASSED','pg test');
must(race,"assert.equal(process.env.PGHOST,'127.0.0.1'","race test");
must(race,"['applied','conflict']","race test");
must(workflow,'postgres:17','CI');
must(workflow,'M57 isolated PostgreSQL','CI');
must(workflow,'node tool/staging/m57_sql_guard.mjs','CI');
must(workflow,'m57_pg_integration.sql','CI');
must(workflow,'m57_pg_concurrency.mjs','CI');
assert(!workflow.includes('SUPABASE_URL'));
assert(!workflow.includes('SUPABASE_SERVICE_ROLE_KEY'));
assert(!workflow.includes('supabase db push'));
assert(!workflow.includes('apply_migration'));
assert(!workflow.includes('https://')); // No external database endpoint.
must(native,'cloudWritesEnabled = false','native');
must(native,'hasServerSideCas = false','native');
must(native,'offlineWriteQueueEnabled = false','native');
must(shared,'static const bool deployed = false','native');
must(documentation,'NOT DEPLOYED','docs');
console.log('M57_STAGING_ONLY_SQL_GUARD_PASSED');
