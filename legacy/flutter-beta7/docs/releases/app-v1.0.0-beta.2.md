# MediaFlowApp v1.0.0 Beta 2 — Logging Recommends Queue Browser

**Release tag:** `app-v1.0.0-beta.2` · **Feature reference:** Personal MediaFlow **v478 Stable** (2026-10-17). This is a focused native subset, not complete website parity.

## Added
- **Browse more recommendations** in native Logging. Expand a category's Personal Order queue for up to **five additional, unselected** eligible titles beyond the current saved task.
- Each suggestion shows its exact Library title, queue rank, status and whether it originated from a Collection. Use its add icon to select it locally and open existing Logging title review.
- The saved current task remains the primary recommendation. Additional queue results are clearly labeled **previews**, not live task rerolls or the website's fallback picker.
- A selected queue title disappears from the additional list without clearing existing selections. Up to eight candidates are cached per category and snapshot, with five shown at a time.
- **Performance improvement:** Logging status options are built once per Library snapshot rather than rescanned when checkboxes are changed. Additional queue evidence is built lazily only on expansion, not every card rebuild.
- Better long-title handling and bounded mobile list presentation for 320px screens.

## Safeguards
- Invalid, unknown or duplicate IDs are excluded. An unresolved saved task is not silently replaced by a different recommendation.
- Queue browsing is unavailable when the Personal Order prioritization setting is disabled or unknown.
- No stateful recommendation reroll, task completion, Collection traversal, logging submission, History/XP change or production Supabase write is enabled.
- Regression suite tests selected IDs, duplicate IDs, policy gating, rank and 320px interaction. Native release is a **beta/developer preview**.

## Build packages
- **MediaFlowApp-Android-debug.apk:** debug-signed APK; can be installed for development, **not Play Store ready**. Hosted CI debug-signing certificates may change, so in-place upgrade from a different APK **is not guaranteed**. Avoid uninstalling if you need to retain local-only app data; consistent release keystore required for reliable upgrades.
- **MediaFlowApp-Windows-x64.zip:** complete release-mode Windows x64 application; extract the **entire** ZIP and launch MediaFlow.exe. It is not an installer and is not code-signed.
- **MediaFlowApp-iOS-unsigned.ipa:** unsigned developer archive only. **Not installable on a normal iPhone.** Valid Apple Developer signing/provisioning or TestFlight is still required.
- **SHA256SUMS.txt:** checksums of the packaged assets.

**No file is considered published until the release workflow has passed Flutter tests, Android/Windows/iOS builds, and uploaded its assets.**

## Known gaps
MediaFlow Recommends is not yet the website's full smart recommendation engine. The native app remains read-only for account-state writes and does not persist local selection/draft changes through a production logging transaction. Refer to the project parity/readiness report before relying on it as a replacement for the personal website.
