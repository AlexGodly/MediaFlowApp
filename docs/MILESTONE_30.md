# MediaFlowApp — Milestone 30: Shared Synchronization Architecture

**Date:** 2026-10-14  
**Status:** Implemented as in-memory reviewed protocol **and migration plan only**. No server deployment, SQL execution, feature enablement or user-data changes.

## Why a native-only CAS cannot protect account data

The **original website source** `src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js` still contains:
`supabase.from('mediaflow_states').upsert({user_id:AUTH_USER.id,state_data:payload,updated_at:new Date().toISOString()},{onConflict:'user_id'})`.

A native client that uses a protected RPC can still have its changes overwritten by that unguarded website writer. This is a **cross-writer** migration, not a Flutter flag switch. The original website and Supabase project were **inspected read-only** and not modified.

## Delivered

- `lib/services/native_m30_shared_sync.dart` implements a **pure, no-I/O simulation** of one shared, owner-authenticated write endpoint used identically by fictional web/Android/Windows/iOS clients.
- Independent monotonically increasing **server-assigned integer revision** paired with SHA-256 of canonical complete wire state. A client-supplied `updated_at` is preserved for compatibility but is **never** the authoritative revision.
- Per-owner operation IDs with a canonical immutable intent fingerprint; repeat after lost acknowledgement returns the **same original revision/digest receipt** without reapplying. Same operation ID and different request is rejected.
- Single synchronous simulated server transaction: authentication, idempotency, exact base revision + wire digest, existing v410 title lookup, strictly local lossless scalar change, revision advance, receipt creation. Real backend must do all these **atomically in PostgreSQL**, not as separate client calls.
- The sole recognized local mutation is **priority adjustment**, which uses the source-backed full-state clone. Status, logging, XP, Collections and all complex multi-root side effects are **not supported or authorized**.
- Simulated legacy unconditional UPSERTs are refused. Synthetic rollout gate refuses writes unless all prerequisites are marked complete **inside a test-only object**.
- Regression scenarios: two-way website/native races, same-timestamp payload changes, lost acknowledgements, replays and poisoned reused IDs, foreign-user isolation, duplicate/missing Library records, gzip envelope preservation and unknown nested fields, default-deny rollout gate, and 1,000 alternating successful synthetic writes.

## Proposed coordinated rollout (REQUIRES SEPARATE EXPLICIT APPROVAL)

1. **Inventory and back up:** Audit production `mediaflow_states` schema, `updated_at` behavior, RLS and all web/background write paths, imports, restore and recovery. Take **verified, restorable** encrypted data backups and confirm owner isolation in staging.
2. **Stage contract & database:** Introduce server-generated per-account revision (or equivalent atomic version token), auth.uid()-derived ownership, and **durable** owner-scoped idempotency receipts in a staging database. Database transaction must atomically check owner, expected version/full wire, apply complete state, advance revision, and store acknowledgement. Log and reject mismatched operation payload reuse.
3. **Protect every write path:** Migrate existing website state writes and all backup/restore/recovery flows to the shared endpoint **before** enabling native writes. Deny all legacy direct client UPDATE/INSERT/UPSERT (privileges/RLS or server-enforced equivalent) so there is no bypass. A web client stuck on the old version **must not be allowed to write**; warn and require refresh, never silently accept unsafe writes.
4. **Dual-read / no-loss validation:** During an approved migration only, allow read-only verification against legacy snapshots. Backfill server revisions without rewriting the JSON payload or its gzip metadata. Preserve unknown roots, nested settings, History, XP/levels/streaks, Collections, Personal Order, import metadata and event IDs. Reject malformed/partial account rows rather than replacing them with blank data.
5. **Cross-client staging matrix:** Race Windows/Android/iOS and old/new web client revisions; simulate simultaneous full-state updates, completion + XP + History mutations, automatic backups, lost responses, replay, account switches, offline/reconnect, partial failures and crash recovery. Assert receipts are durable across a real PostgreSQL restart and stale writes never overwrite newer records.
6. **Phased controlled cutover:** Roll out a compatible **website** first behind a reversible feature gate, while production native writing remains OFF. Enforce server-side revision access and deny old-client direct writes at the agreed cutover. Only after all clients, auth/RLS, restore paths and recovery procedures are independently validated should separately approved native write enablement be considered.
7. **Rollback / incident response:** Halt all writes or revert clients to **read-only** on failure; do not restore unconditional UPSERT privileges. Preserve original cloud rows and operation receipts for reconciliation. Use verified snapshot backups to restore affected accounts only with reviewed, owner-scoped operations and an audit trail. Never automatically replay quarantined offline edits.

**Do not run any migration or alter website/Supabase without explicit approval.** The older `docs/proposals/REVIEW_ONLY_native_cas_v1.sql` is incomplete and does not provide shared writer safety.

## Scope limits

- This tests the **architectural safety contract**, not actual durable database transactions, production Row Level Security or a working Supabase RPC.
- v410 complete transactional business side effects and all 307 functional surfaces remain unverified. A real web runtime still uses unconditional UPSERT until explicitly migrated.
- Device-local encrypted offline snapshots are lossy, read-only and **never** promoted to upload sources; pending draft reviews remain inert and require fresh cloud revalidation.
- No backend migrations, RLS policies, webhook/Edge Functions, SQL commands, cloud write calls, repository changes outside MediaFlowApp, or private-account data exports occurred.
- `NativeM30Protocol.deployed`, `NativeCloudCapabilities.cloudWritesEnabled`, `hasServerSideCas` and `offlineWriteQueueEnabled` remain false.

## Next: Milestone 31

Expand the approved offline-first **read-only** architecture and safe draft review/recovery semantics. Real offline **editing/replay** stays blocked until the shared server protocol is migrated and verified across all website/native writers.
