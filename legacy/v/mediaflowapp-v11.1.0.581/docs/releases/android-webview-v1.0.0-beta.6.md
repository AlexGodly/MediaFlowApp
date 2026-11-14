# MediaFlowApp Android v1.0.0 Beta 6 — Focused Recommendations, Logging and Offline Sync

**Frontend:** Exact, pinned MediaFlow v507 Stable release archive.
**Android host:** Kotlin + Android System WebView using the locally packaged frontend.
**Scope:** Recommendations, Log, Library workspace, Log history.
**Archive:** `legacy/v/android-webview-v1.0.0-beta.6/`.
**Prior source snapshots:** Preserved and never overwritten.

## Focused companion surfaces
- Replaces the mobile bottom navigation with Recommend, Log, Library and History.
- Restricts desktop sidebar navigation to Recommendations, Library workspace and Log history; unrelated website pages are not exposed by the companion navigation.
- Reuses MediaFlow's existing category rotation engine, reroll/skip/end-session actions, exact-title recommendation mode, title reroll history modal, Library progress cards, logging form, XP preview, and batch logging.
- Adds an exact-title recommendation toggle directly to the Recommendations screen. The preference is the existing account setting and syncs through the existing MediaFlow state save.
- Preserves existing logging modes and XP calculations instead of approximating them in native Kotlin.
- Retains the Android-only performance profiles and system-bar/contrast fixes from Beta 5.

## Offline account and local-first saves
- Detects the previously persisted Supabase session in the WebView's local storage if session restoration fails because of a network error or the device is offline. It does not store or print the access/refresh tokens separately.
- Uses account-ID-scoped IndexedDB snapshots as the primary Android offline cache, with the existing MediaFlow account recovery cache as a fallback. IndexedDB stores a serialized full-state snapshot, reducing synchronous multi-megabyte localStorage writes.
- Queues full-state writes locally when offline or when a network/upload attempt fails. The core cloud payload remains the existing `mediaflow_states` row format; no database migration or service-role credential was added.
- Autosaves and restores single-log drafts, batch-log drafts, entry details, logging mode and selected companion screen. Drafts are scoped by the current Supabase user ID.
- On reconnect, validates/refreshes the stored session, fetches the existing cloud row, merges offline changes with cloud state, uploads, and refreshes the live UI. It deliberately refuses to auto-create a missing cloud row when pending local data exists.
- Displays an always-readable, tappable sync-status pill. Retry is automatic on reconnect and while pending data is waiting; the pill also triggers a manual retry.
- CI verifies the offline session patch markers, companion asset packaging, JavaScript syntax, and release archive contract.

## Performance and safety
- Reuses Beta 5's mobile DOM/layout optimizations, reduced effects profiles, local page-size cap in Ultra light, and Android 15+ safe insets.
- Supabase, authentication configuration, website repository and backend schema are unchanged.
- Offline logging is locally saved, not server-confirmed until the status shows synced. If the cloud record is missing or auth must be renewed, the app keeps the local copy and surfaces a sync-attention status instead of silently overwriting remote state.
- Android may suspend background work; queued data retries when the app is active/visible and connectivity returns. Large libraries still require device-level storage and performance tests.
- No claim of verified 60 FPS on every low-end phone is made.

## Release contents
- Installable debug-signed APK.
- SHA-256 checksums and pinned v507 source manifest.
- Complete versioned source ZIP.
- Complete tracked source snapshot under `legacy/v/android-webview-v1.0.0-beta.6/`.
