# MediaFlowApp Android v1.0.0 Beta 9 — MediaFlow v553 Companion

**Frontend:** Official MediaFlow v553 Stable release archive, pinned by SHA-256.
**Android host:** Kotlin + locally bundled Android System WebView.
**Mobile scope:** Recommend, Log, Library workspace and Log history.
**Archive:** legacy/v/android-webview-v1.0.0-beta.9/.
**Previous archives:** Beta 6, Beta 7 and Beta 8 remain unchanged.

## Correct source version and feature parity
- Replaces the outdated v507 frontend with the exact v553 Stable release, including all official HTML, CSS, JavaScript, images, icons, service worker and runtime dependencies.
- Preserves the current v553 recommendation engine and category rotation, recommendation rerolls, exact-title recommendations, title reroll history and the Library Workspace.
- Uses v553's original single and batch logging implementations, Quick/Advanced/Progress modes, available progress methods, and the canonical XP preview rather than duplicating XP calculations in Android.
- Includes v553's new amount-scaled XP for consumed reroll titles, including configured per-unit XP, category rotation and day-streak rounding. The v553 code only credits the bonus after a successful log submission.
- Adds build-time contract checks that fail if the pinned v553 bundle is missing recommendation rendering, title reroll history, single/batch logging, the unified XP projection, the v553 reroll-unit reward calculator, cloud read/write and local recovery-cache entry points.

## Offline account and sync
- Reuses the account's existing Supabase authentication and mediaflow_states row; no new Supabase schema, service-role key or alternate cloud data model.
- Keeps full account-scoped state snapshots in IndexedDB, with localStorage recovery-cache fallback if IndexedDB fails.
- Autosaves single and batch logging drafts locally, including draft form values, and preserves completed offline changes in a pending-sync queue.
- On offline startup after a successful previous login, restores the locally cached account identity and account-scoped state so browsing and drafting do not require a network connection.
- When online, attempts to refresh the existing Supabase session, merges pending local state with the existing cloud state, then uploads through the authenticated client.
- Does not overwrite an absent cloud row when local data is pending. If authentication genuinely expires, cloud sync waits for reauthentication while local drafts remain on the phone.
- Shows an on-device sync status control with retry and reconnect behavior.

## Phone UX, performance and backup
- Keeps the Android-only Original / Balanced / Smooth / Ultra light profiles, improved mobile text contrast and Android 15+ system-bar insets.
- Reuses mobile navigation DOM across unchanged renders and skips desktop sidebar sizing on phone-width layouts.
- Keeps the native folder picker, persisted Android folder permission and canonical MediaFlow full JSON backup routine.

## Release verification
- Python package tests and v553 feature-contract checks.
- Archive SHA-256 pin check and local-asset reference verification.
- JavaScript syntax checks for the patched v553 bundle, companion, backup bridge and performance scripts.
- Complete Android source snapshot under legacy/v/, byte-for-byte checked against tracked source.
- Installable debug-signed APK, source ZIP, source manifest and SHA-256 checksums.

## Important validation note
This is a v553-based Android beta, not a claim that every offline/reconnect case has been tested on a physical phone. The build verifies the correct source and static contracts, but actual airplane-mode startup, draft restoration, successful online submission and Supabase synchronization should still be verified on-device. No universal 60 FPS guarantee is made.
