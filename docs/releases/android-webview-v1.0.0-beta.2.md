# MediaFlowApp Android v1.0.0 Beta 2 — Mobile Completeness and Reliability
Based on the **exact MediaFlow v507 Stable** frontend and cloud logic.

## Improvements over Beta 1
- **Large full-backup exports:** replace all-at-once Base64/native allocation with Android Downloads streaming, 192 KiB chunks and reply acknowledgements. Confirm actual byte counts, clean partial files, and limit to 750MB.
- **Correct Android Back behavior:** close MediaFlow's modal first and navigate its internal SPA views back to Dashboard before exiting.
- **Mobile performance modes:** a new Android-only Settings card with Original / Balanced / Smooth profiles. Balanced removes expensive modal blur; Smooth also removes extra decoration and most animation on phone widths. No changes to the desktop version, theme settings or Supabase.
- **PWA compatibility:** serve service-worker requests from the same locally bundled v507 archive using AndroidX WebKit interception.
- **Renderer recovery:** restart the Android shell on a WebView renderer crash without clearing local account data.
- **Android assets:** retain the original full website, CDN runtime libraries copied into APK at build time, verified official release SHA-256.
- **Validation:** packaging unit test, release metadata contract, Android SDK compile gate and checksum generation.

## Remaining verification
This is still a beta. Full parity (especially cloud login methods, online providers and very large exports) and actual frame timings require live Android testing. Smoothness is a selectable rendering trade-off; no 60 FPS guarantee. Production signing is not configured.

## Data safety
No Supabase migrations, no database schema updates, no cloud data modifications in the native Android host. Existing MediaFlow web sync rules remain authoritative.
