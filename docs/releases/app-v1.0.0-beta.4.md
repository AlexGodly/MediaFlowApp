# MediaFlowApp v1.0.0 Beta 4 — Full MediaFlow Interactive App

**Source baseline:** MediaFlow **v504 Stable**, released 2026-10-18.
**App release tag:** `app-v1.0.0-beta.4`.
**Architecture:** Complete production MediaFlow website in a Flutter-hosted
WebView, not 100% native rewritten Flutter parity.

## Added
- Default app entry point now launches the real, interactive MediaFlow site,
  rather than a partial native Logging preview.
- The original site's Dashboard, Library, all Logging modes and
  recommendations, Personal Order, Collections, History, Statistics,
  Settings, theme engine, metadata/cover workflows and other website
  functionality are present **as delivered by the production website**.
- Original website authentication and existing live Supabase sync are used.
  No duplicate Library, History, XP or native state mutations are added.
- HTTPS trusted-origin guard, full-screen viewport, mobile back navigation,
  loading indicator, recoverable top-level loading-error screen.
- Updated to maintained Flutter InAppWebView Forge 2.1.77, Android API 24 minimum and iOS 15 minimum so current platform build tools can compile the WebView implementation.
- Legacy Flutter native development UI remains selectable with
  `MEDIAFLOW_APP_MODE=native-preview` (cloud writes remain disabled there).
- Android generated manifests gain INTERNET permission.
- New integration guidance, source guard and origin contract tests.

## Limitations and testing status
- This is a **hybrid full-site app**, not a native rewrite of every page.
- CI Flutter analysis/tests and platform build packaging still required.
- Clipboard, file downloads/uploads, share sheets, popups, deep links,
  permissions, offline PWA caching and OAuth paths require physical device
  validation. They should not be described as verified working.
- Windows needs WebView2; iOS archive is **unsigned and not installable on a
  standard iPhone**; Android debug APK isn't a signed store distribution.
- Default mode uses live site/business rules and can change production data
  after a user signs in. Always keep a backup before real-data QA.

**Artifacts, if and only if the complete CI pipeline passes:** Android
debug APK, Windows x64 ZIP, unsigned iOS developer IPA, SHA-256 checksums.
