# MediaFlowApp — Milestone 56: All-Writer Sync Inventory & Staging Preparation

**Status:** Source audit and synthetic staging rehearsal implemented; **not a complete writer discovery, not a provisioned database, and not a production migration**.  
**Audited baseline:** original `AlexGodly/MediaFlow` website **tag `410`**, read-only, plus native `AlexGodly/MediaFlowApp`.  
**Scope of repository changes:** MediaFlowApp only. Production personal website, MediaFlow Plus, Supabase data, RLS, Edge Functions and secrets were not touched. No Supabase credentials or production API calls are necessary.

## Deliverables

1. [Machine-readable writer map](parity/m56_writer_inventory.json): **18** traceable writer-related surfaces (website and native), including **one known direct cloud UPSERT**, its primary callers, domain mutation triggers, exports/backups and native read-only/draft paths. Every website source has a tag-410 Git blob SHA; **8 unverified discovery items** are explicitly listed. The map is deliberately `exhaustive: false`.
2. [Isolated shadow rehearsal](../tool/parity/m56_staging_rehearsal.mjs): **12 deterministic safety cases** run against the existing synthetic v410 sample `test/fixtures/m28_v410_lossless_sample.json` using an in-memory fake transaction model. It does **not** execute SQL, connect to a database, establish RLS, or guarantee durability.
3. [Staging preflight checklist](parity/m56_writer_inventory.json): **8 blocked prerequisites**, all unknown until a separate staging database has actually been provisioned and tested.
4. Native **read-only Settings panel**: source-linked write surfaces, blocked staging checks, and remaining writer discovery tasks. No setup credentials, cloud saving, migration or production activation UI.
5. Dart unit/widget tests on 320px dark, 390px light and 400px AMOLED Settings, plus inventory and staging denial assertions.
6. Fail-closed Node CI guard cross-correlating writer map, M26 pinned website source manifest, Dart projection, test coverage, original capability gates, and no-write policy.

## Fundamental finding: the v410 website bypasses native-only CAS

Pinned v410 `src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js`, **blob `3a79b1073266093b6da026409ede9632c5350bef`**, lines 245–277:

- `rawSet()` serializes and compresses the entire account state and directly executes `supabase.from('mediaflow_states').upsert(...,{onConflict:'user_id'})`.
- The website performs timeout retries, but it does **not** compare a server-assigned revision atomically. The `updated_at` value is client-provided and is **not** a safe revision token.
- Lines 353–367: `saveState()` uses per-tab `saveQueue`; serialization inside one tab cannot protect against another browser/device.
- `v155SyncNow()` in `src/js/services/cloud-sync/058-v155-complete-cloud-state-full-sync-now.js` lines 307–390 builds a snapshot, merges local and cloud, then calls `rawSet`; remote data can change after its initial read.
- `v148` complete-backup restore in `src/js/features/backup/053-v148-complete-data-backup-audit-full-restore.js` lines 286–319 applies an imported snapshot and persists with `saveState` / `saveQueue`. It must be included in any future migration.
- `App.submitLog()` in `src/js/features/logging/008-session-flow.js` makes Library, History and Task changes; `src/js/components/221-v287-personal-order-collection-queues.js` also stages/rolls back Collection traversal. A future server must preserve every related root atomically and prevent repeated XP/History on retry.
- `v155SchedulePortableCloudSave()`, `persistSettings()` wrappers and the v148/v152/v200 backup builders add further state surfaces and are not independent safe transaction boundaries.

These are **observed source-level anchors**, not proof that every currently deployed user page, beta build, dynamically installed wrapper, service worker or compiled bundle has been exhaustively inspected. The original manifest records 144 base modules and 157 runtime override modules; the complete assembled write call graph remains a separate unresolved task.

## Classified source map

