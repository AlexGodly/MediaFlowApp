# MediaFlowApp Android WebView v1.0.0 Beta 1

**Reference website:** MediaFlow v507 Stable (release ZIP checksum pinned).
**App:** Kotlin / Android System WebView / Android 10+.

### Included
- A full bundled copy of the real website's v507 frontend, replacing incomplete native-screen replicas.
- Local assets and vendored startup JavaScript (Supabase client, React and ReactDOM) to reduce network stalls before the interface appears.
- MediaFlow's existing Dashboard, Library, Advanced Logging, Recommendations, Settings, Personal Order, Collections, History, Statistics, themes and other features from the v507 frontend.
- Browser-isolated external links, Android file picking and downloads, and blob-based JSON/CSV exports through scoped storage when supported.
- Original launcher icon; existing package ID; build-time release SHA256 validation.
- Complete backup of the previous Flutter code, docs, tests and build workflows under `legacy/flutter-beta7/`.

### Safety
- No database migrations, Supabase configuration edits or backend writes by the Android native host.
- The page continues to use MediaFlow's existing Supabase client and website synchronization logic.

### Beta limitations
- No guarantee of faster scrolling or lower CPU/GPU work without profiling and optimizing MediaFlow's mobile rendering.
- Android device verification pending; online providers, authentication redirects, large exports, and update flow require real-world testing.
- Debug-signed APK (installable for testing), not a Play Store production signature.
