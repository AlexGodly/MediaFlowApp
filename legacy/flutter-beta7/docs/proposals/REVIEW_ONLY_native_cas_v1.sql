-- ====================================================================
-- REVIEW-ONLY DRAFT. DO NOT EXECUTE ON MEDIAFLOW'S PRODUCTION SUPABASE.
-- This file is NOT a migration and has NEVER been applied to any project.
--
-- WHY NOT READY:
-- Original web v410 still calls mediaflow_states.upsert without any CAS
-- predicate. A legacy website writer can bypass this function and overwrite
-- the native client's successful transaction. Direct UPDATE/UPSERT privilege
-- must be migrated to a common version-aware protocol before activation.
--
-- Additional blockers: gzip payload semantics cannot be verified by this
-- function; no durable idempotency ledger; no integration concurrency tests.
-- ====================================================================

-- PROPOSED: scoped, single-row, atomic compare-and-swap for an existing row.
-- Never take a caller-supplied user_id; the owner comes from auth.uid().
-- Keep SECURITY INVOKER so the existing SELECT and UPDATE RLS policies apply.
CREATE OR REPLACE FUNCTION public.mediaflow_native_cas_v1(
  p_expected_updated_at timestamptz,
  p_expected_state_data jsonb,
  p_next_state_data jsonb
)
RETURNS TABLE (
  applied boolean,
  committed_at timestamptz
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_owner uuid;
  v_new_timestamp timestamptz;
BEGIN
  v_owner := (SELECT auth.uid());

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
  END IF;
  IF p_expected_updated_at IS NULL
     OR p_expected_state_data IS NULL
     OR p_next_state_data IS NULL
     OR pg_catalog.jsonb_typeof(p_expected_state_data) <> 'object'
     OR pg_catalog.jsonb_typeof(p_next_state_data) <> 'object' THEN
    RAISE EXCEPTION 'Missing or invalid snapshot'
      USING ERRCODE = '22023';
  END IF;

  -- Reject accidental compression-format changes. This cannot prove the
  -- *decoded* gzip payload is valid; that requires additional safeguards.
  IF (p_expected_state_data ->> '__mediaflowCompressed')
     IS DISTINCT FROM
     (p_next_state_data ->> '__mediaflowCompressed') THEN
    RAISE EXCEPTION 'Cloud payload encoding must not change'
      USING ERRCODE = '22023';
  END IF;

  -- PostgreSQL locks the target row during UPDATE and rechecks WHERE after
  -- concurrent row updates. The FULL original JSONB plus server timestamp
  -- are compared together; no non-atomic preflight SELECT is relied upon.
  UPDATE public.mediaflow_states AS state
     SET state_data = p_next_state_data,
         updated_at = pg_catalog.clock_timestamp()
   WHERE state.user_id = v_owner
     AND state.updated_at = p_expected_updated_at
     AND state.state_data = p_expected_state_data
  RETURNING state.updated_at INTO v_new_timestamp;

  RETURN QUERY SELECT v_new_timestamp IS NOT NULL, v_new_timestamp;
END;
$function$;

-- Narrow exposure; privileges DO NOT replace row ownership RLS.
REVOKE ALL ON FUNCTION public.mediaflow_native_cas_v1(
  timestamptz, jsonb, jsonb
) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mediaflow_native_cas_v1(
  timestamptz, jsonb, jsonb
) FROM anon;
GRANT EXECUTE ON FUNCTION public.mediaflow_native_cas_v1(
  timestamptz, jsonb, jsonb
) TO authenticated;

-- REVIEW-ONLY rollback, also NOT executed:
-- DROP FUNCTION IF EXISTS public.mediaflow_native_cas_v1(
--   timestamptz, jsonb, jsonb
-- );
