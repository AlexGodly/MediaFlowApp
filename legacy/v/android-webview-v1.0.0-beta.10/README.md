# MediaFlow by Alex Godly — Android

**New Android project:** Kotlin + Android WebView with **the real MediaFlow v553 frontend packaged inside the APK**, not an imitation of its UI. The older Flutter native project and its workflows are preserved in [`legacy/flutter-beta7/`](legacy/flutter-beta7/).

## Current Android update: Beta 10 · MediaFlow v553

Beta 10 keeps the four focused surfaces (Recommendations, Log, Library workspace, Log history) and hardens offline account continuity. Logging drafts are saved locally and synchronized through the existing account state; completed offline logs queue until reconnect. Cloud writes use updated_at compare-and-swap, independent changes are merged, and overlapping settings/task changes prompt an in-app choice instead of being silently overwritten.

[Beta 10 release notes](docs/releases/android-webview-v1.0.0-beta.10.md). **No Supabase schema changes:** the earlier app-specific draft table remains deleted. Beta 10 uses only the existing mediaflow_states row and its current authenticated access policies.

## Features and architecture

- Uses the exact pinned **v553 Stable** web release archive, SHA-256 verified at build time.
- Bundles the HTML, CSS, media and compiled application JavaScript in the Android APK. Supabase, React and ReactDOM CDN scripts are copied into the APK during CI, avoiding a network-dependent initial interface load.
- Renders on Android's hardware-accelerated System WebView, with local HTTPS-like origin provided by `WebViewAssetLoader`. No `file://` privilege bypass or broad cleartext networking.
- Runs the real v553 recommendation, title-reroll/history, Library, Quick/Advanced/Progress logging, XP preview and batch logging logic. The Android companion exposes only Recommendations, Log, Library workspace and Log history.
- Works with on-device file imports, external links in the browser, network downloads, and **chunked** local MediaFlow blob exports to Android Downloads (up to 750 MB of output without constructing a single Base64 copy of the backup in Kotlin).
- Adds an Android-only **Original / Balanced / Smooth / Ultra light** performance profile. The focused companion hides unrelated website navigation and avoids rebuilding desktop-only UI on phones.
- Android Back closes MediaFlow's native-state modal first, then navigates back to Dashboard rather than accidentally exiting a single-page app.
- Intercepts service-worker asset requests from the same pinned local frontend, and recovers from Android WebView renderer restarts without deleting account storage.
- Uses the existing MediaFlow launcher artwork and package ID `com.alexgodly.mediaflow`.

## Build

Requires Java 17, Android SDK 35 and Gradle 8.10.2 (CI provisions these).

```sh
curl -fL --retry 3 \
  https://github.com/AlexGodly/MediaFlow/releases/download/553/MediaFlow_v553_Stable.zip \
  -o .downloads/MediaFlow_v553_Stable.zip
python3 tool/package_mediaflow.py
python3 -m pip install pillow
python3 tool/build_icons.py
gradle :app:assembleDebug
```

The verification script refuses archives whose SHA-256 differs from v553's official release and detects missing local CSS/JS references. APK: `app/build/outputs/apk/debug/app-debug.apk`. The GitHub Actions workflow publishes versioned prerelease APKs only if tests, packaging and compilation pass.

## Scope and limitations

**This is an Android beta, not a verified mobile performance fix.** Loading local files improves startup independence but does not inherently solve large-library DOM rendering, cover decoding, or theme effects. Measure actual frame rate/memory on a phone before calling scrolling optimized. 100% real-world feature compatibility (particularly OAuth redirects, file exporters over ~100MB, provider restrictions and background sync) still needs Android device testing. Some providers and cloud operations still require internet. Frontend changes require bundling a new website release into an updated APK.

The original website is completely unchanged. Beta 10 makes authenticated writes to the existing mediaflow_states row using an updated_at compare-and-swap check and the current RLS policies. It creates no tables, changes no policies, and introduces no service-role key. The previous mediaflow_native_logging_drafts table was removed and is not used.

The generated APK is **debug-signed** for installation/testing and may conflict with the signature of an earlier separately built APK. Do not call it production-signed or Play Store ready.

## Android folder auto-backup (Beta 3)

MediaFlow v553's browser-only `showDirectoryPicker()` is not supported by Android WebView. This release patches only the packaged Android copy of the v553 backup functions: **Choose backup folder** uses Android's Storage Access Framework picker, retains the permitted folder across app restarts, and streams the website's real Full Backup JSON to that location. The existing **Back up now**, **Single file** and **Multiple files** options continue using the v553 settings. The app must be running for timed automatic backups; if reopened after an elapsed interval, a catch-up save may occur after MediaFlow becomes active. Android does **not** schedule background cloud exports when the app is terminated. If a storage provider cannot safely replace a single-file backup, the app reports an error rather than deleting an existing backup.

This is an Android beta: compilation and source-level tests are automated, but provider-specific folder operations, device FPS, logins and every v553 feature require real-device testing.


## Mandatory GitHub release + legacy archive policy (Beta 4 onward)

Every commit updating `main` must bump the Android application version and update the release notes and GitHub workflow to a **new, unique tag**. The exact complete tracked source (excluding the shared `legacy/` directory to prevent nested copies) must be mirrored into `legacy/v/<release-tag>/`. Previous versions must remain intact. The earlier Flutter application stays under `legacy/flutter-beta7/`.

CI now compares the archive byte-for-byte against the release source **before** packaging and publishing. For every passing release, upload the installable Android APK, full version-specific source ZIP, SHA-256 checksums, source manifest and detailed release notes to GitHub Releases. No successful APK build should remain only as a workflow artifact. If a release cannot be built or published, it is not a released version. Updating source without a new archive and tag fails the release checks.

