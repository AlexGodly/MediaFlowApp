# MediaFlow 1.0.0 Beta 14 — Log tab polish

Two fixes to the Log tab from Beta 13:

- **Advanced** — the episode-by-episode logging interface is now called *Advanced*, as on the website (it was labelled *Per unit*). Inside it, each title still has the *Per unit*, *Reached* and *Amount* methods.
- **The recommended title shows its own cover** at the top of the logging form, with the title name, category and target underneath. Titles without a cover show the usual placeholder with the category icon. The recommendation card uses the same placeholder when a recommended title has been removed from the Library.

Logging, sync and the shared draft are unchanged.

## Install notes

- **Android**: `MediaFlow-1.0.0-beta.14-Android.apk`. If Android refuses to update over the previous beta, uninstall it first — your data comes back when you sign in.
- **Windows**: run `…-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. Unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `…-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
