# MediaFlowApp 1.0.0 Beta 11 — full MediaFlow v554, working logging, Android + Windows + iOS

**Frontend:** official MediaFlow **v554** Stable archive, pinned by SHA-256 (previously v553).
**Platforms:** Android APK, Windows installer + portable app, iOS app (unsigned IPA).
**Supabase:** existing authenticated `public.mediaflow_states` row only. No schema, table, policy or key changes.

## Logging works

Beta 10's app layer never actually ran. The MediaFlow website keeps all of its code in one private scope, and Beta 10 loaded its companion as a separate script, so it stopped on its first line at every launch. The Log / Batch / Library / History buttons it drew also called `window.MFAndroidCompanion`, which was never defined, so they did nothing.

Beta 11 injects the app layer inside the website's own scope at packaging time (the build fails closed if that structure ever changes) and defines the handler name. Logging now works the same way it does on the website:

1. Tap the **+** quick-actions button → **Add to Logging**.
2. The app jumps to the logging form and opens the **Browse Library** section (it starts collapsed on phones, which hid the title box).
3. Pick a Library title, or switch to **Quick logging** and type any title, enter the progress you reached, tap **Add**, then **Save & get next task**.

Verified end to end in headless Chrome (phone size) and inside the desktop app shell, against a simulated Supabase account: the log is saved, written to the cloud row with a compare-and-swap update, appears in History, survives a reload, and a log made **offline** is queued on the device and uploaded on reconnect.

## Every website feature

The app no longer hides MediaFlow's pages. Dashboard, Library, Collections, Personal Order, History, Statistics, Account, Settings, About and Old System are all available with the website's own navigation, plus everything inside them (recommendations, rerolls, XP, Logging Workspace, recovery tools, imports/exports, backups). Backups use Settings as on the website; on Android the folder picker is still the native Storage Access Framework.

A logging draft saved by Beta 10's batch form still reopens inside the Dashboard so nothing is lost. (The website itself retired the separate Batch page in v394 in favour of multi-title logging in the Logging Workspace.)

## Much smaller download

The website release archive carries ~150 retired script bundles (~580 MB). Beta 11 copies only the scripts `index.html` and the service worker load. The packaged app content drops from ~600 MB to ~12 MB (Beta 10's APK was 198 MB).

## New: Windows and iOS

- **Windows** (`…-Windows-x64-Setup.exe` installer, or `…-portable.exe` with no install): an Electron window serving the same packaged files from a private secure origin. Links that leave MediaFlow open in your browser. Not code-signed, so Windows SmartScreen will warn on first run (More info → Run anyway).
- **iOS** (`…-iOS-unsigned.ipa`): a native WKWebView app with native alert/confirm/prompt dialogs, Safari for external links, and exports through the iOS save sheet. It is **not signed**: install it with a sideloading tool that re-signs with your Apple ID (AltStore, Sideloadly) or sign it with an Apple Developer account. iPhone and iPad, iOS 16.4+.

## Still to check on real devices

- Android, Windows and iOS binaries are built by GitHub Actions; the logging/offline/reload flow was exercised in Chrome and the desktop shell, not yet on a physical phone or on iOS WebKit.
- Android APK is debug-signed; Windows and iOS builds are unsigned. None is store-ready.
- Background sync runs while the app is open; it is not a background service.
