# MediaFlowApp — Milestone 19: Safe Cloud Synchronization Preflight

**Baseline:** native Milestone 18, original MediaFlow web v410.
**Status:** local safety protocol / simulation complete. Native production cloud writes, automatic replay and live offline editing remain DISABLED.
**Scope:** only AlexGodly/MediaFlowApp; original MediaFlow, MediaFlow Plus and production Supabase remain untouched.

## What was implemented

1. **Full-state conflict anchoring.** Pending review batches bind to an exact owner ID, cloud revision string and SHA-256 of the canonical complete original cloud state_data (including compression-envelope metadata). Comparing updated_at alone is insufficient; the website may reuse timestamps while data changes.
2. **Strict, inert review batches.** Batch IDs and operation IDs are unique, proposals must use the same owner and baseline revision, and local preflight must succeed before staging. Unknown operations and status/XP side-effect shortcuts remain blocked. No full original cloud state is persisted in the pending review file.
3. **Fresh-row revalidation.** A pending batch cannot be reviewed for simulation without a fresh, full authenticated cloud row. Missing row, wrong owner, changed timestamp, changed payload, unsupported operation or invalid batch yields an explicit blocked/quarantined result. No silent merge, rebase, last-writer-wins or offline snapshot promotion is performed.
4. **Encrypted device-only pending-review storage.** Versioned AES-256-GCM envelope, independently namespaced per-owner OS-protected key, explicit owner checks, size/operation limits, pending temporary file and previous-generation recovery. Clear/sign-out removes both local generations, uncommitted temp file and matching encryption key. These records are not an enabled production offline write queue. No automatic replay, background retries, or cloud transport exists.
5. **Simulated atomic server and idempotency.** A purely in-memory fake server verifies exact baseline before a synchronous test commit, rejects two concurrent clients attempting to overwrite each other, returns a stable receipt for an identical repeated batch, and rejects an operation ID reused for altered content. This is not the actual Supabase server protocol.
6. **Native Settings lab.** Interactive synthetic-data demonstration of a full-payload anchored review, a timestamp-collision conflict, and a simulated atomic save. It never displays or mutates real account records.
7. **Automated testing.** Concurrent edits, stale timestamps, same-timestamp content changes, foreign users, missing rows, unsupported operations, unknown-field preservation, encrypted pending state round-trip/recovery/tampering/key loss, serialized sign-out cleanup and a synthetic 100,000-title digest test.

## Required production protocol before enabling native writes

The existing original web v410 full-state UPSERT cannot be considered safe concurrently with a native compare-and-swap RPC. An RPC protecting only the native client would still lose data when an unchanged website client performs unconditional UPSERT.

Implementation must be coordinated across ALL cloud writers:

1. Adopt a database-enforced version/revision token for each owner-scoped state row, incremented atomically by the server. Never treat client-supplied updated_at as a unique monotonic version.
2. Require every cloud writer (web, Android, Windows, and any future clients) to use the same RLS-aware server-side atomic transaction with owner authentication and expected token/full-state comparison. The comparison and write must occur in one transaction, not client-side SELECT plus unconditional UPSERT.
3. Add a per-account idempotency operation record or equivalent transactional mechanism for save acknowledgement/lost-response retries. The exact same operation ID with a different payload must fail; completed identical operations must return the same receipt.
4. Preserve the complete v410 state and all side effects, including History/XP/level/streak, Collections, Personal Order, import/export metadata, newer/unknown fields, and compressed snapshot conventions.
5. Add an explicitly reviewed migration and backfill strategy, RLS audit, backup plan, staging tests and client rollout compatibility gate; deploy only after all writers can safely participate.
6. Stress-test two-device writes, offline edits and reconnect, repeated requests, changes made under identical timestamps, account switches, partial writes and rollback; do not auto-merge full-state conflicts without a tested semantic reconciliation mechanism.

The existing SQL proposal in docs/proposals/REVIEW_ONLY_native_cas_v1.sql remains review-only and must NOT be deployed as-is to solve cross-client safety. It is not evidence that production CAS is active.

## Explicit exclusions

No database migration, Edge Function deployment, SQL function execution, RLS change, API INSERT/UPDATE/UPSERT/DELETE call, real-account native editing, automatic offline retries, or background synchronization was introduced. The safe simulated status does not authorize uploads. NativeCloudCapabilities.cloudWritesEnabled, hasServerSideCas, and offlineWriteQueueEnabled all remain false.

## Verification

GitHub Actions Flutter analyze and unit/widget tests, with separate Android debug and Windows platform builds, are required for the final branch. Synthetic 100,000-title tests do not establish real-device frame times. Actual cloud conflict protection awaits coordinated web/server development.

## Next development milestone

Milestone 20 can add more native local draft UX and full v410 side-effect parity behind the existing write-disabled gate. Actual live editing should remain disabled until the coordinated production protocol above is deployed and independently verified, and the website has migrated away from unconditional full-state writes.
