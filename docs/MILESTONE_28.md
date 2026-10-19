# MediaFlowApp — Milestone 28: Full v410 Data Model Compatibility

**Date:** 2026-10-14  
**Scope:** Native read-only/local data compatibility for original personal MediaFlow v410.  
**Backend:** Unchanged. Native cloud writes remain OFF.

## Findings

The existing `MediaFlowCatalog` is a **deliberately lossy screen projection**. It drops many account fields (opaque title/provider metadata, future settings, complete XP ledgers, extra History/unit metadata, order and Collection extensions). Saving a state reconstructed from that catalog would irreversibly discard data.

## Implemented

- `lib/data/mediaflow_full_state.dart`: a defensive-copy `MediaFlowFullState` preserving all JSONB account roots and arbitrarily nested unknown fields without creating a new server-side data copy.
- Accepts and preserves original wire kind: JSONB object, JSON string, or `__mediaflowCompressed: gzip` envelope, including unknown envelope metadata. **Unmodified** wire data is returned unchanged for local tests. Modified synthetic gzip data is safely re-encoded *only in memory* and verified.
- Existing JSON scalar types, array ordering, absent-vs-null keys, provider metadata, title seasons, v369 History units, timezone strings, XP ledgers, Collection metadata, Personal Order subqueues, category state, nested settings, backup/appearance preferences and extra roots are preserved.
- A strict minimum-valid-cloud-state guard for missing/malformed core Library, Categories, Sessions, and Settings; refuses damaged record arrays, invalid Personal Order layout, or unsupported compression. It never fabricates an empty replacement state.
- Read-only accessor and source coverage report for present roots, unknown roots, nested settings and domain counts. `readOnlyCatalog()` still exposes the existing screen projection; **must never be reserialized as an account state**.
- Pure local scalar simulation with existing-path-only operations, no subtree replacement or insertion, deep copies, and reverse-diff preservation assertions. This is not a native editor and cannot write to Supabase.
- Synthetic fixture with all 38 source-pinned default settings keys and representative opaque v410 state extensions. CI guard checks 30 source-audited state root candidates and keeps all native write gates closed.
- Automated JSON-object, JSON-string, gzip-envelope, unknown-field, epoch/timestamp text, nested records, rollback/rejection, and 15K-title synthetic parity tests.

## Non-claims and remaining compatibility work

- `stateRoots` in the Milestone 26 inventory include 30 *candidates*. Not all are cloud-persisted: some are UI-only. Having a typed preservation mechanism is **not** a proven end-to-end specification of every website mutation, nested setting, file importer or backup format.
- v410 source contains late runtime module overrides; these must be tied to exact save/load code and versioned settings in Milestones 29–30 and feature milestones 36–51.
- Large synthetic fixtures do **not** certify 100K real-device smoothness.
- No authenticated live data was dumped or copied into fixtures. Synthetic test identifiers are fictional.
- Existing encrypted **offline projection intentionally stays lossy, read-only, and non-uploadable**. Do not confuse it with this complete in-memory compatibility layer.
- Neither the original MediaFlow repository/site, MediaFlow Plus, nor production Supabase is modified. Production two-way cloud writing remains blocked until Milestones 30–34 and approved website/server compatibility work.

## Source references

- `src/js/core/state/002-state.js` (original personal MediaFlow v410)
- `src/js/core/constants/001-constants.js` (38 top-level defaults)
- `src/js/components/186-v252-seasons-view.js`
- `src/js/components/267-v369-itemized-logging.js`
- `src/js/components/245-v348-universal-streak-action-xp.js`
- `docs/parity/v410_settings_data_contract.json` (pinned source contract)

## Next milestone

**Milestone 29 — Complete Business Logic Compatibility**. Extend pinned original JS-vs-Dart behavioral fixtures for logging, XP, streaks, recommendations, achievements, seasons and other side effects before enabling real writes.
