# MediaFlowApp Android v1.0.0 Beta 4 — Release Archive Protection

**Website source:** MediaFlow v507 Stable, pinned to its verified release ZIP.
**Android runtime:** Kotlin + locally bundled Android WebView.

## Release and archival policy now enforced by CI

- Archived the full tracked source of the previous **Beta 3** version at `legacy/v/android-webview-v1.0.0-beta.3/`.
- Archived this new **Beta 4** release at `legacy/v/android-webview-v1.0.0-beta.4/`, including complete code, scripts, tests, CI workflows, documents and manifests.
- Preserved the older Flutter project at `legacy/flutter-beta7/`.
- Added `tool/verify_release_archive.py`: compares byte-for-byte every tracked source file against its release archive. A missing, extra, or changed file prevents APK publication.
- Generalized the release guard so every version requires matching Android versionCode/versionName, source archive, unique tag, APK and release notes.
- Release workflow triggers on every push to `main`, with no path filter. A change that does not increment its release version and archive is rejected instead of being silently released with an old tag.
- Adds the archived source ZIP to the GitHub Release alongside the debug-signed Android APK, SHA-256 checksums and pinned v507 source manifest.

## Functionality

The Android frontend and backup implementation from Beta 3 are retained **unchanged**. This release is specifically for enforcing versioned release and archive discipline.

## Limitations

This does not establish 100% Android parity or prove that the WebView is smooth on a particular phone. Real-device benchmarks and backup-provider validation remain necessary. No Supabase database, policies, secrets or MediaFlow website source have been changed.
