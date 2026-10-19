# MediaFlowApp — Milestone 22: Season & Itemized Logging Read-Only Parity

**Baseline:** Milestone 21; original MediaFlow v410.
**Cloud writes, History submissions, XP awards, offline mutation/replay:** DISABLED.
**Scope:** only independent native `AlexGodly/MediaFlowApp`; original website, MediaFlow Plus, production Supabase untouched.

## Verified source references

Original website inspected read-only:
- `src/js/components/186-v252-seasons-view.js`: `v252NormalizeSeason`, `v252NormalizeSeasons`, `v252SeasonAggregate`; normalized seasons have stable IDs, numbers, total/progress, and an aggregate.
- `src/js/components/267-v369-itemized-logging.js`: `v369ContiguousProgress`, `v369KnownUnits`, `v369ProjectedTitleProgress`, `v369AddUnit`; unit number, season ID, repeat, timestamp and duration fields.
- `src/js/components/288-v394-advanced-logging.js`: `v394Relevant`, `v394ExactContiguous`, `v394RuntimeForEntry`; season grouping and runtime semantics.

## Implemented

1. **Preserve season evidence:** The native `MediaFlowSeason` projection now retains real `id`, `number`, `synthetic`, `progress` and `total` fields. Existing read-only title views retain their previous constructor compatibility.
2. **Preserve itemized History evidence:** Each native `MediaFlowSessionTitle` can retain v369 archived units with ID, number, season ownership, repeat flag, logged timestamp and duration seconds. Device offline cache still stores only a deliberately lossy read-only projection, not the complete original cloud state.
3. **Deterministic itemized preview:** The pure `NativeItemizedParity.calculate` groups units by selected season, reads compatible historic unit evidence, advances only a contiguous numbered sequence and projects per-season and whole-title progress. Gaps do not invent missing episodes. Repeat entries count as hypothetical History consumption but do not advance Library progress.
4. **Fail-closed data integrity:** Missing or duplicate season IDs, a season aggregate mismatching title progress, unknown season selection, missing season IDs on archived units, duplicates, over-limit units, invalid duration and unverified repeat state are rejected. A detached synthetic test catches stale/foreign archive ambiguity.
5. **Native form:** Logging title details include **Draft itemized / season units**. The responsive form accepts an actual season, comma-separated unit numbers and seconds per unit, displays a progress/duration diagnostic and keeps the result only in RAM. No History, XP or Supabase writes.
6. **Draft isolation:** Milestone 20 workspace now stores account-scoped itemized previews separately, prevents competing standard/title drafts for the same title, warns on stale sources and clears them on sign-out. Settings provides itemized review and individual discard.
7. **Regression tests:** Source-derived example fixtures, gaps, historic archived units, repeats, season grouping, fail-closed invalid inputs, offline codec roundtrip, workspace isolation, native form controls and a synthetic 100,000-session sweep.

## Scope limits

The original v410 website's live itemized submission involves active recommendation/task flow, per-unit event IDs and wall-clock timestamps, exact seconds, health status, XP ledgers, completion timeline, mixed timestamps, bulk logging, conflict merges, history-session grouping, and multiple later function overrides. **Those side effects are not reproduced or applied.** The unit preview **does not assert 100% runtime parity** and is not an uploadable state-data patch. Archived units may predate v369 and be incomplete; where season attribution is unknowable, we quarantine rather than guess.

An existing older unencrypted or version-1 read-only cache may lack season IDs and archived unit records; an online refresh provides the complete available evidence. GitHub build validation is a CI compilation check, not an actual signed Android/Windows release, live device speed proof, or production parity certification.

## Next

Milestone 23 should focus on a fixture-driven source/runtime parity harness for comprehensive History/XP and v410 advanced logging side effects. Real cloud editing remains blocked until every cloud writer and the original website adopt a common server-enforced atomic revision protocol.
