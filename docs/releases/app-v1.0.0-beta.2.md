# MediaFlowApp v1.0.0 Beta 2 — Logging Recommendation Queue Browser

**Reference:** personal MediaFlow **v478 Stable** as of October 17, 2026. This is a progressively implemented Flutter-native feature subset, **not** full parity.

## Added
- **Browse Personal Order recommendations** directly in the native Logging **MEDIAFLOW RECOMMENDS** card. The saved current-task recommendation remains the main recommendation, while the queue browser is explicitly a separate non-authoritative preview.
- Up to **five queue titles per page**, with Previous/Next controls and a bounded **50-position** inspection window. Queue titles display their source: direct Personal Order or Collection queue, including ordinal rank.
- **Use queue title in Logging** opens the existing local title review and adds that exact Library ID to the current Logging selection. Existing selections and drafts are not cleared; selecting again reviews the same title.
- Selecting a category resets pagination; changing the cloud snapshot rebuilds the source-grounded recommendation audit. Long titles and controls support narrow 320px Android screens.
- A missing, duplicated or ambiguous Library ID is not offered as selectable. An unknown/disabled Personal Order prioritization setting blocks the browser rather than inventing website fallback recommendations.
- CI and regression tests for 5-at-a-time paging, 100,000-title Libraries, duplicates, saved-task separation, category/policy gating, 320px interactions and disabled cloud writes.

## Platform packages
- **MediaFlowApp-Android-debug.apk:** Android **debug-signed** developer build; can be manually installed with appropriate device settings. **Not** a store-signed production APK.
- **MediaFlowApp-Windows-x64.zip:** Windows x64 release-mode portable build. Extract **all** files into a folder before running MediaFlow.exe. No installer or publisher code signature.
- **MediaFlowApp-iOS-unsigned.ipa:** iOS release-mode **unsigned archive** for developer signing only. It cannot be installed on an ordinary iPhone until it is signed and provisioned with valid Apple Developer credentials; no TestFlight delivery.
- **SHA256SUMS.txt** containing hashes of the platform files.

## Safety and limitations
- Browsing does not reroll saved tasks, advance Collection traversal, record History, award XP or write Supabase data.
- Native Logging selections and draft plans remain transient and locally reviewed; **actual website task/Logging submission and synchronization are not implemented**.
- This is **not** the original website's full recommendation fallback/smart engine and is not full app parity.
- Personal MediaFlow website, MediaFlow Plus and production Supabase were not modified.
- Native application build number increments to **411**, so an installed beta build 410 can be updated without an Android version-code downgrade.