Beta 3 and Beta 4 archives are tracked under `legacy/v/`. Beta 4 is a release-discipline update; it does not claim that the Android app is fully feature-verified or that scrolling problems have been measured and resolved.


## Beta 5 Android phone-first optimization

- Android 15+ system-bar safe insets and improved mobile tab/label readability.
- Reuses unchanged mobile navigation HTML instead of replacing tabbar buttons on every unrelated rerender.
- Avoids desktop sidebar layout work on phones.
- Four local-only performance presets: Original, Balanced, Smooth, Ultra light. Auto-selects Ultra light on phones with four or fewer CPU threads or at most 3 GiB reported RAM; Smooth otherwise.
- Ultra light temporarily caps Library page rendering at 48 entries, skips offscreen row painting, and cuts visual effects without changing saved Library/cloud preferences.
- Provides Android-only long task counters in Settings; benchmarking requires a real device. No guaranteed FPS.


## Beta 6: focused mobile companion + offline-first workflow

The Android app is now intentionally scoped to four surfaces: **Recommendations**, **Log**, **Library workspace**, and **Log history**. It reuses the actual MediaFlow v507 functions rather than reimplementing its recommender or XP calculations. Exact-title recommendations can be toggled in the Recommendations screen; title rerolls and reroll history use the original MediaFlow logic. Single-title logging preserves the existing Quick/Advanced modes, per-unit/progress methods and XP preview. Batch Log remains available.

### Offline behavior

- Supabase's existing persisted session stays in the Android WebView's app-local storage. If the phone is offline, the app can restore the locally stored account identity and the matching account-scoped local snapshot instead of forcing a new login.
- Full state snapshots are stored in **IndexedDB**, keyed by the signed-in Supabase user ID. This avoids writing a multi-megabyte library to localStorage on every save. The existing local recovery cache remains a fallback.
- Drafts for single-title and batch logging, the selected companion screen, and the open logging mode are autosaved locally.
- When offline, log submissions and recommendation changes are stored locally and marked pending. Once online, the app refreshes the saved session, merges queued state with the existing cloud state, and uploads using MediaFlow's existing `mediaflow_states` record. A missing cloud row is **not** auto-created or overwritten; the local copy remains available and the status button reports that sync needs attention.
- A tappable status pill shows offline, pending, syncing, or synced state. No Supabase schema or backend policies are changed.

This implementation does not guarantee that every phone will hold a huge library within available device storage or that all background sync will run while Android has suspended the app. Pending changes sync when the app is active and connectivity is restored. Real-device tests are still required for offline sign-in, conflict handling and long-session logging.


## Beta 7 offline-session reliability fix

Beta 7 protects the cached account during offline restoration from a transient Supabase `SIGNED_OUT` event. An early startup gate ensures the offline queue, draft restoration and account-scoped snapshot loader are installed before the authenticated app bootstrap proceeds. The guard is cleared after successful cloud communication, so normal sign-out handling resumes. Beta 6's published source archive is preserved byte-for-byte under `legacy/v/android-webview-v1.0.0-beta.6/`.


## Beta 8 backup access in the focused companion

The Library workspace now exposes a compact Automatic backups panel with Choose backup folder, Back up now, and an On/Off toggle. It calls MediaFlow's existing Android folder-picker bridge and JSON backup routine, so the focused app no longer hides the backup feature when the full Settings page is omitted.

## Beta 9 — MediaFlow v553 companion

The Android companion now pins the official MediaFlow v553 Stable release archive and verifies its SHA-256 before packaging. It inherits v553's reroll-title XP calculation and unified XP preview instead of bundling the older v507 frontend.

The focused mobile surfaces are Recommend, Log, Library workspace and History. The app delegates category rotation, title rerolls/history, all original single/batch logging modes, progress methods, XP calculations and successful-log awards to the v553 application logic. It uses the same authenticated mediaflow_states cloud row and does not require a Supabase schema change.

After a successful login, account-scoped IndexedDB snapshots and single/batch drafts are kept locally. If the phone is offline, the app can reopen the last locally cached account and keep drafts and logs queued on-device. When connectivity returns, it refreshes the saved Supabase session and merges queued state with the existing cloud state before upload. It never stores access/refresh tokens separately or bypasses Supabase authentication. A session that has genuinely expired may still require reauthentication before cloud sync; local drafts remain available.

Build checks require v553 recommendation, title-history, logging, unified XP-preview, reroll-unit reward and cloud save/read entry points to exist in the pinned source before an APK can be built. Real-device offline/reconnect tests remain necessary; a passing APK build alone is not proof of every network condition.


## Beta 10 — offline account continuity and conflict-safe sync

- Uses the previously saved Supabase identity and account-scoped local snapshot to reopen the same workspace when offline, without forcing sign-in solely because the network is unavailable.
- Autosaves unfinished single and batch Logging forms, syncs draft snapshots through the namespaced `__mfAndroidCompanionDraftV1` field in the existing cloud JSON state, and queues completed offline logs until reconnection.
- Uses compare-and-swap updates against the existing `updated_at` value instead of Android's unconditional UPSERT. If a cloud write races with another save, it retries against a fresh row or keeps the local copy queued.
- Merges independent account changes and surfaces overlapping settings/task changes in a designed conflict dialog. Draft conflicts offer explicit phone-vs-cloud choices.
- Persists a compact last-known cloud baseline so offline changes can be compared with the prior shared version after an app restart.
- Adds executable tests for stale revision rejection, account fencing, insert-if-absent behavior, and the release packaging contract.

No Supabase table or policy changes are part of Beta 10. A genuinely expired/revoked session can still require reauthentication once online, and Android background sync runs while the app is active rather than as a guaranteed background service. Airplane-mode and reconnect scenarios must still be exercised on a physical device.
