# MediaFlow v410 — Native Parity Audit

**Milestone 26 source-grounded baseline.** This is the living entry point for complete MediaFlowApp parity tracking, not a claim that Flutter has all of the website's features.

## Milestone 57 — isolated atomic PostgreSQL reference (2026-10-15)

[Milestone 57](MILESTONE_57.md) introduces a private ephemeral PostgreSQL transaction and test suite with revision, full-state digest, owner checks, idempotency receipts and two concurrent sessions. The tests use synthetic owners and a **local PostgreSQL CI container**, not a connected Supabase project. Supabase Auth/RLS and real website compatibility are not certified. **No real staging deployment or production changes.** Native write gates remain disabled.

## Milestone 56 — synchronization writer discovery (2026-10-15)

[Source-backed writer inventory and isolated staging rehearsal](MILESTONE_56.md) and [machine-readable ledger](parity/m56_writer_inventory.json) identify **18 traceable write-related surfaces**, all labeled as direct writers, indirect save callers, state mutations, exports, read-only native paths, or test-only simulations. The v410 website still contains an unconditional account-state UPSERT and **8 writer discovery tasks plus 8 staging gates remain open**. The in-memory 12-scenario model is not a staging Supabase deployment. Production writing and release certification remain disabled.

## Milestone 55 — production release gate (2026-10-15)

[Milestone 55 readiness report](MILESTONE_55.md) and [machine-readable audit](parity/m55_release_readiness.json) now cross-check all 307 feature surfaces and 54 interaction cases against the original inventory, record all 21 domain summaries, track 12 blocked production release gates and propose M56–M70. **No feature or journey has been formally parity-certified yet; the app is NOT RELEASE READY.** M54's 393 passing automated tests and validation builds do not replace cross-device acceptance. Native account writes and signed production distributions remain disabled. The original milestone number 55 is not a product sign-off.

## Authoritative milestone artifacts

- [Milestone 26 report](MILESTONE_26.md)
- [Original v410 source manifest](parity/v410_source_manifest.json): 144 base modules, 157 overrides, 140 active CSS assets and 38 base settings defaults, all tied to pinned original repository references.
- [Feature inventory](parity/v410_feature_inventory.json): **307 candidate feature surfaces in 21 domains**, original source owners and current native scaffolds.
- [Settings and data contract](parity/v410_settings_data_contract.json): 38 default top-level keys, 10 Settings Center sections, 30 candidate state roots and all-client cloud revision requirements.
- [Interaction/visual QA matrix](parity/v410_interaction_matrix.json): **54 concrete flows**, phone/tablet/desktop acceptance criteria, offline/100K/conflict examples, and actual v410 screenshots still needed.
- [Guard script](../tool/parity/m26_inventory_guard.mjs) invoked from CI; the inventory cannot silently drop mandatory domains or be mislabeled verified.

## Current native implementation truth

Native Flutter shells/screens exist for Authentication, Dashboard, Library, Logging, Collections, Personal Order, History, Statistics, Account and local Settings; current features include secure read-only cloud projection and offline snapshot access, plus **RAM-only draft previews**. Most mutating website features, exact full visual parity, complete settings, scheduler logic, XP/History submissions and production cloud synchronization **are not implemented or enabled**. The feature status in the machine-readable inventory is a **coarse domain classification**. Every record intentionally says `parityVerified: false`.

## Critical behavioral constraints

1. **Never modify the original MediaFlow or MediaFlow Plus repository during native migration work without explicit separate authorization.** During this audit, both remain unchanged.
2. **Reuse existing user accounts and authorized original cloud data.** Never create a separate public copy of the user's Library for display.
3. **Keep production cloud writes disabled until all writers, including the website, use one proven server-enforced conflict/version protocol.** The original whole-state UPSERT can defeat native-only CAS.
4. Never create real History or XP entries from draft previews, nor replay an award during retry, import, or sync. Preserve unknown fields.
5. Keep canceled live MAL/SIMKL account tracking off; supported file imports are separate.
6. Native Flutter widgets (not WebView), faithful visual design, and touch/mouse/keyboard/accessibility must be verified across Android, iOS and Windows.
7. Verify 100,000-title performance with **physical-device measurements**, not only synthetic CI tests.
8. Preserve original responsive v410 behavior, notably phone dock/action sheet, multi-select pickers and Library search-focus behavior.

## What constitutes final sign-off

Every feature and interaction row must have an assigned implementation, source comparison, test evidence, working user flow, cross-device persistent-data verification where applicable, and appropriate screen references. Preserve the exact original icon and app identity: **MediaFlow**, Android/iOS `com.alexgodly.mediaflow`, Windows `MediaFlow.exe`.

**Next:** [Milestone 27](MILESTONE_26.md#next-milestone) — native design system / visual parity. The ultimate finish line is measured parity, not simply reaching a milestone number.
