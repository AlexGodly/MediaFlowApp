# MediaFlowApp — Milestone 32: Native Draft Review & Conflict Recovery

**Date:** 2026-10-14  
**Status:** Live authenticated read-only review workflow implemented; production writes, automatic replay and cloud migrations remain OFF.  
**Repositories affected:** `AlexGodly/MediaFlowApp` only.

## Delivered

- **A user-triggered workflow in Settings:** Start with a Library title **priority-only** draft, open Settings → Priority review, explicitly stage an encrypted review, check it against a newly fetched cloud snapshot, or discard the saved review. This connects previously isolated RAM title drafts and the existing encrypted `NativePendingReviewStore` to the real signed-in account.
- **Source-bound cloud anchor:** When the Library is fetched online, attach the *original* owner ID, exact `updated_at` string and SHA-256 digest of the full, original wire `state_data` to that catalog. The anchor is not invented from the lossy offline projection. Only the accepted current authoritative catalog is eligible, and a new fresh owner-scoped Supabase **SELECT** must still match both revision **and complete payload digest** before a review can be staged.
- **Priority-only admission:** For every drafted title, require exactly one matching source title and one matching cloud record, untouched status/progress/rating, an actual change of priority, non-stale workspace, and no standard/itemized logging drafts. The website's status/progress/History/XP side effects are **not** implemented or uploaded.
- **Inert encrypted persistence:** Stage an `NativeReviewBatch` holding only owner, opaque revision, full-state fingerprint and typed bounded operations. Encrypt through existing device OS key vault, with authenticated AES-GCM envelope, prior-generation recovery and per-owner wiping. A saved review is **not** an offline synchronization queue, contains **no complete cloud snapshot**, and has no `Apply` or `Upload` action. A second stage cannot silently replace an existing pending batch.
- **On-demand conflict inspection:** An explicit user action obtains a **fresh** authenticated full cloud SELECT, then runs existing `NativeSyncReview.inspect`. Changed timestamp, changed content at same timestamp, deleted/missing row, other account, invalid proposal or unavailable network blocks the review. A conflict leaves the encrypted review intact for explicit inspection or discard; **never auto-merges/rebases/retries/uploads**.
- **Session and race safety:** The repository checks owner identity before and after awaited operations; signed-out workspaces and encrypted pending-review generations are wiped through existing sign-out logic. Concurrent commands reject one another. The UI clearly labels its preview-only status.
- **Tests and CI:** E2E synthetic staging/inspection, exact digest conflicts, unsupported side effects, offline failure, owner switch, concurrent actions, prior pending batch protection and account isolation; static source checks for absent write transport. Native Android and Windows development builds and Flutter analyzer/tests run on PR.

## Safety limits

- The existing v410 website still unconditionally UPSERTs full cloud states. Native production write safety remains **unsolved** until every website and native writer participates in a verified database-side atomic, idempotent protocol.
- Priority-only local proposal review is **not a production edit**, not restored automatic editing, and does not prove all 307 audited website features are implemented.
- Offline device snapshot is a deliberately lossy **read-only** projection. It never becomes the source of a pending review; **all staging and inspections require a fresh authenticated full-state SELECT**.
- No Supabase INSERT, UPDATE, UPSERT, DELETE, RPC, SQL migration, Edge Function, website deployment, or change to the personal/Plus repositories occurs in this milestone.
- The encrypted review can be lost after OS key revocation/reinstall and is explicitly removed on sign-out. Never treat review data as a v410 backup.

## Next

Milestone 33 — coordinated multi-writer transactional readiness, conflict-aware user workflows and authenticated staging acceptance before any production writes; separate explicit approval is required for changes to the original website and Supabase.
