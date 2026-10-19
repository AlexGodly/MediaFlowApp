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
