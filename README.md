# MediaFlowApp

Native Flutter application for Android, iOS, and Windows, based on MediaFlow web v410.

## Goals
- Reimplement the MediaFlow v410 interface and functionality in native Flutter (not WebView).
- Keep the original website and repository unchanged.
- Reuse existing Supabase accounts and user data without duplicating libraries.
- Preserve offline support, themes, import/export, logging, collections, statistics, and settings.
- Validate functionality against an explicit v410 parity inventory before production releases.

## Release policy
- Public tags and release names: `v410`, `v411`, etc.
- Each release includes changelogs and verified platform build artifacts.
- Android APK and Windows packages are distributed through GitHub Releases.
- iOS IPA requires macOS/Xcode and valid Apple signing/provisioning; installation/distribution depends on Apple rules.
- Do not publish a production release until required build and parity checks pass.

## Native app identity

- **Name:** MediaFlow
- **Android package/application ID:** `com.alexgodly.mediaflow`
- **iOS bundle identifier (template):** `com.alexgodly.mediaflow`
- **Windows executable:** `MediaFlow.exe`
- **App icon:** original MediaFlow logo from the personal website (source-pinned, rebuilt into native Android/iOS/Windows launcher resources).
- **Dart import/package name:** `mediaflow_app` remains internally unchanged to preserve source compatibility; it is not the installed app identifier.

## Development status (milestone 28)
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

**Development reports:** [Milestone 28](docs/MILESTONE_28.md) · [Milestone 27](docs/MILESTONE_27.md) · [Milestone 26](docs/MILESTONE_26.md) · [v410 parity inventory](docs/parity/v410_feature_inventory.json) · [interaction matrix](docs/parity/v410_interaction_matrix.json) · [Milestone 25](docs/MILESTONE_25.md) · [Milestone 24](docs/MILESTONE_24.md) · [Milestone 23](docs/MILESTONE_23.md) · [Milestone 22](docs/MILESTONE_22.md) · [Milestone 21](docs/MILESTONE_21.md) · [Milestone 20](docs/MILESTONE_20.md) · [Milestone 19](docs/MILESTONE_19.md) · [Milestone 18](docs/MILESTONE_18.md) · [Milestone 17](docs/MILESTONE_17.md) · [Milestone 16](docs/MILESTONE_16.md) · [Milestone 15](docs/MILESTONE_15.md) · [Milestone 14](docs/MILESTONE_14.md) · [Milestone 13](docs/MILESTONE_13.md) · [Milestone 12](docs/MILESTONE_12.md) · [Milestone 11](docs/MILESTONE_11.md) · [Milestone 10](docs/MILESTONE_10.md) · [Milestone 09](docs/MILESTONE_09.md) · [Milestone 08](docs/MILESTONE_08.md) · [Milestone 07](docs/MILESTONE_07.md) · [Milestone 06](docs/MILESTONE_06.md) · [v410 parity audit](docs/V410_PARITY_AUDIT.md).

Source: https://github.com/AlexGodly/MediaFlow (VERSION 410 verified on 2026-10-13).
