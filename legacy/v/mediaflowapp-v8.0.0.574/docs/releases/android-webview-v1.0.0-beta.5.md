# MediaFlowApp Android v1.0.0 Beta 5 — Phone Performance and Readability

Base: official MediaFlow v507 Stable release ZIP, bundled locally and SHA-256 verified.
Archives: legacy/v/android-webview-v1.0.0-beta.5/ plus every previous retained version.

## Android phone performance

- Stops recreating every mobile navigation button during unrelated Logging, Library and Dashboard rerenders. The selected tab still updates when navigation changes.
- Skips desktop-only sidebar sizing and resize setup at screen widths of 1080px or less. Avoids unnecessary forced layout calculations on phones.
- Adds a first-paint performance bootstrap, independent of MediaFlow cloud state. The default mode is Smooth; devices indicating up to 4 CPU threads or 3 GiB RAM default to Ultra light if no preference is saved.
- Four user-selectable Android-only modes: Original, Balanced, Smooth and Ultra light.
- Ultra light reduces mobile animation, blur and shadow work, skips paint for offscreen Library/History rows with CSS content-visibility, and temporarily renders at most 48 titles per Library page. It does not remove any titles or change saved paging settings. Other modes preserve the website page size.
- Sets cover images inside Library and History rows to asynchronous decoding during browser idle periods, without modifying source URLs or account data.
- Adds locally measured long-main-thread-task counters to Android Settings. These are diagnostics, not device FPS benchmarks.

## Android 15+ system bars and text contrast

- Applies Android system bar and display cutout insets to the WebView on Android 15 and later, where targeting SDK 35 otherwise draws behind system UI.
- Improves text legibility for mobile bottom navigation buttons, active states, section labels, hints and descriptions at narrow widths.
- Keeps current MediaFlow theme roles instead of imposing fixed colors.

## Safety and packaging

- Patches the original v507 application bundle at five exact render points, failing the build if the upstream source does not match.
- Adds packaging regressions and JavaScript syntax checks for the optimized bundle and performance scripts.
- Includes the complete v507 frontend, original Supabase client, Advanced Logging, recommendations, Settings and Android folder backup integrations.
- No website repository changes, no Supabase configuration/schema changes, no new cloud-writing code.
- Release includes debug-signed APK, SHA-256 sums, pinned-source manifest, complete archived source ZIP and detailed notes.

## Known limitations

This is a performance improvement, NOT proof of 60 FPS on an arbitrary low-end phone; verify device scrolling and cloud workflows. Ultra light may produce minor scroll size estimation shifts for unusually tall rows. Original and Balanced are available if visual compatibility issues appear. The bundled v507 UI still runs in Android System WebView.
