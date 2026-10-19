# MediaFlowApp — Milestone 34: Native Conflict Resolution Center

**Date:** 2026-10-14  
**Implemented:** Owner-scoped, device-local manual comparison and recovery for saved M33 **priority-only** offline drafts.  
**Production cloud writes / offline sync:** **DISABLED**. This is not a solution to the website's legacy unconditional full-state UPSERT.

## Delivered

1. **Real native Settings conflict center:** Open Settings → Conflict Resolution Center. Load the saved encrypted M33 draft queue and explicitly **Review fresh cloud**. For each draft, show title, *Before* (the stored prior priority), *Your draft* (desired priority), and *Cloud* (priority from freshly authenticated, owner-scoped SELECT). Responsive Wrap/Column layout works on small and wide screens.
2. **Per-title diagnoses:** Independently report unchanged, already desired (but no proof the draft was saved), changed elsewhere, missing title, duplicate ID, malformed cloud priority, and unavailable cloud. One bad title does **not** hide diagnostics for the others. An unchanged priority is **not** permission to upload.
3. **Full payload integrity:** For cloud-originated M33 drafts, compare both the original full-state SHA-256 digest and exact cloud timestamp against the fresh row to warn about unrelated changes in History, XP, Settings, Collections, or other roots. v410 anonymous/unknown state fields are not removed, copied to the queue or overwritten.
4. **User decisions:** Keep (no action), Discard (delete selected *device-only* intent), or Recreate (explicitly build a brand-new *device-only* priority intent against verified fresh cloud state). Recreate is disabled for missing/duplicate/malformed/already-desired values and requires another fresh SELECT matching the reviewed full digest and timestamp. Every recreated operation gets a distinct ID and captures the latest value as its new "Before". Nothing is automatically merged, retried or uploaded.
5. **No false revision provenance:** If an operation is recreated alongside retained originals from different baselines, the new queue uses the explicit **mixedManual** unanchored source and has NO cloud revision/digest. A fully recreated set may carry a new authenticated full-state digest, but remains inert.
6. **Encrypted crash/restart safety:** Rewrites use the owner's existing AES-GCM M33 draft storage and require an exact queue ID/digest match. A successful pruned rewrite deletes the old fallback-generation file so deliberately discarded entries are not retained in normal recoverable backups. Power failure at an arbitrary instant cannot be promised to securely erase previous generations; sign-out/device key erasure remains the definitive local wipe. Existing sign-out cleansing preserves owner isolation. A write or cloud-check failure leaves the old queue unchanged.
7. **Tests and CI:** Pure multi-conflict matrix, unrelated cloud changes with same timestamp, owner-switch, duplicate IDs, unavailable cloud, outdated local queue, stale recheck, confirmed per-item discard/recreate, no auto-upload, and unchanged History/XP. Source guard enforces shared cloud mutation gates remain OFF.

## Blockers to actual cross-device conflict-free synchronization

- The original personal MediaFlow website still uses a direct full-state `mediaflow_states` UPSERT. A native mutation could be overwritten by that writer regardless of client-side checks. **M34 cannot safely enable production write transport.**
- No verified shared PostgreSQL CAS RPC, durable idempotency receipts, cross-writer migration, or old-writer revocation has been deployed. This requires separate approval, controlled staging and rollout.
- This milestone resolves the UX and local integrity side of **priority-only** conflicts, not full v410 logging, Collections, progress, XP, or History edits.
- Android/Windows CI builds are unsigned development validation and not tested across physical devices. Apple iOS signed distribution remains unavailable until the full app is production-ready and proper signing is configured.

**Repositories changed:** `AlexGodly/MediaFlowApp` only. No user cloud data, Supabase project, MediaFlow website, or MediaFlow Plus mutations.

## Next

Milestone 35: expand native edit/action parity and stage transactional multi-writer integration tests without enabling cloud mutations. The full M31–M34 production edit/sync blockers must be cleared before any cloud-write feature or automatic offline upload can be considered complete.
