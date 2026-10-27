# MediaFlowApp v1.0.0 Beta 3 — Searchable Logging Recommendations

**GitHub Release tag:** `app-v1.0.0-beta.3`  
**Reference:** latest confirmed personal MediaFlow **v478 Stable** (2026-10-17). Native remains a focused feature subset, not full v478 parity.

## Added
- **Search inside the Logging MediaFlow Recommends queue.** Search by Library title or exact-ID fragments within the verified, eligible Personal Order candidates.
- **Selection filters:** **Not added**, **All**, and **Already added** (the latter makes it easy to revisit a previously selected recommendation).
- **Real paging:** Five queue results per page with Previous/Next controls, matched-result counts and page totals. Unlike Beta 2, browsing is not limited to the first five additional entries.
- **Bounded preview list:** At most **500 uniquely verified candidates per category and snapshot**. A visible message explains when the cap is reached. This is deliberately bounded to protect large libraries from unbounded UI growth.
- **Selected-title distinction:** Already added entries display a check icon and the action becomes a local review rather than duplicate submission.
- **Performance:** Indexes queue evidence only after expansion, reuses it for searches and filters, and does not repeat a 100k-title duplicate scan on each checkbox tap.
- **Mobile responsiveness:** Filter chips wrap on compact 320px screens. Search and page navigation remain accessible without enlarging the rest of the Logging UI.

## Preserved
- **Saved active task** is the primary recommendation; a missing/duplicate task ID cannot be replaced with a guessed queue title.
- Collection-origin and exact Personal Order queue position indicators, category chooser, direct local selection and title details remain.
- Selections and existing local drafts are unchanged by search/filter/page interactions.
- No task reroll, task progress update, History/XP write, media metadata provider call, real task completion or production Supabase mutation.
- No modifications to the personal MediaFlow website or MediaFlow Plus.

## Validation
Flutter analysis and full regression suite, plus new tests for queue order/rank, policy disablement, duplicate IDs, missing tasks, 100,000-title catalog, and compact 320px search/filter/page selection.

## Platform packages
- **MediaFlowApp-Android-debug.apk:** debug-signed Android APK. Android package `com.alexgodly.mediaflow`. CI debug-signing keys may rotate, so replacing an older APK in-place can fail; preserve local data before changing installations. Not a Play Store release.
- **MediaFlowApp-Windows-x64.zip:** complete release-mode Windows app; extract *all* files and launch `MediaFlow.exe`. Not a signed installer.
- **MediaFlowApp-iOS-unsigned.ipa:** **unsigned developer archive, not installable on a standard iPhone**. Apple developer signing and provisioning/TestFlight remain required.
- **SHA256SUMS.txt:** checksums of every artifact.

The release workflow publishes the tag, name, this changelog and **all three archives only after** Flutter checks and platform builds succeed. A merged PR alone is not a verified published release.

## Remaining gaps
Recommendation queue entries are explicitly **Personal Order previews**, not the v478 website's complete provider-based recommendation engine. Production Logging synchronization is still disabled. Signed Android upgrades, signed Windows distribution and provisioned iOS builds remain future release-hardening work.
