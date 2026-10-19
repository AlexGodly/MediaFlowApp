# MediaFlowApp

## Current feature release: Beta 8 — account-owned cloud Logging drafts (MediaFlow v507)

[Beta 8 implementation and limitations](docs/releases/app-v1.0.0-beta.8.md). Advanced Logging drafts now have an actual separate, RLS-protected Supabase store, lossless itemized draft restore, automatic and manual Save, and cross-device revision conflict protection. The native app still does **not** submit consumption History, XP, tasks or overwrite the website's authoritative Library. The newly added `mediaflow_native_logging_drafts` table has no pathway into `mediaflow_states`; this is a functional cloud draft backup, not complete account sync.

## Previous feature release: Beta 7 (MediaFlow v507 reference)

[Native experience and cloud safety audit](docs/BETA7_NATIVE_EXPERIENCE_AUDIT.md) · [Beta 7 release notes](docs/releases/app-v1.0.0-beta.7.md)

Beta 7 refreshes **the existing Flutter app** with an atmospheric, token-based visual system, layered shared panels, search across all 14 native destinations, cloud read-status visibility on desktop/mobile/Settings, manual cloud snapshot refresh and bounded foreground refresh. Existing account snapshots remain owner-scoped with protected offline recovery. **This does not enable bidirectional cloud account-data writes**, including Advanced Logging submissions/History/XP; these require coordinated website-native atomic sync validation. Android/Windows/iOS release artifacts are gated by CI; the iOS developer archive is unsigned.


Native Flutter application for Android, iOS, and Windows. The historical parity inventory remains pinned to personal MediaFlow **v410**, while new incremental feature work follows the **latest verified personal MediaFlow** (v478 at the start of the first feature release).

## New development direction — feature-by-feature releases

Rather than treating the old milestone plan as proof of complete parity, app updates now implement focused slices of the latest personal MediaFlow. The first update introduces **MediaFlow Recommends inside native Logging** (saved task exact-ID selection and clearly labeled Personal Order queue preview), based on the v478 experience. Beta 2 adds an opt-in bounded queue browser for additional verified Personal Order titles and caches costly status/queue lookups to reduce stutter on very large Libraries. These are local-only previews; authenticated production Library/History/XP writes remain disabled.

Feature releases use independent app tags (starting `app-v1.0.0-beta.1`) with named GitHub prereleases and detailed change descriptions. The new `.github/workflows/native-feature-release.yml` pipeline runs Flutter analysis/tests, creates an Android debug APK, a Windows x64 application ZIP, and an **unsigned** iOS IPA developer archive, then publishes only if all packages pass. **Unsigned iOS is not installable on a normal iPhone**; an Apple Developer account, certificates and provisioning are needed for a signed IPA/TestFlight build. See `tool/releases/current.json` and `docs/releases/`. Each future release needs a new tag and changelog.

## Goals
- Reimplement the MediaFlow v410 interface and functionality in native Flutter (not WebView).
- Keep the original website and repository unchanged.
- Reuse existing Supabase accounts and user data without duplicating libraries.
- Preserve offline support, themes, import/export, logging, collections, statistics, and settings.
- Validate functionality against an explicit v410 parity inventory before production releases.

