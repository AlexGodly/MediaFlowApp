# MediaFlow 1.0.0 Beta 12 — native Flutter app with real logging

**This is a real app now, not a website in a frame.** Beta 12 replaces the WebView builds with a native Flutter app for Android, Windows and iOS, built around the thing that matters most: logging what you watch and read, straight into your MediaFlow account.

## What's in it

- **Sign in** with your existing MediaFlow account (same email and password as the website).
- **Library**: every title in your account, with covers, progress bars and status. Search, filter by status (In progress, Planned, Completed, Paused, Dropped) and by category.
- **Log**: tap **Log** (or a title → **Log progress**), enter the episode/chapter you reached (or switch to an amount), adjust minutes if you like, add a note or pick an earlier date, and save. Rewatches/rereads of completed titles are handled the same way the website handles them.
- **History**: all your logs grouped by day, with today's time and XP at the top and a search box.
- **Account**: sync status, logs waiting to upload, sync now, sign out.
- Phone layout with a bottom bar; Windows and wide screens get a side rail.

## Logs land in your real account, exactly as the website would write them

A native log is written as the website's own **Batch Log** entry, with the same rules the website runs: Library progress (including per-season progress), completion and the completion timeline, rewatch tracking, automatic start dates, category-health XP, streak multipliers and the XP ledger awards (completion, first start, Batch Log bonus). The app was tested against reference results produced by running the real MediaFlow v554 website on the same data. Your logs show up on the website just as if you'd made them there.

## Works offline, never overwrites newer data

- Logs save on the device immediately and upload when you're online.
- Uploads use a compare-and-swap check on your account's version. If the website saved something in the meantime, the app re-applies your log on top of the newer copy instead of overwriting it, and a log can never be recorded twice.
- No Supabase schema, table or policy changes.

## Not in this beta yet

Dashboard recommendations, Collections, Personal Order, Statistics, Settings and adding new titles are still on the website (the Account tab links there). They're next, one area per beta.

If the website is open on another device at the same moment you log in the app, refresh the website afterwards. The website saves its whole copy without a version check, so a stale tab could overwrite a newer log.

## Install notes

- **Android**: `MediaFlow-1.0.0-beta.12-Android.apk`. If an older MediaFlowApp build is installed, uninstall it first (it was signed with a different key). Your data comes back when you sign in.
- **Windows**: run `…-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. Unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `…-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
