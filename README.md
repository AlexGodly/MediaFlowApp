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

## Development status (milestone 17)
- Native adaptive Flutter UI is implemented for **Library, Dashboard, History, Collections, Statistics, Personal Order, Logging browser, Account, and device-local Settings**. Some screens remain read-only projections; they are NOT 1:1 website parity.
- Existing Supabase accounts and original compressed cloud snapshot are reused. Account data is not mirrored into new public tables.
- Authentication and local Dark/Light/AMOLED preferences are implemented; advanced web settings and all edit/logging workflows remain incomplete.
- Milestone 17 adds verified, owner-scoped, device-local read-only snapshots with previous-generation recovery, explicit offline warnings and Settings cache controls. Offline cloud edits and write replay remain OFF; the cache is not encrypted at rest.
- Milestone 12 adds cached History search/filter indexing and per-snapshot Collections resolution/progress caching, with synthetic 50,000-session tests.
- Milestone 11 adds a lazily sorted Library index, bounded search-result cache, filter/sort parity tests and a synthetic 100,000-title benchmark. This does not establish real-device 100K performance.
- Milestone 10 adds a **memory-only, account-scoped local draft journal** with all-or-nothing preview, revision quarantine, strict ownership checks, versioned JSON format and an interactive synthetic-data lab in Settings. It does not edit real accounts or survive restarts.
- Cloud saves are **disabled by design**. Milestone 09 audited the original v410 UPSERT mechanism and added an owner-checked local compare-and-swap proposal planner, in-memory conflict tests, gzip round trips and Settings diagnostics.
- A draft RLS-invoker CAS SQL function exists **only for review** and was **not deployed**. The original website still uses unconditional UPSERT; therefore a native CAS RPC alone would not provide full cross-device safety.
- Automated Flutter analysis/tests and Android debug/Windows build validation are configured in GitHub Actions. See actual workflow runs for pass/fail status.
- No signed APK, Windows package, or iOS IPA has been released. Native edits, full Logging/XP/history parity, offline write queue, advanced Collections/Personal Order behavior, production device tests, and 100K-title benchmarks remain pending.
- Original MediaFlow and MediaFlow Plus repositories and production data remain unchanged.

**Development reports:** [Milestone 17](docs/MILESTONE_17.md) · [Milestone 16](docs/MILESTONE_16.md) · [Milestone 15](docs/MILESTONE_15.md) · [Milestone 14](docs/MILESTONE_14.md) · [Milestone 13](docs/MILESTONE_13.md) · [Milestone 12](docs/MILESTONE_12.md) · [Milestone 11](docs/MILESTONE_11.md) · [Milestone 10](docs/MILESTONE_10.md) · [Milestone 09](docs/MILESTONE_09.md) · [Milestone 08](docs/MILESTONE_08.md) · [Milestone 07](docs/MILESTONE_07.md) · [Milestone 06](docs/MILESTONE_06.md) · [v410 parity audit](docs/V410_PARITY_AUDIT.md).

Source: https://github.com/AlexGodly/MediaFlow (VERSION 410 verified on 2026-10-13).
