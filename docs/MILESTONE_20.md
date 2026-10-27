# MediaFlowApp — Milestone 20: Native Editing & Logging Draft Preparation

**Baseline:** MediaFlowApp Milestone 19; original MediaFlow website v410.
**Cloud writes:** OFF. **Offline write replay:** OFF. **Production Supabase and both MediaFlow websites:** UNCHANGED.

## Delivered

1. **Real-title native editing forms.** Library title details now provide a responsive, native Flutter local draft sheet for status, priority, aggregate progress and rating. It pre-fills from the authenticated read-only catalog, validates value ranges and retains edited values only in the RAM-bound draft workspace. A local draft is never saved to Supabase or the authoritative Library.
2. **Logging draft composer.** Logging title details now provide a local-only form for units consumed, runtime minutes and notes. The preview shows planned aggregate progress and pending entry count, while explicitly reporting zero History entries submitted and zero XP awarded. Logging session IDs, per-unit dates, XP, levels, streaks and other v410 side effects are **not fabricated**.
3. **Shared account-scoped workspace.** The same in-memory owner-bound workspace is passed through Library, Logging, and Settings by the signed-in native shell. On sign-out it is discarded before cloud/device cleanup; upon shell disposal it is destroyed. It is not persisted to disk, never exported to M19's pending-review queue and has no method to write cloud data.
4. **Refresh and account safety.** A different Library snapshot quarantines existing sketches instead of silently rebasing them against changed data. The user can view or discard stale drafts in Settings. Workspaces from other authenticated accounts cannot access the first owner's staged inputs.
5. **Cross-draft consistency.** Progress/total checks prevent overshoots; logging plans reject zero/invalid/negative units and invalid runtime. Title-progress edits cannot invalidate an existing logging draft, and discarding a title draft also discards its associated logging sketch.
6. **Conservative season handling.** The website stores per-season progress, so the aggregate cannot safely be edited when seasons exist. Season-based logging is blocked until v410's real season conversion and side-effect model are implemented and tested. Changes to status/progress are flagged for unverified v410 effects.
7. **Review/discard controls.** Settings > Native editing drafts shows provisional title values and logging plans, pending counts, no XP/History changes, stale warning, per-entry discard, and confirmed discard-all.
8. **Tests.** Pure behavior and widget coverage verifies input validation, preview-only behavior, no History/XP mutation, stale quarantine, account isolation, season constraints, cross-draft progress consistency, and a 100,000-title synthetic catalog draft test. Flutter CI and separate native builds required.

## Explicit limitations

- **This milestone does not implement working cloud editing, native logging submission, History creation, awarding XP, or accurate v410 full side effects.** The original v410 website remains the place to make persistent account changes.
- There is no local disk-save of these sketches; switching accounts/signing out/closing the application discards them. They are *not* part of an offline synchronization queue. Selection-only UI does not submit History.
- No original web repository or MediaFlow Plus source was edited. No production database mutation, SQL migration, Edge Function or RLS change occurred.
- Exact save behavior requires the original v410 website and all native writers to adopt coordinated server-enforced CAS and full side-effect parity (see Milestone 19).
- Large-library test is synthetic. Passing automated tests does not establish production 100k performance, signed build availability, or 1:1 functional parity.

## Next

Milestone 21: expand the local preview engine to model v410-compatible season, status, progress, History, XP and logging side effects from verified original source algorithms, with differential fixtures and explicit conflict boundaries. Only after ALL cloud writers adopt a compatible CAS protocol can the tested models be wired into real cloud writes.
