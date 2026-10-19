-- EPHEMERAL POSTGRES ONLY: mock a Supabase JWT owner for CI.
-- All identifiers and account JSON here are fabricated for tests.
-- Do not run against an actual Supabase project.
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE SECURITY INVOKER
AS $$
  SELECT NULLIF(pg_catalog.current_setting(
      'request.jwt.claim.sub',true),'')::uuid;
$$;
GRANT USAGE ON SCHEMA auth TO authenticated,anon;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated,anon;

\i tool/staging/m57_ephemeral_atomic_sync.sql

INSERT INTO m57_staging.account_states(owner_id,state_data)
VALUES
('11111111-1111-4111-8111-111111111111',
 '{"library":[{"id":"A","priority":"high","unknownFuture":{"nested":[1,null,true]}}],"sessions":[],"xpLedger":{"events":[]},"futureRoot":"opaque"}'::jsonb),
('22222222-2222-4222-8222-222222222222',
 '{"__mediaflowCompressed":"gzip-base64","data":"SYNTHETIC_NOT_ACTUAL_GZIP"}'::jsonb);

-- Definer can read its own private data; clients cannot directly access either table.
DO $$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='m57_staging' AND c.relname='account_states'
           AND c.relrowsecurity) THEN
    RAISE EXCEPTION 'RLS not enabled';
  END IF;
  IF pg_catalog.has_table_privilege('authenticated',
     'm57_staging.account_states','UPDATE') THEN
    RAISE EXCEPTION 'Authenticated role can bypass RPC';
  END IF;
  IF pg_catalog.has_function_privilege('anon',
     'public.m57_stage_commit(uuid,bigint,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous role can execute staging commit';
  END IF;
  IF (SELECT prosecdef FROM pg_catalog.pg_proc
      WHERE oid='public.m57_stage_commit(uuid,bigint,text,jsonb)'::regprocedure) THEN
    RAISE EXCEPTION 'Exposed wrapper must not be definer';
  END IF;
  IF NOT (SELECT prosecdef FROM pg_catalog.pg_proc
      WHERE oid='m57_staging.commit_state(uuid,bigint,text,jsonb)'::regprocedure) THEN
    RAISE EXCEPTION 'Private core must hold controlled row privileges';
  END IF;
END $$;

SET ROLE authenticated;
SELECT pg_catalog.set_config('request.jwt.claim.sub',
  '11111111-1111-4111-8111-111111111111',false);
DO $$
DECLARE
  start_row record;
  after_row record;
  ack record;
  dup record;
  rejected record;
  next_doc jsonb;
BEGIN
  -- Guard owner: auth.uid resolves row without caller owner argument.
  SELECT * INTO start_row FROM public.m57_stage_read();
  IF start_row.revision<>1 OR start_row.state_digest IS NULL
       OR start_row.state_data->>'futureRoot'<>'opaque' THEN
    RAISE EXCEPTION 'M57 read missing owner-specific synthetic state';
  END IF;
  next_doc:=pg_catalog.jsonb_set(start_row.state_data,
     '{library,0,priority}','"low"'::jsonb);
  SELECT * INTO ack FROM public.m57_stage_commit(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
    start_row.revision,start_row.state_digest,next_doc);
  IF ack.status<>'applied' OR ack.revision<>2 THEN
    RAISE EXCEPTION 'M57 initial commit failed: %',ack.status;
  END IF;
  -- Lost ACK returns the SAME original revision and digest.
  SELECT * INTO dup FROM public.m57_stage_commit(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
    start_row.revision,start_row.state_digest,next_doc);
  IF dup.status<>'replayed' OR dup.revision<>ack.revision
       OR dup.state_digest<>ack.state_digest THEN
    RAISE EXCEPTION 'Lost ACK was not idempotent';
  END IF;
  -- Reused operation ID with changed payload cannot be applied.
  SELECT * INTO rejected FROM public.m57_stage_commit(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,
    start_row.revision,start_row.state_digest,start_row.state_data);
  IF rejected.status<>'operation_id_mismatch' THEN
    RAISE EXCEPTION 'Operation ID poisoning not denied';
  END IF;
  SELECT * INTO rejected FROM public.m57_stage_commit(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid,
    start_row.revision,start_row.state_digest,start_row.state_data);
  IF rejected.status<>'conflict' THEN
    RAISE EXCEPTION 'Stale wire was not rejected';
  END IF;
  SELECT * INTO after_row FROM public.m57_stage_read();
  IF after_row.state_data->'library'->0->'unknownFuture'
     IS DISTINCT FROM start_row.state_data->'library'->0->'unknownFuture' THEN
     RAISE EXCEPTION 'Unknown metadata lost';
  END IF;
END $$;
-- Above last private-table count should be executed only as superuser;
-- the actual direct SELECT from authenticated is intentionally prohibited.
RESET ROLE;

-- Inspect recorded state and receipts from the test administrator only.
DO $$
BEGIN
  IF (SELECT count(*) FROM m57_staging.operation_receipts)<>1 THEN
    RAISE EXCEPTION 'Only applied operations should store receipts';
  END IF;
END $$;

SET ROLE authenticated;
SELECT pg_catalog.set_config('request.jwt.claim.sub',
  '22222222-2222-4222-8222-222222222222',false);
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.m57_stage_read();
  IF r.revision<>1 OR r.state_data->>'data'<>'SYNTHETIC_NOT_ACTUAL_GZIP' THEN
    RAISE EXCEPTION 'Owner isolation / compressed envelope changed';
  END IF;
  BEGIN
    PERFORM * FROM m57_staging.account_states;
    RAISE EXCEPTION 'Direct read bypass unexpectedly permitted';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $$;
RESET ROLE;
-- Anonymous and missing-session access must fail even when the URL is known.
SET ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.m57_stage_read();
    RAISE EXCEPTION 'Anonymous read incorrectly accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

\echo M57_POSTGRES_STAGING_SQL_ASSERTIONS_PASSED