| Reference | Entry point | Kind | File | Risk |
| --- | --- | --- | --- | --- |
| `web-cloud-rawset` | `rawSet()` | `direct_cloud_writer` | `src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js` | critical |
| `web-autosave` | `saveState() -> saveQueue -> rawSet()` | `cloud_write_caller` | `src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js` | critical |
| `web-sync-now` | `v155SyncNow() -> mergeStates() -> rawSet()` | `direct_cloud_write_caller` | `src/js/services/cloud-sync/058-v155-complete-cloud-state-full-sync-now.js` | critical |
| `web-recovery-restore` | `MediaFlowRecovery.restore() / saveState()` | `cloud_write_caller` | `src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js` | critical |
| `web-logging-submit` | `App.submitLog() -> persistLibrary()/persistSessions()/persistTask()` | `state_mutator_to_autosave` | `src/js/features/logging/008-session-flow.js` | critical |
| `web-collection-traversal` | `v287StageTraversal()/v287RollbackTraversal()/App.submitLog wrapper` | `state_mutator_to_autosave` | `src/js/components/221-v287-personal-order-collection-queues.js` | critical |
| `web-order-clear-restore` | `v287 clear/restore Order actions -> saveState()` | `state_mutator_to_autosave` | `src/js/components/221-v287-personal-order-collection-queues.js` | high |
| `web-full-backup-restore` | `restore validated backup -> v46ApplyState() -> saveState()` | `cloud_write_caller` | `src/js/features/backup/053-v148-complete-data-backup-audit-full-restore.js` | critical |
| `web-backup-export` | `v148BuildFullBackup() / App.exportJSON()` | `local_file_export` | `src/js/features/backup/053-v148-complete-data-backup-audit-full-restore.js` | high |
| `web-automatic-backup` | `backupSnapshot() -> v148BuildFullBackup()` | `local_file_export` | `src/js/features/backup/056-v152-automatic-backup-full-backup.js` | high |
| `web-settings-wrappers` | `persistSettings() wrapper` | `state_mutator_to_autosave` | `src/js/services/cloud-sync/115-persistence-merge-sync-now-full-backup.js` | high |
| `web-rating-queue-portable` | `v155SchedulePortableCloudSave() / snapshot wrapper` | `state_mutator_to_autosave` | `src/js/services/cloud-sync/058-v155-complete-cloud-state-full-sync-now.js` | high |
| `web-library-import` | `v169 import apply/rollback` | `state_mutator_to_autosave` | `src/js/features/import-export/071-v169-advanced-import-export-media-services.js` | high |
| `web-legacy-backup-overrides` | `v200 persistSettings()/snapshot()/backup builder` | `runtime_override_to_review` | `src/js/services/cloud-sync/140-persistence-cloud-full-backup.js` | high |
| `native-owner-read` | `_readCloud() / _readFreshForPriorityReview()` | `cloud_read_only` | `lib/data/mediaflow_library_repository.dart` | critical |
| `native-local-drafts` | `encrypted offline pending review drafts` | `device_local_only` | `lib/services/native_m33_draft_store.dart` | high |
| `native-proposed-cas` | `NativeM30SimulatedSharedServer` | `test_only_simulation` | `lib/services/native_m30_shared_sync.dart` | critical |
| `native-locked-cloud-writes` | `NativeCloudCapabilities flags` | `production_capability_gate` | `lib/services/native_cas_protocol.dart` | critical |

Kind totals: `direct_cloud_writer`: 1; `cloud_write_caller`: 3; `direct_cloud_write_caller`: 1; `state_mutator_to_autosave`: 6; `local_file_export`: 2; `runtime_override_to_review`: 1; `cloud_read_only`: 1; `device_local_only`: 1; `test_only_simulation`: 1; `production_capability_gate`: 1. A `local_file_export` is not a cloud writer; a `state_mutator_to_autosave` is not a direct database operation. The source map deliberately distinguishes both.

## Deterministic rehearsal coverage

