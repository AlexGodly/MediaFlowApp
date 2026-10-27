# MediaFlowApp — Milestone 33: Offline Editing & Synchronization (Foundations)

**Roadmap requirement:** Milestone 33 is *Offline Editing & Synchronization* — encrypted pending operations, local editing, retry queues, reconnection synchronization, and app-restart recovery.

**Status: PARTIAL, safely blocked from real synchronization.** The user-approved original website and production Supabase have not been migrated to a shared database-enforced write protocol. Previous milestones 31/32 delivered read-only recovery and encrypted review, **not** the roadmap's full Safe Cloud Persistence and Native Cloud Editing acceptance criteria. Therefore automatic upload/retry or claiming real offline sync would risk lost account data.

## Implemented in the real Flutter application

- **Device-local priority-only offline drafts.** While displaying a successfully authenticated cloud or verified encrypted device snapshot, users can create priority-only RAM title sketches and explicitly choose Settings → **Offline priority drafts → Keep offline drafts**. The existing safe Library edit sketch UI is reused. No History, XP, progress, status, logging or season side effects are staged.
- **Dedicated encrypted pending-intent storage** `NativeM33DraftStore`: per-owner OS-protected AES-256-GCM key namespace separate from M18/M19; random nonce, authenticated envelope and ciphertext; write serialization, unfinished-write cleanup, protected previous-generation recovery, owner-verified format and bounded operation count / size. Raw title IDs/priorities are only inside ciphertext.
- **No false authority for an offline cache.** An offline/recovered/in-memory display creates a draft with **no** cloud write revision. Only an original online authenticated full-state read supplies an optional exact updated_at + SHA-256 full-wire digest. Neither one is sufficient to authorize real writes.
- **Explicit app-restart recovery.** The Settings panel loads the account's encrypted saved draft queue on start. The RAM workspace may be gone after restart, but the device-only queue survives while its OS key remains available. It is removed on sign-out along with device keys and other offline state.
- **Manual reconnection review.** Settings → **Review against cloud** performs a fresh, authenticated owner-scoped `SELECT state_data,updated_at` and compares the saved original/desired priorities to unique title IDs, with optional anchored full-state digest/timestamp checks. Missing/duplicated titles, different priorities, unrelated full-account changes, disconnected cloud or owner changes are surfaced as blocked conditions. Matching target priority does **not** prove the draft was saved by this device.
- **No automatic replay or overwrite.** Existing saved queue cannot be replaced without explicit deletion. Queues contain only operation IDs, priority intent, provenance metadata, and optional cloud digest (not whole v410 state). All reports expose `mayUpload == false` and no cloud write actions exist.
- **Validation:** synthetic encrypted restart, key-loss, ciphertext tamper, two generations, signout/save racing, cross-account isolation and manual conflict/unknown-field scenarios; Flutter/Dart analyzer, test suite, source-safety CI, native Android/Windows development builds.

## To complete this milestone (not done)

1. Implement a **shared server-side, transactionally versioned write protocol** across the personal MediaFlow website and Flutter native clients, with strict owner RLS, durable idempotency receipts, backfill/rollback and denial of old unconditional website UPSERT. Requires separate, explicitly reviewed staging and deployment approval.
2. Complete website-equivalent native edit/logging/XP/History/status side effects before adding them to offline operations. Verify full state and unknown field preservation.
3. Add a real bounded, idempotent retry worker with network-change detection, per-device retry/backoff and restart recovery, but **only after** (1) and (2) are proven in staging. No automatic rebase, no last-writer-wins.
4. Run two+device staging and production cutover acceptance, including offline → reconnect, server crash between update and ACK, duplicate operations, account switches, invalid snapshots, key loss and out-of-order responses.

**Do not misinterpret draft encryption or a successful manual compare as production synchronization.** Original website, MediaFlow Plus and production Supabase remain untouched. NativeCloudCapabilities.cloudWritesEnabled, hasServerSideCas and offlineWriteQueueEnabled remain false.

## Next

Finish blocked **Milestone 31/32 production synchronization prerequisites** with an explicitly approved coordinated migration, then finish Milestone 33's real replay path and Milestone 34 conflict resolution. Until then native drafts remain explicitly local-only.
