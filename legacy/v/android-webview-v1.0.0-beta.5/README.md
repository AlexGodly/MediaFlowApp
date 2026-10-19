# MediaFlow by Alex Godly — Android

**New Android project:** Kotlin + Android WebView with **the real MediaFlow v507 frontend packaged inside the APK**, not an imitation of its UI. The older Flutter native project and its workflows are preserved in [`legacy/flutter-beta7/`](legacy/flutter-beta7/).

## Features and architecture

- Uses the exact pinned **v507 Stable** web release archive, SHA-256 verified at build time.
- Bundles the HTML, CSS, media and compiled application JavaScript in the Android APK. Supabase, React and ReactDOM CDN scripts are copied into the APK during CI, avoiding a network-dependent initial interface load.
- Renders on Android's hardware-accelerated System WebView, with local HTTPS-like origin provided by `WebViewAssetLoader`. No `file://` privilege bypass or broad cleartext networking.
- Runs MediaFlow's **existing authenticated cloud logic and logging code**, not the old Flutter beta's read-only repository. This does **not** modify Supabase or claim new native data sync semantics.
- Works with on-device file imports, external links in the browser, network downloads, and **chunked** local MediaFlow blob exports to Android Downloads (up to 750 MB of output without constructing a single Base64 copy of the backup in Kotlin).
- Provides a new Android-only **Performance** card at the top of MediaFlow Settings: Original, Balanced (default), Smooth. Phone rendering settings are not synced to your account.
- Android Back closes MediaFlow's native-state modal first, then navigates back to Dashboard rather than accidentally exiting a single-page app.
- Intercepts service-worker asset requests from the same pinned local frontend, and recovers from Android WebView renderer restarts without deleting account storage.
- Uses the existing MediaFlow launcher artwork and package ID `com.alexgodly.mediaflow`.

## Build

Requires Java 17, Android SDK 35 and Gradle 8.10.2 (CI provisions these).

```sh
curl -fL --retry 3 \
  https://github.com/AlexGodly/MediaFlow/releases/download/507/MediaFlow_v507_Stable.zip \
  -o .downloads/MediaFlow_v507_Stable.zip
python3 tool/package_mediaflow.py
python3 -m pip install pillow
python3 tool/build_icons.py
gradle :app:assembleDebug
```

The verification script refuses archives whose SHA-256 differs from v507's official release and detects missing local CSS/JS references. APK: `app/build/outputs/apk/debug/app-debug.apk`. The GitHub Actions workflow publishes versioned prerelease APKs only if tests, packaging and compilation pass.

## Scope and limitations

**This is an Android beta, not a verified mobile performance fix.** Loading local files improves startup independence but does not inherently solve large-library DOM rendering, cover decoding, or theme effects. Measure actual frame rate/memory on a phone before calling scrolling optimized. 100% real-world feature compatibility (particularly OAuth redirects, file exporters over ~100MB, provider restrictions and background sync) still needs Android device testing. Some providers and cloud operations still require internet. Frontend changes require bundling a new website release into an updated APK.

The original website is completely unchanged. Supabase secrets, project configuration, database and policies are not touched. Cloud writes, when made through the site logic, remain subject to its existing authenticated guardrails.

The generated APK is **debug-signed** for installation/testing and may conflict with the signature of an earlier separately built APK. Do not call it production-signed or Play Store ready.

## Android folder auto-backup (Beta 3)

MediaFlow v507's browser-only `showDirectoryPicker()` is not supported by Android WebView. This release patches only the packaged Android copy of the v507 backup functions: **Choose backup folder** uses Android's Storage Access Framework picker, retains the permitted folder across app restarts, and streams the website's real Full Backup JSON to that location. The existing **Back up now**, **Single file** and **Multiple files** options continue using the v507 settings. The app must be running for timed automatic backups; if reopened after an elapsed interval, a catch-up save may occur after MediaFlow becomes active. Android does **not** schedule background cloud exports when the app is terminated. If a storage provider cannot safely replace a single-file backup, the app reports an error rather than deleting an existing backup.

This is an Android beta: compilation and source-level tests are automated, but provider-specific folder operations, device FPS, logins and every v507 feature require real-device testing.


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
