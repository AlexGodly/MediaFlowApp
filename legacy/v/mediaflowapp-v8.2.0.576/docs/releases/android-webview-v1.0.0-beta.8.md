# MediaFlowApp Android v1.0.0 Beta 8 — Focused Companion with Backup Controls

**Frontend:** Pinned MediaFlow v507 Stable release.
**Android host:** Kotlin + locally bundled Android System WebView.
**Scope:** Recommendations, Log, Library workspace and Log history.
**Archive:** `legacy/v/android-webview-v1.0.0-beta.8/`.
**Previous archives:** Beta 6 and Beta 7 remain unchanged.

## Mobile companion features
- Reuses the original MediaFlow recommendation engine, category rerolls, exact-title recommendation mode, title reroll history, Quick/Advanced/Progress logging, batch logging and XP preview.
- Four primary mobile surfaces: Recommend, Log, Library and History.
- Keeps the account-scoped IndexedDB cache, offline draft persistence, queued Supabase sync, offline session restoration guard and low-end performance profiles.

## Restored automatic backup access
- Adds a compact **Automatic backups** panel to the Library workspace, without reopening the full website Settings page.
- **Choose backup folder** invokes the existing Android native folder picker and persists access using the Android backup bridge.
- **Back up now** invokes the existing full JSON backup routine. If no folder is selected, the native picker can be opened from the action.
- **Automatic backups: On/Off** updates MediaFlow's existing account setting and restarts the existing backup timer.
- The backup implementation uses the original MediaFlow backup format and Android bridge, not a second backup format.

## Offline and synchronization
- Restores the last locally persisted Supabase account after a successful prior login.
- Stores full state snapshots in account-scoped IndexedDB, saves single/batch logging drafts locally, and queues offline log/recommendation state changes.
- On reconnect, merges queued local state with the existing cloud row and uploads it. Missing cloud state is never silently overwritten.
- Unsaved form drafts remain on the same device; completed offline logs and state changes sync when connectivity returns and the app is active.

## Release verification and limitations
- Unit/packaging tests, source archive byte-for-byte verification, JavaScript syntax checks and Android APK build run in GitHub Actions before release.
- Beta 6 and Beta 7 source snapshots remain preserved under `legacy/v/`.
- No Supabase schema, credentials or website source changes.
- Real-device verification is still required for Android folder permission behavior, offline sync, and actual low-end-phone scrolling. No universal 60 FPS claim is made.

## Release contents
- Installable debug-signed APK.
- SHA-256 checksums and pinned-source manifest.
- Complete source ZIP and source archive under `legacy/v/android-webview-v1.0.0-beta.8/`.
