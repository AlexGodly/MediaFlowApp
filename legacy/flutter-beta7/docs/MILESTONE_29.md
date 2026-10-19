# MediaFlowApp — Milestone 29: v410 Business Logic Reference Parity

**Date:** 2026-10-14  
**Source:** Original personal MediaFlow v410, read-only GitHub source (not a rebuilt web runtime).  
**Safety:** Native Supabase writes, XP awards, History mutations and offline upload remain disabled.

## Concrete additions

1. **Scheduler (v90/v410 base):** Pure-native grouping of multiple category session rows into one logical logging action, exclusion of skipped rows, weighted consumption share across 3/7/30-day and lifetime windows, bounded suggested logging amounts, and deterministic (zero-jitter) score calculations. The JavaScript reference uses a frozen synthetic clock.
2. **Seasons (v252):** Source-referenced numeric normalization, Specials naming, stable season-number sorting, total/progress clamping, aggregate values, and season offset. Inputs remain unmodified.
3. **Advanced Logging (v369/v394):** Verbatim source-backed checks for exact contiguous units, mixed/gapped episode detection, seconds/minutes runtime accounting, and optional manual total runtime. Nothing is submitted or awarded.
4. **Collection & Personal Order XP event *detection* (v348):** Compare original/current memberships and relative ordering; distinguish added titles, assigned Collections, reordered titles, and moved Collection queues. Rewards are **not actually granted** and the site-specific suppression/import guards still require end-to-end testing.
5. **Cross-language fixtures:** The exact pinned original JavaScript implementations live under `tool/parity/m29_website_reference.mjs` with source blob IDs; fake `S`, frozen `Date.now`, isolated action callbacks and synthetic test vectors live under `test/fixtures/m29_business_rules_vectors.json`. Dart independently verifies the same scenarios under `test/native_m29_business_parity_test.dart`.
6. **CI:** Run original JS vectors alongside the M23–M25 legacy reference checks, M26 feature inventory, and M28 lossless contract before Flutter analysis/tests and platform builds.

## Critical limitations

This milestone expands **source-backed parity coverage**, not full website behavior equivalence. Original v410 is an evolving layered system; newer runtime overrides, real consumption XP formulas, achievement promotion, stochastic scheduler paths, logging/season mutation side effects, respect rewards, fresh episode provider state and entire UI action workflows need additional evidence before full signoff. In particular, v348 reward event detection is not XP accounting or idempotent authoritative awarding.

The 307 feature requirements in M26 remain individually unverified until full workflows, safety and native-device tests pass. These partial results never authorize cloud writes or a switch to a read/write account model.

No original website, MediaFlow Plus repo, production Supabase, owner data, or personal MediaFlow configuration is changed.

## Source anchors

- `src/js/features/scheduler/007-scheduler.js`
- `src/js/components/186-v252-seasons-view.js`
- `src/js/components/267-v369-itemized-logging.js`
- `src/js/components/288-v394-advanced-logging.js`
- `src/js/components/245-v348-universal-streak-action-xp.js`

All excerpts are included verbatim inside the pinned original-JS runner; helpers represent synthetic environment only, not a full browser runtime.

## Next: Milestone 30 — Shared Synchronization Architecture

Design and test revision integrity, no-loss updates, conflict detection, and a coordinated website/client migration plan in isolation. **Do not deploy a change to production Supabase or the website without a separate explicitly approved safe migration.**
