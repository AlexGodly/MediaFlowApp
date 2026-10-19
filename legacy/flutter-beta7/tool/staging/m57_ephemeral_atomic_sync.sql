-- M57 STAGING-ONLY REFERENCE. DO NOT APPLY TO mediaflowcloud/production.
-- Execute only inside an isolated ephemeral PostgreSQL database (CI) or
-- explicitly approved, separate Supabase staging project with synthetic owners.
-- NOT a migration of public.mediaflow_states. Does not authorize native writes.
-- PostgreSQL >=15. Requires Supabase auth.uid() (CI provides a local mock).
-- Exposed schema public functions are SECURITY INVOKER only. The private
-- SECURITY DEFINER core has an empty search_path and explicit owner check.
CREATE SCHEMA IF NOT EXISTS m57_staging;
REVOKE ALL ON SCHEMA m57_staging FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS m57_staging.account_states (
  owner_id uuid PRIMARY KEY,
  revision bigint NOT NULL DEFAULT 1 CHECK (revision > 0),
  state_data jsonb NOT NULL
    CHECK (pg_catalog.jsonb_typeof(state_data) IN ('object','string')),
  state_digest text NOT NULL
    CHECK (state_digest ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp()
);
-- The jsonb::text cast is STABLE, so PostgreSQL rejects it in a
-- GENERATED ALWAYS expression. Use a private BEFORE trigger instead.
CREATE OR REPLACE FUNCTION m57_staging.set_state_digest()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path = ''
AS $m57$
BEGIN
  NEW.state_digest := pg_catalog.encode(pg_catalog.sha256(
    pg_catalog.convert_to(NEW.state_data::text,'UTF8')),'hex');
  RETURN NEW;
END;
$m57$;
CREATE TRIGGER m57_digest_before_state_write
BEFORE INSERT OR UPDATE OF state_data ON m57_staging.account_states
FOR EACH ROW EXECUTE FUNCTION m57_staging.set_state_digest();
REVOKE ALL ON FUNCTION m57_staging.set_state_digest()
  FROM PUBLIC,anon,authenticated;

CREATE TABLE IF NOT EXISTS m57_staging.operation_receipts (
  owner_id uuid NOT NULL REFERENCES m57_staging.account_states(owner_id),
  operation_id uuid NOT NULL,
  fingerprint text NOT NULL CHECK (length(fingerprint)=64),
  committed_revision bigint NOT NULL,
  committed_digest text NOT NULL,
  committed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  PRIMARY KEY(owner_id,operation_id)
);
ALTER TABLE m57_staging.account_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE m57_staging.operation_receipts ENABLE ROW LEVEL SECURITY;
-- No direct SELECT/INSERT/UPDATE/DELETE grants or RLS policies for clients.
REVOKE ALL ON ALL TABLES IN SCHEMA m57_staging FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION m57_staging.read_state()
RETURNS TABLE(revision bigint, state_data jsonb, state_digest text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = ''
AS $m57$
DECLARE v_owner uuid;
BEGIN
  v_owner := auth.uid();
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;
  RETURN QUERY
    SELECT s.revision,s.state_data,s.state_digest
    FROM m57_staging.account_states AS s WHERE s.owner_id=v_owner;
END;
$m57$;

CREATE OR REPLACE FUNCTION m57_staging.commit_state(
  p_operation_id uuid,
  p_expected_revision bigint,
  p_expected_digest text,
  p_next_state jsonb
)
RETURNS TABLE(status text, revision bigint, state_digest text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $m57$
DECLARE
  v_owner uuid;
  v_revision bigint;
  v_digest text;
  v_previous m57_staging.operation_receipts%ROWTYPE;
  v_fingerprint text;
  v_new_digest text;
BEGIN
  v_owner := auth.uid();
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;
  IF p_operation_id IS NULL
      OR p_expected_revision IS NULL OR p_expected_revision < 1
      OR p_expected_digest IS NULL
      OR p_expected_digest !~ '^[0-9a-f]{64}$'
      OR p_next_state IS NULL
      OR pg_catalog.jsonb_typeof(p_next_state) NOT IN ('object','string')
      OR pg_catalog.octet_length(p_next_state::text)>134217728 THEN
    RAISE EXCEPTION 'Invalid versioned state request' USING ERRCODE = '22023';
  END IF;

  -- Fingerprint all authoritative operation inputs, not a client-supplied hash.
  v_fingerprint := pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(
    pg_catalog.jsonb_build_array(
      p_expected_revision,p_expected_digest,p_next_state)::text,
    'UTF8')), 'hex');
  -- A row lock makes the read/compare/receipt/write atomic across sessions.
  SELECT a.revision,a.state_digest INTO v_revision,v_digest
    FROM m57_staging.account_states a
    WHERE a.owner_id=v_owner FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'missing_account'::text,NULL::bigint,NULL::text;
    RETURN;
  END IF;

  SELECT * INTO v_previous FROM m57_staging.operation_receipts r
    WHERE r.owner_id=v_owner AND r.operation_id=p_operation_id;
  IF FOUND THEN
    IF v_previous.fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'operation_id_mismatch'::text,
        v_revision,v_digest;
    ELSE
      RETURN QUERY SELECT 'replayed'::text,
        v_previous.committed_revision,v_previous.committed_digest;
    END IF;
    RETURN;
  END IF;
  IF v_revision <> p_expected_revision OR v_digest <> p_expected_digest THEN
    RETURN QUERY SELECT 'conflict'::text,v_revision,v_digest;
    RETURN;
  END IF;

  UPDATE m57_staging.account_states a
    SET state_data=p_next_state, revision=a.revision+1,
        updated_at=pg_catalog.clock_timestamp()
    WHERE a.owner_id=v_owner
    RETURNING a.revision,a.state_digest
    INTO v_revision,v_new_digest;

  INSERT INTO m57_staging.operation_receipts(
    owner_id,operation_id,fingerprint,committed_revision,committed_digest
  ) VALUES (v_owner,p_operation_id,v_fingerprint,v_revision,v_new_digest);
  RETURN QUERY SELECT 'applied'::text,v_revision,v_new_digest;
END;
$m57$;

REVOKE ALL ON FUNCTION m57_staging.read_state()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION m57_staging.commit_state(uuid,bigint,text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA m57_staging TO authenticated;
GRANT EXECUTE ON FUNCTION m57_staging.read_state() TO authenticated;
GRANT EXECUTE ON FUNCTION m57_staging.commit_state(uuid,bigint,text,jsonb)
  TO authenticated;

-- Client-facing SECURITY INVOKER bridge; exposed-schema function does not
-- possess ownership bypass on its own. Never expose private schema in PostgREST.
CREATE OR REPLACE FUNCTION public.m57_stage_read()
RETURNS TABLE(revision bigint,state_data jsonb,state_digest text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $m57$
  SELECT * FROM m57_staging.read_state();
$m57$;
CREATE OR REPLACE FUNCTION public.m57_stage_commit(
  p_operation_id uuid,p_expected_revision bigint,
  p_expected_digest text,p_next_state jsonb
)
RETURNS TABLE(status text,revision bigint,state_digest text)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $m57$
  SELECT * FROM m57_staging.commit_state(
    p_operation_id,p_expected_revision,p_expected_digest,p_next_state);
$m57$;
REVOKE ALL ON FUNCTION public.m57_stage_read() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.m57_stage_commit(uuid,bigint,text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.m57_stage_read() TO authenticated;
GRANT EXECUTE ON FUNCTION public.m57_stage_commit(uuid,bigint,text,jsonb)
  TO authenticated;

-- No triggers or code against public.mediaflow_states.
-- DO NOT DEPLOY: staging authorizer and exhaustive web migration are pending.
