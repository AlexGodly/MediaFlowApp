# MediaFlowApp — Milestone 26: Source-Pinned v410 Parity Inventory

**Date:** 2026-10-14  
**Baseline:** Original personal MediaFlow v410 (GitHub source `AlexGodly/MediaFlow`, read-only)  
**Implementation repository:** `AlexGodly/MediaFlowApp`  
**Status:** Source-level inventory and verification gates implemented; **no full application parity certification**.  
**Cloud writes:** Still deliberately disabled. No production Supabase changes, original MediaFlow changes, or MediaFlow Plus changes.

## Deliverables

| Artifact | Content |
|---|---|
| [Source manifest](parity/v410_source_manifest.json) | Pinned original-source Git blob references, **144** stable/base build modules, **157** runtime override modules, **140** active CSS files, 2 external JS script assets, 38 default top-level settings keys, v410 Settings Center categories, candidate state fields |
| [Feature inventory](parity/v410_feature_inventory.json) | **307** source-backed candidate feature surfaces in **21** domains, native file evidence, coarse native scaffold status, target implementation milestone, and mandatory acceptance condition |
| [Settings and data contract](parity/v410_settings_data_contract.json) | 38 source-extracted top-level settings defaults, 10 v365 Settings Center categories, **30** candidate state roots marked persisted/transient/unknown for further examination, and explicit cloud-write/backup safety gates |
| [Interaction matrix](parity/v410_interaction_matrix.json) | **54** concrete end-to-end workflows spanning all 21 domains, with steps, expected outcomes, device dimensions, failure/scale cases, and pending verification flags |
| [Parity guard](../tool/parity/m26_inventory_guard.mjs) | Node-only CI validator: source/file references, unique feature and flow IDs, domain coverage, exact pinned counts, settings contracts, write-disabled invariants, and mandatory noncertified status |
| [GitHub Actions](../.github/workflows/native-ci.yml) | Runs the guard alongside existing pinned original-JavaScript parity tests before Flutter analysis and tests |

## Scope and honesty of status

The existing Flutter application already has native Authentication and main-page scaffolds, read-only Library/History/Collections/Order/Dashboard/Statistics projections, encrypted offline snapshots, and RAM-only local editing/logging previews. That does **not** mean all of the corresponding website features work.

The inventory's `nativeStatus` is a **coarse domain-scaffold classification**, not a feature-by-feature implementation certificate. Counts:

- `read_only`: 149 source features whose domain has a read-only native presence; individual capabilities may be absent.
- `partial`: 69 source features whose domain has a partial native UI.
- `draft_only`: 58 source features whose domain has prototype-only edits or previews.
- `missing`: 16 source features in domains without a full native feature counterpart.
- `foundation`: 15 cross-platform/security/performance requirements with early foundations.

**0 of 307 source features are marked parity-verified.** This intentionally avoids fake progress percentages or treating UI scaffolds as working implementations. A feature becomes verified only after actual source-backed interaction tests, persistent state roundtrips, screenshots where appropriate, and real-device validation. Counts must not be interpreted as proportions of app completion.

## Source caveats

The original website's `VERSION` and `index.html` identify it as v410. The repository's `build-order.json` and `runtime-order.json` are pinned as source evidence, as are the `legacy/v/410/index.html` CSS references (including v409/v410 styling patches). The compiled `assets/js/mediaflow-v410.bundle.js` is a separately generated ~3.5MB asset and **has not been proved byte-for-byte equivalent to the concatenated source manifests**. No assumption of full runtime coverage is made.

The 38 default settings keys are **top-level keys of `DEFAULT_SETTINGS` in the pinned base constants file**, not an assertion that only 38 settings exist. Nested `v181Library`, `leveling`, `backup`, `v230ChoiceLayout`, and later runtime-added settings still need exhaustive key-by-key persistence validation. The 30 state roots are *candidates*, not claims that every UI-only field is stored in Supabase.

Existing screenshots in the website's v410 archive include earlier visual examples from v398/v400; they are **historical references, not v410 UI acceptance screenshots**. Real v410 phone/tablet/desktop snapshots across themes and empty/large/offline states remain to be captured and compared.

## Functional domains mapped to implementation work

| Area | Target milestone(s) | Verification focus |
|---|---:|---|
| Responsive shell and design system | 27 | Sidebar, mobile sheet/dock, focus and visual parity |
| Full data contract and safe synchronized writes | 28–35 | Unknown-field preservation, RLS, atomic CAS across **all** writers, recovery |
| Dashboard, recommendations and Library | 36–40 | Task logic, all Library modes/overlays, CRUD, seasons, 100K performance |
| Quick/advanced/batch logging, History, XP, Statistics | 41–45 | Side-effect parity, idempotent XP, event timestamps, complete audit |
| Collections, Personal Order, Settings, themes and portability | 46–50 | Exact user workflows, settings/picker parity, no-loss imports/backups |
| Remaining Old System/provider features and platform verification | 51–55 | All source-backed features, native equivalents, real-device QA, signed releases |

## Blocking gates before a genuine completed app

1. **Synchronizing real changes:** Original MediaFlow currently uses unconditional full-state cloud saving. Native-only CAS protection cannot prevent an old website client overwriting new native edits. A coordinated compatibility change to the original website's write path and server enforcement must be staged and explicitly approved before production activation.
2. **Native workflows:** The existence of a Flutter page is insufficient. Library mutations, Logging submissions, History/XP writes, Collections/Order edits, settings persistence, imports/backups, scheduler actions and achievements must be independently built and tested.
3. **Visual equivalence:** All 54 interaction scenarios and required new v410 screenshots need measurable UI/browser/native parity on phone, tablet and desktop.
4. **Data resilience:** Owners, unknown keys, 100K titles, incomplete/malformed cloud data, offline sign-out, concurrent edits, restart/recovery and backup integrity must be tested without corrupting the source data.
5. **Platform releases:** Android/Windows validation builds are not signed production packages. The iOS app needs macOS/Xcode and valid signing to produce a distributable IPA.

## Rules for updating the inventory

- Add all newly discovered website interactions as separate feature IDs and scenarios; never mark an untested feature complete.
- For each feature, record **exact source and Flutter owner**, automated parity test name, tested viewport, and evidence of persistent data integrity before marking verified.
- Preserve original website, MediaFlow Plus, and production Supabase untouched during source audits.
- Do not reintroduce canceled MAL/SIMKL **live** account tracking. Website-compatible file imports are a distinct feature.
- When original website is updated past v410, pin new original sources and explicitly decide whether the Flutter baseline advances.

## Next milestone

**Milestone 27 — Complete native design system and visual parity groundwork.** Establish reusable tokens/components for every site viewport and theme, capture an approved set of actual v410 screenshot states, and begin screen-by-screen conversion without bypassing the synchronized-write gate.
