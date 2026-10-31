# MediaFlowApp Android v1.0.0 Beta 3 — Real Folder Backups

MediaFlow website source: **v507 Stable**, hash-verified and locally bundled.
Previous Flutter project: **legacy/flutter-beta7/** (intact).

## Actual Android auto-backup folder support
- Implements native Android Storage Access Framework folder selection instead of unsupported `showDirectoryPicker()`.
- Keeps folder permissions via `takePersistableUriPermission` so the selected folder remains usable after app restarts.
- Patches only the v507 Android-packaged frontend's three existing backup entry points, preserving the actual MediaFlow full-backup builder and canonical backup settings.
- Writes JSON into the chosen folder in bounded UTF-8/base64 chunks, with explicit acknowledgements and end-to-end byte count verification.
- Uses temporary file staging and attempts safe replacement for single-file backups. A failed write does not silently claim that the backup succeeded.
- Keeps existing multi-file/timestamped and single-file naming semantics when provider rename is available.
- Automatic backups run **while MediaFlow is open**, just as the website's current timer does; a missed interval can run once after returning to the app. Background backups while the app is killed are **not supported**.
- File selection cancellation and revoked permissions have visible error paths; no artificial success message.

## Safety and performance
- Retains the beta 2 client performance presets and chunked browser exports.
- Adds native, scoped, main-frame-only backup message handling. No exposed global `addJavascriptInterface`, no database schema or Supabase migrations.
- Includes a source-patching regression test and gradle Android APK compilation gate.

## Validation caveats
CI build/test verifies packaging and Kotlin compilation, not the complete behavior of all 507-era MediaFlow features on a real Android handset. Hardware scrolling, authentication redirects and folder-provider-specific SAF operations need device testing. The APK is debug-signed (not Play Store signed).
