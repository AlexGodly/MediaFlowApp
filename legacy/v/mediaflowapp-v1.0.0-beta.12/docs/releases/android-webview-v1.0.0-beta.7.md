# MediaFlowApp Android v1.0.0 Beta 7 — Offline Session Safety

**Frontend:** Pinned MediaFlow v507 Stable release.
**Android host:** Kotlin + locally bundled Android System WebView.
**Scope:** Recommendations, Log, Library workspace and Log history.
**Archive:** `legacy/v/android-webview-v1.0.0-beta.7/`.
**Previous archives:** Beta 6 restored to the exact published source snapshot and remains unchanged.

## Fixes
- Adds an early Android companion startup gate so authenticated bootstrap waits until the local companion sync/draft hooks are installed.
- Guards against a transient Supabase `SIGNED_OUT` event clearing the cached account while offline session restoration is in progress. Explicit user logout is not suppressed.
- Clears the offline-session guard after a successful online cloud read/upload so real auth events work normally after reconnection.
- Keeps the Beta 6 IndexedDB account-scoped snapshot, pending-save queue, draft autosave, reconnect merge, and sync status indicator.
- Keeps the performance improvement that avoids parsing the complete saved library just to determine whether each subsequent save has a pending queue.
- Extends packaging tests to assert the offline auth event guard is included in the exact patched v507 source.

## Expected behavior
- After a successful login, opening the app with no network should restore the same account from its locally stored Supabase session and account-scoped IndexedDB snapshot.
- Offline consumption logs and recommendation changes remain on-device with a pending-sync status.
- When connectivity returns, the app refreshes the saved session, merges queued state with the existing cloud row and uploads it.
- A missing cloud row is not automatically created or overwritten; local data remains preserved and the status indicates that sync needs attention.

## Limitations
- Offline account restoration requires a previous successful login and a locally available session/snapshot.
- Android may suspend background work. Sync is retried when the app is active, visible or connectivity returns.
- This does not establish a universal 60 FPS guarantee or replace testing on the target phone.
- No Supabase schema, policies, secrets or website source are changed.

## Release contents
- Debug-signed installable APK.
- SHA-256 checksums and source manifest.
- Version-specific source ZIP.
- Complete tracked source snapshot under `legacy/v/android-webview-v1.0.0-beta.7/`.
