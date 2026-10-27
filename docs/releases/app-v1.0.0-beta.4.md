# MediaFlowApp v1.0.0 Beta 4 — Native R2 Advanced Logging

**Reference:** MediaFlow personal website v504 Stable (October 18, 2026).
**Design input:** Approved interactive HTML prototype R2.
**Release type:** Native Flutter prerelease, not production parity certification.

## Native interface
- R2 Logging Workspace replaces the old read-only selection page as the primary Logging experience.
- The previous Logging Library browser remains accessible for comparison.
- MediaFlow Recommends requires a verified, exact current-task Library ID; title-name matching does not silently substitute a different entry.
- Browse the authenticated Library with category, status, priority, searchable title/tags, pagination, and 12 actual sort options.
- Desktop two-column and narrow mobile stacked layouts use native Flutter widgets and existing MediaFlow theme tokens.

## Advanced Logging draft behavior
- Per Unit, Last Watched/Read Unit and Amount Consumed are selectable **per title**.
- v504-inspired + / - quantity adjustments, with a directly editable numeric dialog.
- Per-unit picks and per-unit timestamps survive method switches.
- Season-specific selections remain distinct as the user switches seasons.
- Account-snapshot title progress/total caps and 2,000-unit per-season draft limit are enforced.
- Each draft includes When Watched, repeat/rewatch, runtime, note, move up/down, remove, and confirmation before clearing.
- Live Library progress is shown beside the **local preview** progress.
- Draft state is retained across normal app navigation inside the signed-in shell. Signing out destroys the account-scoped in-memory draft.

## Safety and limitations
- **No account-state writes are enabled.** Reviewing a logging draft does not commit Library progress, History, XP, activity tasks, or sync to Supabase.
- The unchanged native cloud-write gate remains disabled pending cross-device/website CAS compatibility verification.
- No claim of complete feature parity for MediaFlow v504. The existing Dashboard, Library, Collections, History, Personal Order and Settings pages remain available but are not fully redesigned to R2 in this beta.
- Per-unit cross-season history serialization and production transaction side effects remain future work.
- Existing personal MediaFlow website, MediaFlow Plus, production Supabase and its schema remain untouched.

## Tests and build
- New regression tests cover quantity bounds, timestamps through method changes, season isolation, reorder/remove/clear, and repeat preview.
- GitHub Actions must pass source guards, Flutter analyze/test, Android APK, Windows x64 package and unsigned iOS IPA jobs before publishing a prerelease.
- **Unsigned iOS IPA is not installable on a normal iPhone.** A signed distribution requires Apple Developer provisioning.
- Artifacts are available only after the GitHub Actions release workflow succeeds.

## Remaining roadmap
1. Validate actual production v504 logging submission and cross-device atomic updates, first on isolated staging.
2. Extend R2 design to Dashboard, Library, Personal Order, Collections, Statistics, History, Recovery, theme/design studio.
3. Implement the real v365 Settings Center's entire registry with source-backed value bindings rather than fake controls.
4. Complete Android, Windows and iOS end-to-end device acceptance before a stable release.
