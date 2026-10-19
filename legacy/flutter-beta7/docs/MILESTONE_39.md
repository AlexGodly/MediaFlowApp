# MediaFlowApp — Milestone 39: External IDs, Seasons and Lossless Metadata Simulations

**Source baseline:** original `AlexGodly/MediaFlow` tag `410`, specifically `src/js/components/186-v252-seasons-view.js`, `273-v377-ids-editor-jikan-recovery.js`, and `274-v378-tenrai-import-logging-order.js`. **Target repo:** `AlexGodly/MediaFlowApp` only.

## Native implementation

- Read-only Library projection decodes `externalIds`, the `v377ManualExternalIds` map (including meaningful `null` overrides), season metadata `source`/`manual`/`synthetic` and `seasonSource`, not only title progress/count. Full raw state is still kept separately from the projection.
- Source-informed provider identifier validator: numeric MAL/SIMKL/AniList/TMDB/Kitsu, `tt` IMDb, ISBN, generic provider identifiers. Unrecognized valid provider keys already saved in a title are displayed and can be edited without coercion. Emptying a saved ID records a *local* `null` manual-clear marker to avoid accidental alias/import overwrite in future planned migrations.
- Source-informed v252 seasons: optional per-title season number, name, progress, total; unique season IDs; integer counters; aggregate progress and total derived from season rows. Existing overall counters are held in an **Unassigned** row when initially adding Seasons View; deleting *all* seasons on an existing title is blocked because fallback progress semantics are not fully verified.
- Actual native Library Title Details now displays IDs, intentionally cleared IDs, season provenance, and a new **Edit IDs & seasons locally** bottom sheet. Stage/undo/redo through the same M37 account-scoped device-only planner, with stale refresh quarantine, and carry metadata safely through old M37 title edits and M38 bulk metadata edits.
- Separate `MediaFlowFullState.simulateTitleMetadata` performs pure **local full JSON state simulations** for existing uniquely identified title IDs. For recognized season rows, it merges changed season fields into the original full map to preserve unknown nested fields (e.g. custom provider metadata), not rebuilding unknown objects from `MediaFlowCatalog`. A restoration check verifies that all other account roots and Library rows remain equal. It does **not** attempt to serialize the lossy Library screen projection.
- Regression suite tests valid and invalid provider IDs, manual clear precedence, season validation/aggregate, atomic failure, stale plans, undo/redo, ordinary and bulk edit carry-over, no mutation of raw source, preservation of unknown nested v410 Library/season fields and core account data, and the Flutter sheet flow. CI checks cloud-write safety.

## Important limitations

- This is a **device-only RAM preview**, not full authoritative v410 metadata editor or synchronized save. `MediaFlowFullState` edits are explicitly test-only simulations and cannot be uploaded. The original website uses unconditional full-state account UPSERT and does not yet coordinate a server CAS/idempotency contract.
- The full state simulation intentionally does not set production `modifiedAt`/`seasonsModifiedAt` timestamps or replay completion/History/XP/season import side effects; therefore it is not a production-ready writer. Older alias handling, provider verification, media lookup, unknown provider-source metadata editing, season removal fallback, season ID provenance, and all cross-device synchronization require further design and tests.
- No changes to `AlexGodly/MediaFlow`, `AlexGodly/MediaFlowPlus`, Supabase schema/data/functions/secrets, or production site. CI Android/Windows artifacts are development validation only; no signed iOS, Windows, or Android distribution is published.

**Next:** Milestone 40 — native Collections editing parity foundation and reference-safe local mutations, while keeping production writes disabled pending server-side multi-client CAS.