## Release policy
- Public feature release tags: `app-v1.0.0-beta.1`, `app-v1.0.0-beta.2`, etc. (separate from personal website's numeric version).
- Each release includes changelogs and verified platform build artifacts.
- Android APK and Windows packages are distributed through GitHub Releases.
- Unsigned iOS developer IPA can be built on a macOS runner, but signed device distribution requires valid Apple Developer signing and provisioning. Do not present an unsigned archive as an installable iPhone app.
- Do not publish a production release until required build and parity checks pass.

## Native app identity

- **Name:** MediaFlow
- **Android package/application ID:** `com.alexgodly.mediaflow`
- **iOS bundle identifier (template):** `com.alexgodly.mediaflow`
- **Windows executable:** `MediaFlow.exe`
- **App icon:** original MediaFlow logo from the personal website (source-pinned, rebuilt into native Android/iOS/Windows launcher resources).
- **Dart import/package name:** `mediaflow_app` remains internally unchanged to preserve source compatibility; it is not the installed app identifier.

## Development status — Milestone 57 isolated PostgreSQL transaction

**Milestone 57:** [Server-side staging transaction and integration tests](docs/MILESTONE_57.md). Added a private-schema PostgreSQL 17 reference transaction with owner-scoped revisions, trigger-maintained SHA-256 wire digests, durable database receipts, private SECURITY DEFINER core and authenticated-only SECURITY INVOKER RPC wrappers. GitHub Actions creates an **ephemeral local PostgreSQL service** to run SQL, privilege, replay, and two-connection race tests. **No Supabase staging project was provisioned or contacted. Production website and native account writes remain unchanged and disabled.** This does not prove feature-level v410 side-effect parity, website compatibility, or production readiness.

## Development status — Milestone 56 synchronization source audit

**Milestone 56:** [Source-backed writer inventory and staging plan](docs/MILESTONE_56.md) · [machine-readable writer/threat ledger](docs/parity/m56_writer_inventory.json). Identified **18 source-linked writer-related surfaces** (14 website / 4 native), including the legacy direct `mediaflow_states` UPSERT and its normal/Sync Now/backup-restore callers. Ran a **12-scenario synthetic, in-memory staging safety rehearsal**, documented 8 discovery gaps and 8 blocked staging prerequisites. Added a **read-only Settings staging preflight panel** and CI guard. **No staging Supabase database was provisioned, no production data was accessed, no website/Supabase changes were made, and native cloud writes remain disabled.** This is not an exhaustive cloud-writer certification or production cutover.

## Development status — Milestone 55 release-readiness audit

**Milestone 55 assessment:** [Read the release readiness report](docs/MILESTONE_55.md) and [machine-readable v410 gate ledger](docs/parity/m55_release_readiness.json). The original milestone roadmap has reached its **final assessment checkpoint**, but the Flutter app is **NOT RELEASE READY** and **NOT 100% v410 feature-parity certified**. Of the 307 inventoried source surfaces and 54 cross-device journeys, **zero have complete, recorded parity sign-off**; that does not mean the app has no working features. There are 12 explicit release blockers. Native account-state cloud writes remain disabled and M56–M70 are proposed continuation steps, not approval to change the personal website or production Supabase.

Milestone 54's 393 passing automated tests and Android/Windows validation builds were engineering checks, not signed deliverables, iOS testing, or exhaustive website acceptance.

### Earlier engineering milestones
- Milestone 37 adds a real native Library **create/edit/delete/restore/bulk** local change planner with explicit preview, undo/redo and stale-source quarantine. It is owner-scoped RAM-only; cloud editing and synchronization stay OFF. [Details](docs/MILESTONE_37.md).
- Milestone 36 adds an actual account-scoped **Stopwatch**, v256-inspired **Runtime Calculator** (carry-forward and multi-row), and read-only **Rate Your Library / Missing Covers** suggestion panels to the Flutter Dashboard. No logging, XP or cloud state is written. [Details](docs/MILESTONE_36.md).
- Milestone 35 completes a native, responsive login/signup/password-recovery **subset** and owner-validated Supabase Auth password update path; it expands synthetic four-client CAS acceptance tests. Real password recovery deep-link registration still requires device configuration and QA, and production cloud data writes remain disabled. [Details](docs/MILESTONE_35.md).
- Milestone 34 implements a responsive **Conflict Resolution Center** for encrypted priority-only offline intents: Before / Your draft / Cloud comparison, full-wire cloud drift warning, per-title diagnostics and user-confirmed local discard/recreate with fresh owner-scoped revalidation. **No cloud writes, automatic uploads or production sync have been enabled.** [Details](docs/MILESTONE_34.md).
- Milestone 33 implements an encrypted, owner-scoped **offline priority draft** store, app-restart recovery, manual fresh-cloud conflict checking, and a Settings review/discard panel. Full roadmap **offline editing with automatic cloud synchronization remains blocked** because real atomic cross-writer CAS and verified web/native writes are not yet deployed. [Details](docs/MILESTONE_33.md).
- Milestone 32 adds a real signed-in, **read-only** Settings Priority review: verified online Library priority sketches can be encrypted as inert pending-review records and checked against a fresh full cloud SELECT, with explicit conflict/discard UX. **No upload or cloud writing is enabled.** [Details](docs/MILESTONE_32.md).
- Milestone 31 integrates an offline-first read-only coordinator into the real Supabase repository: authenticated encrypted recovery, memory-only fallback, explicit reconnect status, stale refresh suppression and fail-closed malformed-cloud handling. [Details](docs/MILESTONE_31.md). **No production cloud writes or offline editing.**
- Milestone 30 adds a local-only, revisioned and idempotent shared synchronization contract simulation and coordinated website/server migration plan. **No production sync writes or migration were enabled.** [Details](docs/MILESTONE_30.md).
- Milestone 29 adds source-pinned v410 scheduler, season, advanced-logging and Collection/Personal Order action-trigger regression parity checks. **These are isolated, no-write reference subsets, not full 307-feature or runtime behavior certification.** [Details](docs/MILESTONE_29.md).
- Milestone 28 adds a lossless, source-backed full-state model that preserves all unknown JSON fields and original gzip/string/map formats for **local testing only**. See [Milestone 28](docs/MILESTONE_28.md). Cloud writes remain disabled.
- Milestone 27 introduces source-backed Dark/Light/AMOLED design tokens, shared widgets and adaptive navigation; reuses the original MediaFlow launcher logo within the Flutter shell and login screen. Full screenshot/font/custom-theme parity is still pending (see [Milestone 27](docs/MILESTONE_27.md)).
- Milestone 26 adds a source-pinned 307-feature / 21-domain v410 parity inventory, 54 concrete cross-device test journeys, 38 default settings keys, 30 candidate state roots and a CI guard. **The inventory is not proof of complete native functionality**; all features remain parity-unverified until tested.
- Native adaptive Flutter UI is implemented for **Library, Dashboard, History, Collections, Statistics, Personal Order, Logging browser, Account, and device-local Settings**. Some screens remain read-only projections; they are NOT 1:1 website parity.
- Existing Supabase accounts and original compressed cloud snapshot are reused. Account data is not mirrored into new public tables.
- Authentication and local Dark/Light/AMOLED preferences are implemented; advanced web settings and actual persistent edit/logging workflows remain incomplete.
- Milestone 25 audits v348 action XP rates, universal-streak rewards and ledger extras with **shared original-JavaScript/Dart fixtures**, compact read-only cloud/offline projections and a safe Settings diagnostic; actual XP awards and cloud writes remain OFF.
- Milestone 24 configures the native name/package/icons across Android/iOS/Windows, and source-verifies read-only v120 completion XP ledger idempotence and v331 per-title History timestamps. **Production cloud/History writes and XP awards remain OFF.**
- Milestone 23 runs pinned original v410 JavaScript functions against the same fixtures as native Dart; adds logical History action counts, known XP audit with unresolved rewards, conservative completion evidence, and category grouping previews. **Cloud/History writes and XP awards remain OFF**.
- Milestone 22 preserves read-only v252 season IDs and v369 itemized History units, adds conservative contiguous-progress and season draft previews, native itemized forms and Settings review, and 100K archived-session synthetic tests. **Cloud writing, History and XP rewards remain OFF.**
- Milestone 21 adds source-grounded Last Progress and Repeat logging draft previews, provisional completion/History summaries, v149 historical-day streak diagnostics, contiguous-unit calculation, and regression fixtures; **exact XP, advanced seasons/unit submission, History writes and cloud writes remain OFF**.
- Milestone 20 adds Library title draft forms (status/priority/progress/rating), Logging units/minutes/note draft form, shared signed-in RAM workspace, stale snapshot quarantine, Settings review/discard and synthetic 100K tests. **These are local previews only**: History/XP/cloud are never changed.
- Milestone 19 adds exact owner/revision/full-payload conflict anchors, encrypted pending-review records, a simulated atomic/idempotent server, timestamp-collision checks and a synthetic Settings lab. **Production cloud writes and offline replay are still disabled**; all web/cloud writers need an aligned server-enforced CAS protocol before enabling them.
- Milestone 18 encrypts native offline snapshots with AES-256-GCM and per-account OS-protected keys, invalidates old plaintext caches, and validates tampering/key loss/recovery. Cloud writes remain OFF.
- Milestone 17 adds verified, owner-scoped, device-local read-only snapshots with previous-generation recovery, explicit offline warnings and Settings cache controls. Offline cloud edits and write replay remain OFF; legacy plaintext caches are discarded on upgrade.
- Milestone 12 adds cached History search/filter indexing and per-snapshot Collections resolution/progress caching, with synthetic 50,000-session tests.
- Milestone 11 adds a lazily sorted Library index, bounded search-result cache, filter/sort parity tests and a synthetic 100,000-title benchmark. This does not establish real-device 100K performance.
- Milestone 10 adds a **memory-only, account-scoped local draft journal** with all-or-nothing preview, revision quarantine, strict ownership checks, versioned JSON format and an interactive synthetic-data lab in Settings. It does not edit real accounts or survive restarts.
- Cloud saves are **disabled by design**. Milestone 09 audited the original v410 UPSERT mechanism and added an owner-checked local compare-and-swap proposal planner, in-memory conflict tests, gzip round trips and Settings diagnostics.
- A draft RLS-invoker CAS SQL function exists **only for review** and was **not deployed**. The original website still uses unconditional UPSERT; therefore a native CAS RPC alone would not provide full cross-device safety.
- Automated Flutter analysis/tests and Android debug/Windows build validation are configured in GitHub Actions. See actual workflow runs for pass/fail status.
- No signed APK, Windows package, or iOS IPA has been released. Production native edits, full Logging/XP/history parity, automatic offline cloud-write queue, advanced Collections/Personal Order behavior, production device tests, and 100K-title benchmarks remain pending.
- Original MediaFlow and MediaFlow Plus repositories and production data remain unchanged.

**Development reports:** [Milestone 29](docs/MILESTONE_29.md) · [Milestone 28](docs/MILESTONE_28.md) · [Milestone 27](docs/MILESTONE_27.md) · [Milestone 26](docs/MILESTONE_26.md) · [v410 parity inventory](docs/parity/v410_feature_inventory.json) · [interaction matrix](docs/parity/v410_interaction_matrix.json) · [Milestone 25](docs/MILESTONE_25.md) · [Milestone 24](docs/MILESTONE_24.md) · [Milestone 23](docs/MILESTONE_23.md) · [Milestone 22](docs/MILESTONE_22.md) · [Milestone 21](docs/MILESTONE_21.md) · [Milestone 20](docs/MILESTONE_20.md) · [Milestone 19](docs/MILESTONE_19.md) · [Milestone 18](docs/MILESTONE_18.md) · [Milestone 17](docs/MILESTONE_17.md) · [Milestone 16](docs/MILESTONE_16.md) · [Milestone 15](docs/MILESTONE_15.md) · [Milestone 14](docs/MILESTONE_14.md) · [Milestone 13](docs/MILESTONE_13.md) · [Milestone 12](docs/MILESTONE_12.md) · [Milestone 11](docs/MILESTONE_11.md) · [Milestone 10](docs/MILESTONE_10.md) · [Milestone 09](docs/MILESTONE_09.md) · [Milestone 08](docs/MILESTONE_08.md) · [Milestone 07](docs/MILESTONE_07.md) · [Milestone 06](docs/MILESTONE_06.md) · [v410 parity audit](docs/V410_PARITY_AUDIT.md).

Source: https://github.com/AlexGodly/MediaFlow (VERSION 410 verified on 2026-10-13).
