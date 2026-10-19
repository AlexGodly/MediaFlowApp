# MediaFlowApp — Milestone 25: XP Settings, Universal Action Rewards and Ledger Audit

**Baseline:** Milestone 24 / original MediaFlow web v410. **Status:** native read-only audit and source parity fixtures. Cloud writes, XP awards, and History submissions are DISABLED.

## Preserved native identity

- Android package/namespace: `com.alexgodly.mediaflow`; iOS bundle identifier: `com.alexgodly.mediaflow`.
- Android/iOS display name: MediaFlow. Windows executable: `MediaFlow.exe`.
- Android, Windows and iOS icon generation continues using pinned *original MediaFlow logo* and existing `tool/branding/apply_branding.py`. No rename of Dart's internal `mediaflow_app` module.
- These identity changes were already completed and built successfully in Milestone 24; this milestone preserves them and does not replace the original icon.

## Source-verified improvements

1. The original website's `v348Enabled`, `v348Multiplier`, `v348Multiply`, `v348Rate`, `v348Award`, `v348ExtraXP` and `v348RaiseNewRewards` functions and original `v149StreakMultiplier` are copied verbatim into `tool/parity/m25_website_reference.mjs` with pinned original source blob SHAs. Synthetic fixture state and stub storage functions prevent production mutation. The same fixture JSON is checked independently in Dart.
2. `MediaFlowXpEvidence` reads an account's `settings.leveling` and configured v348 rates (7 supported actions) as a **restricted, read-only projection**. It detects the leveling enable state and the universal streak switch. No account settings editor is added.
3. Native v348 rate bounds, fallback defaults, amount rounding, universal-streak multiplier and reward preview calculations are unit-tested against pinned original JavaScript outputs. The preview has no submit/award operation.
4. Summaries of `xpLedger.v348ActionEvents`, `v348LibraryAdditionBonus` and `v348LibraryCompletionBonus` can be displayed as *known extra XP*. `logCompletions` entries are counted separately but **not added again** to v348ExtraXP. No event IDs or event metadata are copied into the encrypted offline projection.
5. `v348RaiseNewRewards` parity previews reward only **new increases** to existing fixed ledgers. If the streak grows later, prior grants are never multiplied again. Reordered Collections, Personal Order and Batch Log real action detection remain dependent on full website workflows and are NOT triggered by a preview.
6. A responsive Settings card displays read-only XP evidence, missing/invalid source warnings, known extra ledger totals, and a switchable hypothetical action/streak example. It never offers to save a reward, change the cloud ledger or edit leveling preferences.
7. Cloud snapshot extraction now retains only bounded XP evidence through the native catalog. The encrypted owner-scoped offline cache persists the compact summary, not full XP ledger event IDs; no new public storage or user data duplication is introduced.
8. Automated fixtures include enable/disable and universal multiplier toggles; default/custom/clamped/invalid rates; fractional quantities; no-action; ledger sum/double-count controls; incremental reward math; privacy-preserving encrypted projection roundtrip; a synthetic 100,000-event benchmark; and Settings widget checks.

## Deliberate limits

- The XP diagnostics are not the account's authoritative total XP, current level, or guaranteed awards. Missing legacy XP, health/category multipliers, completion timeline and v410 runtime hooks are not reconstructed.
- Some malformed or infinite XP ledger values are quarantined rather than trying to emulate unsafe JavaScript Infinity summing. The audit explicitly marks those values and never enables cloud writes.
- The original website still uses unconditional whole-state writes; real native edits remain blocked on a coordinated server-enforced CAS migration adopted by every cloud client. Personal MediaFlow web, MediaFlow Plus and Supabase are not modified.
- iOS icon/bundle configuration is checked by Flutter CI on a generated template, but no signed iOS IPA is claimed. Android and Windows CI builds are development validation only, not production releases.

## Validation and next milestone

- `node tool/parity/m23_website_reference.mjs`, `node tool/parity/m24_website_reference.mjs`, `node tool/parity/m25_website_reference.mjs` and Flutter tests run on GitHub CI.
- Android debug and Windows validation builds compile on the merged `main` commit. Check actual GitHub Actions conclusions for pass/fail before announcing a successful build.
- **Milestone 26:** expand verified action/History side-effect fixtures, XP settings coverage and native feature completeness; retain read-only mode until the cross-client transactional save protocol is ready.
