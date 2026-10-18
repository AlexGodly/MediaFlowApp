# MediaFlowApp — complete interactive application baseline

## Decision and source

- Authoritative product: [AlexGodly/MediaFlow](https://github.com/AlexGodly/MediaFlow).
- Verified source release when implementation began: **504 Stable**, Oct 18 2026.
- Latest production entry: https://alexgodly.github.io/MediaFlow/
- Existing Flutter native subset: kept intact under `native-preview` mode.
- Default: live-origin embedded browser on Android (Android System WebView),
  iPhone (WKWebView), and Windows (Edge WebView2).

## What the prototype includes

Because the *real MediaFlow application* runs inside the app rather than a
copy of its UI, product areas are driven by MediaFlow itself: Dashboard;
normal/dynamic Library; title details, metadata and covers; Quick/Advanced
Logging and recommendations; History; Statistics; Collections; Personal
Order; settings, imports/exports, dynamic themes, background workflows and
account backup/sync. This is full functional **website coverage**, not
Flutter-native feature implementation or independent WebView QA approval.

## Data model and authentication

- WebView profile's site cookies/localStorage/IndexedDB/service worker are
  distinct from the browser's and from Flutter's native read-only session.
- User logs into existing MediaFlow website inside app as needed.
- Cloud mutations, XP and History originate from original MediaFlow JS.
- **No new Supabase migrations, RPCs, native production mutations or data
  copies.** The previous native CAS gates remain disabled.
- The deployed website automatically receives future MediaFlow releases.

## Device acceptance matrix (must be tested on physical devices)

1. Sign in, restart app, verify session persistence.
2. Navigate every tab and modal; verify responsive tight mobile widths.
3. Library > title details > create/edit/delete with a backed-up test account.
4. Logging > recommendation > Quick and Advanced > confirm History/XP once.
5. Personal Order and Collection reorderings persist across restart.
6. Import/export files and full backups, download and file chooser.
7. Recovery provider requests, progress UI, and safe task cancellation.
8. Dynamic themes, service worker/reload, back navigation, app resume.
9. Keyboard, clipboard, file URLs and notification permissions.
10. Windows WebView2 runtime, iPhone signing, Android permission/network.

Live-account data mutations are not automated in CI. Test with backups.
Offline availability, OAuth popups and upload/download flows are currently
**unverified** and may need platform channel integration. The native subset
is still incomplete. Release status must be stated accordingly.

## Developer entry points

Run `flutter create --project-name mediaflow_app --org com.alexgodly
--platforms=android,ios,windows .`, then `flutter pub get`. On Android
also run `python3 tool/platform/configure_webview_android.py` after
generating the Android project, then `flutter run`. Native-preview only:
`flutter run --dart-define=MEDIAFLOW_APP_MODE=native-preview`.

Production URL is locked to the personal MediaFlow HTTPS origin. A
misconfigured `MEDIAFLOW_SITE_URL` falls back to that trusted URL.

## Platform package compatibility

Flutter InAppWebView Forge 2.1.77 replaces the old InAppWebView package, whose bundled Android Gradle script uses a ProGuard default disallowed by modern AGP. The Forge Android package uses the optimized ProGuard default. Android minimum API is 24 and iOS deployment target is 15. The generated templates are patched by `tool/platform/configure_webview_android.py` and `tool/platform/configure_webview_ios.py` respectively. Device validation remains required.

## Windows compatibility note

Forge 2.1.77 currently publishes a Windows CMake plugin target name that differs from the name expected by Flutter's generated registrant on the October 2026 runner. The Windows build runs an idempotent source-checked compatibility patch in `tool/platform/configure_webview_windows.py` before CMake configuration. This modifies only the runner's local downloaded plugin package, never the MediaFlow website or cloud account.