| Scenario | Expected safe result |
| --- | --- |
| `lost-update-web-native` | reject stale base revision even if web and Android write different subtrees |
| `same-time-changed-wire` | reject stale payload when updated_at collides |
| `retry-lost-ack` | return identical receipt once; never duplicate History/XP |
| `operation-id-reuse` | reject same id with changed intent |
| `foreign-owner` | require auth.uid owner regardless of payload owner id |
| `old-web-direct-upsert` | deny legacy direct table write after coordinated cutover |
| `missing-cloud-row` | refuse silent empty-account overwrite or default seed |
| `invalid-compressed-wire` | reject malformed gzip/JSON and retain previous data |
| `backup-restore-race` | reject stale full restore; keep previous encrypted backup and receipt |
| `offline-reconnect` | quarantine replay behind owner and server revision checks |
| `atomic-logging-side-effects` | all or none of Library, History, XP, task, order traversal |
| `cross-account-device-switch` | old draft cannot attach to signed-in different account |

The Node rehearsal rejects stale revision/full-wire digest (even with the same displayed timestamp), wrong owner, reused operation ID with different intent, missing row, invalid backup, legacy direct UPSERT, and interrupted transaction. It checks duplicate-response receipts, preservation of unknown v410 fields, and one in-memory all-roots unit-of-work. **A fake test receipt does not demonstrate a durable PostgreSQL receipt or RLS enforcement.** There are no live accounts in the tests.

## Staging preflight — intentionally blocked

| Gate | State | Why |
| --- | --- | --- |
| `isolated-env` | Blocked | No isolated Supabase staging project provisioned; no live migration attempted |
| `writer-exhaustive` | Blocked | Dynamic v410 bundled override/write-path discovery remains open |
| `schema-rls` | Blocked | No live production/staging schema or RLS audit performed |
| `backup-restore` | Blocked | No real owner-scoped, restorable staging backup tested |
| `durable-transactions` | Blocked | Only in-memory model tests exist; no PostgreSQL version/receipt transaction deployed |
| `all-client-compat` | Blocked | Original website still uses unconditional state_data UPSERT |
| `rollback-drill` | Blocked | No database recovery drill or restore receipts captured |
| `cross-device-qa` | Blocked | No real-device/account integration tests against staging |

### Isolated staging setup guide (for a separately approved follow-on)

1. Obtain **explicit approval** for a separate, nonproduction Supabase project and credentials, with no automatic linking to the personal `mediaflowcloud` production project; do not reuse production API URLs/service-role keys.
2. Generate artificial owners and synthetic state only. If a future integration test requires real user exports, obtain fresh consent, minimize/secure data, and keep them out of git and CI artifacts.
3. Pin the website compiled version, source manifest and all `snapshot`/`mergeStates`/`rawSet`/`saveState` wrappers before constructing a complete direct/indirect writer graph; audit Auth, backup/restore, Storage and background writers too.
4. Create reviewed **staging-only** revisioned schema with independently incremented server revision; enforce `auth.uid()` ownership and deny direct client `INSERT`/`UPDATE`/`UPSERT` bypasses after cutover. No write protocol shall rely solely on `updated_at`.
5. Use one PostgreSQL transaction for revision/full-wire check, complete state mutation and durable idempotency receipt. Verify retry after crash/restart, wrong-owner isolation, preserved compressed/unknown state, large libraries, multi-category log side effects, and restore rollback.
6. Run at least two website clients and Android/Windows/iOS staging clients against **synthetic accounts** including old website stale-write rejection; prove no lost edits, duplicated awards, or incomplete task/Collection traversal.
7. Capture signed evidence for each required staging check, a verified independent backup/restore drill, explicit migration rollback, and authorization for the website/server cutover. Never use production accounts as test fixtures.
8. **Only after** this can Milestones 57–59 consider an approved rollout. Native cloud writing remains disabled until all-client compatibility is independently established.

**Next:** M57 — implement the staged owner-scoped revision/idempotency server transaction and its real-database integration tests **in an isolated environment**, without touching production without specific approval.

**M56 closing decision: PREPARATION COMPLETE; STAGING NOT PROVISIONED; PRODUCTION CUTOVER BLOCKED.**
