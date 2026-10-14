# MediaFlowApp — Milestone 09: Cross-device synchronization safety

**Baseline:** Original AlexGodly/MediaFlow website v410.  
**Target:** AlexGodly/MediaFlowApp (native Flutter).  
**Status:** Read-only sync diagnostics and an in-memory atomic transaction simulator. **Production cloud writes DISABLED.**

## 1. Website write protocol verified from source

The original source in src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js shows:

- v115FetchCloudState reads an authenticated user's single row in mediaflow_states with state_data and updated_at.
- v115SafeBootstrap blocks writes during an uncertain startup, including failed cloud reads, unexpectedly missing or empty cloud data, and local recovery caches newer than the cloud. Suspicious cases require explicit user recovery.
- rawSet serializes the WHOLE application state, optionally gzip-compresses the JSON into an envelope, saves an account-scoped local recovery cache, and writes using a user-scoped UPSERT keyed by user_id.
- The existing UPSERT sends client-generated updated_at and DOES NOT supply an expected-version compare-and-swap predicate.
- saveState serializes writes in one browser tab with saveQueue. That is NOT a cross-device lock.
- mergeStates merges Library entries, sessions, history and XP ledgers, plus settings and other data.

The later source in src/js/services/cloud-sync/058-v155-complete-cloud-state-full-sync-now.js adds guarded Sync Now merging and post-write readback verification. Those safeguards reduce risk but still do not make separate devices' uploads atomic. Collections have additional merge/tombstone logic in src/js/components/208-v274-collections-library-rating-order-layout.js. Logging has multi-field side effects in src/js/features/logging/008-session-flow.js.

## 2. Production metadata inspected (read-only)

Project mediaflowcloud (reference wgeijxfdpgehesxialxm):

- The public.mediaflow_states columns are user_id UUID, state_data JSONB, and updated_at TIMESTAMPTZ. They are all NOT NULL.
- Existing SELECT, INSERT, UPDATE, DELETE row-level policies for authenticated users enforce ownership via auth.uid() = user_id.
- No non-internal row triggers exist on this table.
- The original website explicitly sets updated_at. Therefore matching only the timestamp is insufficient; a transaction must match the original full JSONB as well as the timestamp.

The audit queried only metadata, not user records. No live database changes occurred.

## 3. Implemented in MediaFlowApp

- native_snapshot_codec.dart: copy-on-write compressed or uncompressed JSONB round trips. Retains unknown top-level fields, nested metadata, and unknown gzip-envelope keys.
- native_cas_protocol.dart: explicit compile-time write capability gates (all false), immutable-by-copy original cloud row, prepared expected/proposed payloads, strict owner and original-revision checks, complete baseline verification, and pure SQL-predicate simulation.
- Native status changes are blocked by transaction preflight because changing completed/dropped/etc. in v410 may affect History, completion timelines and XP.
- Same-timestamp but different-payload conflicts are rejected.
- The Settings screen now shows authenticated read-only cloud diagnostics and announces that native writing and offline queueing are disabled.
- Tests cover concurrent clients, foreign owner, damaged data, stale revisions, unchanged future v410 fields, no-ops, status restrictions and Personal Order preservation.

## 4. Non-deployed server proposal

Review docs/proposals/REVIEW_ONLY_native_cas_v1.sql for the exact draft (NOT a migration and NOT deployed).

It uses SECURITY INVOKER so authenticated RLS continues to apply. It gets the acting owner from auth.uid(), never a caller-controlled user ID. A PostgreSQL UPDATE atomically compares both original state_data JSONB and original updated_at under the row lock before replacing the state. If the row changed, the draft reports a conflict rather than silently overwriting it.

This alone is NOT sufficient while the original website can still bypass this function with direct UPSERT. Revoking those direct grants before migrating the website would break existing users. The server also cannot validate opaque gzip contents in the current draft.

## 5. Blockers before native writes

1. Original website must participate in the same enforced concurrency protocol, without breaking its behavior. The user explicitly prohibited touching that repository in this workflow, so this gate remains closed.
2. A trusted server revision, operation idempotency ledger, error-after-commit reconciliation and crash-safe offline queue are required. Do not blindly retry a timeout.
3. Snapshot completeness, gzip encoding, Library/History/XP invariants, Collections deletion tombstones, and every affected Settings field require staging integration tests.
4. Authenticated owner, different owner, anonymous, simultaneous devices, rollback and 100k+ title performance need real database/device testing.
5. Release/write switches must stay off until verified.

## 6. Testing status and limitations

Dart unit tests verify **local simulations**, not production SQL. The draft has not been executed in production or staging. Flutter analyzer/tests run in GitHub Actions; Android/Windows builds run in a separate workflow. There are no signed public native releases.

No edits to the original MediaFlow repository, no Supabase migrations, no user data copy and no database writes.
