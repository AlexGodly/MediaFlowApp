# MediaFlow by Alex Godly — Android, Windows and iOS apps

The **real MediaFlow website** (pinned official release, currently **v554**) packaged as installable apps. The same packaged files run in all three shells, so every website feature is available: Dashboard, Library, Collections, Personal Order, History, Statistics, Account, Settings, About, logging, recommendations, XP, recovery tools, imports/exports and backups.

| Platform | Shell | Release file |
| :-- | :-- | :-- |
| Android 10+ | Kotlin + System WebView (`app/`) | `MediaFlow-<version>-Android.apk` (debug-signed) |
| Windows 10/11 x64 | Electron (`desktop/`) | `…-Windows-x64-Setup.exe` or `…-Windows-x64-portable.exe` (unsigned) |
| iPhone / iPad, iOS 16.4+ | Swift + WKWebView (`ios/`) | `…-iOS-unsigned.ipa` (re-sign to install) |

Download from [Releases](https://github.com/AlexGodly/MediaFlowApp/releases). Latest: **1.0.0 Beta 11** — [release notes](docs/releases/mediaflowapp-v1.0.0-beta.11.md).

## Logging a title

Tap the **+** quick-actions button → **Add to Logging**. The app scrolls to the Logging Workspace and opens **Browse Library**: pick a Library title, or choose **Quick logging** and type any title, enter the progress reached, tap **Add**, then **Save & get next task**. Logs save to your account immediately, or queue on the device while offline and upload when you reconnect.

## How it works

- `tool/package_mediaflow.py` takes the pinned website archive (CI downloads it), verifies its SHA-256, copies only the files `index.html` and the service worker load (the archive also holds ~580 MB of retired bundles), vendors React/ReactDOM/Supabase locally, applies small fail-closed patches, and **injects the app layer (`tool/android_assets/companion-mode.js`) inside the website's private script scope**.
- The app layer adds: account-scoped IndexedDB snapshots, an offline queue, compare-and-swap cloud writes against `mediaflow_states.updated_at`, three-way merge with an in-app conflict dialog, logging-draft autosave/sync, and the jump-to-logging behaviour above. It hides nothing from the website.
- Android extras: native folder picker for automatic backups, chunked exports to Downloads, Back-button handling, performance presets (Settings).
- Windows serves the files from a private `mediaflow://app` secure origin; iOS does the same with a `WKURLSchemeHandler` and adds native dialogs, Safari for external links and the iOS save sheet for exports.
- No Supabase schema, table, policy or key changes; the apps use the website's existing authenticated row.

## Build and test

CI (`.github/workflows/release.yml`) does everything on every push to `main`: unit tests → package website → end-to-end logging test in phone-sized Chrome and in the desktop shell (fake Supabase) → Android, Windows and iOS builds in parallel → one GitHub prerelease with all files and SHA-256 sums. Pull requests run `pr-validation.yml`.

Locally:

```sh
mkdir -p .downloads
curl -fL https://github.com/AlexGodly/MediaFlow/releases/download/554/MediaFlow_v554_Stable.zip -o .downloads/MediaFlow_v554_Stable.zip
python3 tool/package_mediaflow.py                 # → app/src/main/assets/www
python3 -m unittest discover -s tests && python3 tests/release_guard.py
python3 tests/e2e/smoke.py app/src/main/assets/www   # needs: pip install playwright
python3 -m pip install pillow && python3 tool/build_icons.py
gradle :app:assembleDebug                          # Android (Java 17, SDK 35, Gradle 8.10.2)
# Windows: copy the www folder to desktop/www, then in desktop/: npm install && npm run dist:win
# iOS (macOS): copy www to ios/www, then in ios/: xcodegen generate && open MediaFlow.xcodeproj
```

To move to a newer website release, change `VERSION` and `ARCHIVE_SHA256` in `tool/package_mediaflow.py` and `MEDIAFLOW_VERSION` in both workflows; the build refuses to package if any patched function changed shape.

## Scope and limitations

- Binaries are built by GitHub Actions. The logging, offline-queue and reload flow is tested automatically in Chrome and in the desktop shell; physical-device testing on Android and iOS WebKit is still needed.
- The APK is debug-signed; the Windows and iOS builds are unsigned. Windows SmartScreen warns on first run; the IPA must be re-signed (AltStore, Sideloadly or an Apple Developer account) to install. None of the builds is store-ready.
- Sync runs while the app is open; it is not a background service. Some providers and cloud features need internet.
- Website updates reach the apps only through a new app release that pins the newer website version.

# Release history

## Android folder auto-backup (Beta 3)

MediaFlow v553's browser-only `showDirectoryPicker()` is not supported by Android WebView. This release patches only the packaged Android copy of the v553 backup functions: **Choose backup folder** uses Android's Storage Access Framework picker, retains the permitted folder across app restarts, and streams the website's real Full Backup JSON to that location. The existing **Back up now**, **Single file** and **Multiple files** options continue using the v553 settings. The app must be running for timed automatic backups; if reopened after an elapsed interval, a catch-up save may occur after MediaFlow becomes active. Android does **not** schedule background cloud exports when the app is terminated. If a storage provider cannot safely replace a single-file backup, the app reports an error rather than deleting an existing backup.

This is an Android beta: compilation and source-level tests are automated, but provider-specific folder operations, device FPS, logins and every v553 feature require real-device testing.


## Mandatory GitHub release + legacy archive policy (Beta 4 onward; all platforms from Beta 11)

Every commit updating `main` must bump the app version (Android `versionName`/`versionCode`, `desktop/package.json`, iOS `CURRENT_PROJECT_VERSION`) and update the release notes and GitHub workflow to a **new, unique tag**. The exact complete tracked source (excluding the shared `legacy/` directory to prevent nested copies) must be mirrored into `legacy/v/<release-tag>/`. Previous versions must remain intact. The earlier Flutter application stays under `legacy/flutter-beta7/`.

CI now compares the archive byte-for-byte against the release source **before** packaging and publishing. For every passing release, upload the Android APK, the Windows installer and portable app, the iOS IPA, full version-specific source ZIP, SHA-256 checksums, source manifest and detailed release notes to GitHub Releases. No successful APK build should remain only as a workflow artifact. If a release cannot be built or published, it is not a released version. Updating source without a new archive and tag fails the release checks.

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
