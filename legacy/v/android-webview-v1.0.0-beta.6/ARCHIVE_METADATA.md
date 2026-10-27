# MediaFlowApp Android v1.0.0 Beta 6 source archive

- Release tag: `android-webview-v1.0.0-beta.6`
- Frontend base: the pinned MediaFlow v507 Stable release archive.
- Scope: focused Recommendations, single and batch Logging, Library workspace, Log history, exact-title rerolls/history, XP preview, IndexedDB local snapshots, offline draft persistence, and queued Supabase synchronization.
- Contains every tracked root source file at the Beta 6 release commit, excluding the shared `legacy/` directory to prevent recursive archive duplication.
- The source archive is verified byte-for-byte by `tool/verify_release_archive.py` before the APK is built and published.
- Prior versions and `legacy/flutter-beta7/` remain preserved.
- Supabase schema, credentials and website source are not modified by this release.
