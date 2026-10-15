# MediaFlowApp — Milestone 57: Isolated Atomic Shared-State Transaction

**Status:** Source and CI integration implemented; **NOT DEPLOYED to any Supabase project**. Milestone 57 verifies a genuine ephemeral PostgreSQL transactional prototype and authorization checks, not production client synchronization.

## Scope and isolation

- Repository: `AlexGodly/MediaFlowApp` only.
- Baseline: original personal MediaFlow v410; original website still uses `mediaflow_states.upsert(..., {onConflict:'user_id'})` without a shared server revision.
- Production MediaFlow/MediaFlow Plus repositories, Supabase schemas/roles/RLS/data/functions/secrets, existing accounts, signed releases, and Flutter write gates **remain unchanged**.
- Integration runner: fresh PostgreSQL 17 **GitHub Actions service container**, synthetic owner UUIDs and in-memory/test-only JSON fixtures. Does not provision a Supabase staging project.
- Artifacts: [isolated SQL](../tool/staging/m57_ephemeral_atomic_sync.sql), [SQL integration tests](../test/staging/m57_pg_integration.sql), [real two-connection race test](../tool/staging/m57_pg_concurrency.mjs), [staging-only guard](../tool/staging/m57_sql_guard.mjs), [dedicated CI](../.github/workflows/m57-postgres-staging.yml).

## Implemented transactional contract

- **Private, isolated schema** `m57_staging`; no modifications to `public.mediaflow_states`.
- `account_states` holds owner UUID, server-assigned incrementing `bigint` revision, an opaque v410 `jsonb` state envelope (including unknown roots or compressed-string/envelope representations), and **generated SHA-256** wire digest.
- `operation_receipts` keeps durable-in-a-live-database owner+operation UUID, fingerprint of full request input, committed revision/digest. Records and state are inserted/updated within one PostgreSQL function transaction.
- `m57_staging.commit_state` is **SECURITY DEFINER**, resides in a private schema, sets empty `search_path`, uses schema-qualified objects and gets owner from **`auth.uid()`**, not a caller-supplied UUID. It takes row-level `FOR UPDATE` lock before comparing revisions/receipts.
- For an identical lost-ack retry, return `replayed` with the **original committed receipt**, even if a later operation has changed the current revision. Reused operation ID with different payload returns `operation_id_mismatch`; stale revision or full-wire digest returns `conflict`; absent owner row returns `missing_account`.
- `public.m57_stage_read` and `public.m57_stage_commit` are only **SECURITY INVOKER** wrappers; anonymous and PUBLIC EXECUTE revoked; explicit authenticated grants. No direct table grants to authenticated or anon; RLS enabled, no client table policies. Never expose `m57_staging` as a REST-exposed schema.
- **Caveat:** In the isolated CI environment, `auth.uid()` is a **mock that reads a synthetic session setting**, and the private function is owned by the ephemeral superuser. This verifies the SQL role model but is NOT proof of real Supabase JWT enforcement or production ownership security. Staging deployment requires authentic Supabase Auth, advisors, RLS/grant verification and independent review.
- The transaction atomically replaces the **entire opaque account state**, but it does **not** yet validate v410 business semantics (XP, Logging, Collections, task and backup mutation invariants). Its input is a proposed full state, not a safe native feature mutation; no native client should call it until later milestones and website migration are complete.

## Test matrix

| Area | How it is tested |
| --- | --- |
| Real PostgreSQL constraints | Ephemeral PG17 schema creation, generated digests, row lock and receipts |
| Auth/owner | Two artificial owner UUIDs, `auth.uid()` mock, no owner parameter |
| Table bypass | Authenticated/anon have no direct table modification privileges |
| Function exposure | Private definer, public invoker and restricted grants |
| First atomic commit | One revision increment and updated server digest |
| Lost acknowledgement | Identical operation receives original revision/digest |
| Poisoned operation ID | Same ID with changed payload cannot commit |
| Stale write | Revision/digest mismatch rejected |
| Unknown fields | Unrecognized nested v410 metadata retained |
| Compressed envelope | Separate synthetic gzip-like envelope isolated by owner |
| Two simultaneous connections | Same baseline races; exactly one applied, one conflict |
| Other owner isolation | Owner B's state/revision unchanged during owner A race |
| Staging-only safety | Node guard forbids modifying production mediaflow_states, production URLs, secrets, or native write-gate flip |

The SQL fixture includes no personal Library data; it intentionally uses fabricated records. **Run metadata and validation jobs are not signed releases.**

## Still blocked before approved Supabase staging

1. A separate, explicitly designated **nonproduction Supabase project** needs to be provisioned. None has been created or modified by this milestone.
2. Audit current Supabase Auth `auth.uid()` behavior, owner RLS, function ownership/security-definer bypass, exposed schema configuration, and security advisor output in that staging project.
3. Independently ensure `public.m57_stage_*` functions are **not deployed** to the personal production project or a broadly accessible production PostgREST schema.
4. Validate compressed payload round trips on real v410 synthetic encodings, malformed payload rejection, receipt persistence after PostgreSQL restart and 100k-title performance/memory limits.
5. Audit all existing v410 website save, sync, recovery, backup and import paths. **The unguarded legacy website UPSERT remains**, and a staging-only RPC cannot prevent it from overwriting native edits if production were ever enabled.
6. Produce a coordinated website/server migration with a hard block on direct legacy writes; verify clean rollback, data restoration and cross-client compatibility before separately authorized production cutover.
7. Implement safe feature-level transactional semantics (History/XP/Respect/task/Collection and offline replay) rather than permitting arbitrary native full-state replacements.

**Release status: NOT DEPLOYED, NOT PRODUCTION SAFE.** `NativeCloudCapabilities.cloudWritesEnabled=false`, `hasServerSideCas=false`, `offlineWriteQueueEnabled=false`, `NativeM30Protocol.deployed=false` remain the authoritative native gates.

## Compatibility references

Supabase's current documentation recommends preferring SECURITY INVOKER; private SECURITY DEFINER functions must explicitly check ownership, use `SET search_path = ''`, be absent from exposed schemas, and revoke PUBLIC EXECUTE. In 2026 Data API table exposure also requires explicit grants; a grant without ownership checks is unsafe.

- https://supabase.com/docs/guides/database/functions
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/changelog?types=breaking-change

**Next:** Milestone 58 may design the website migration and prove old-client write denial in isolated staging. Do not modify production website/Supabase without separate approval.
