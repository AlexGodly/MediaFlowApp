# MediaFlow 1.2.0

## TMDB covers

The app now finds covers on **TMDB**, like the website.

- **Search online** in the title editor and **Find cover** in Library → Missing Covers now show TMDB posters first for movies, TV and anime categories. They appear alongside the existing sources (iTunes, AniList, TVMaze).
- It goes through MediaFlow's own provider gateway as your signed-in account, the same way the website does, so the TMDB key stays on the server and never ships in the app.
- Movie categories search TMDB's movie catalogue first, and TV / series / show categories search TV first, using the website's movie/TV hint. A title with a saved TMDB ID is looked up by that ID first.
- Results show **Movie** or **TV** and the year. Close-but-not-exact titles are marked **similar title** and listed after exact matches, so check those before picking.
- The gateway allows one TMDB request a second per account; the app waits and retries once if needed. It shares the website's daily TMDB allowance for your account.

Nothing is saved until you pick a result and save the title.

## Install notes

- **Android**: `MediaFlow-1.2.0-Android.apk` installs over 1.1.0. If Android refuses to update, uninstall first — your data comes back when you sign in.
- **Windows**: run `MediaFlow-1.2.0-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. Unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `MediaFlow-1.2.0-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
