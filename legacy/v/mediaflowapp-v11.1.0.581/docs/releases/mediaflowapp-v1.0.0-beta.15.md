# MediaFlow 1.0.0 Beta 15 — faster

Beta 14 made the app slow, especially with a big Library or History. Beta 15 fixes that. Nothing changes in what the app does or what it saves.

- **Hidden tabs do no work.** Before, every tab was built when the app started, and all of them (Statistics, Extras, History, Library…) were rebuilt on every change: each sync, each tap in the logging form. Now:
  - a tab is built the first time you open it, then kept, so its scroll position and filters stay;
  - only the tab on screen updates; the others catch up when you return to them;
  - opening *More* no longer throws the open tabs away.
- **Heavy work is done once per change of your account, not on every redraw.** This covers:
  - the Statistics totals and charts;
  - Today's Balance and On This Day;
  - the XP History journal;
  - the History list order;
  - the sorted Library;
  - the Logging Library results.

  Typing in a search box now only filters.
- **Logging form:** "XP for this log" is recalculated only when something that affects XP changes, not when you collapse a title or change a filter.
- **Opening a title** saves its "last seen" time as one tiny change, instead of comparing your whole account, and uploads it with your next sync.
- **Saving an edit** (a title, a log, a Collection, the Personal Order, a setting) compares and copies your account directly instead of converting it to text several times, so edits on a big account are quicker.
- **The Stopwatch** only redraws while Extras is on screen.
- **Syncs:** a later change never postpones a sync that was already due sooner.

## Install notes

- **Android**: `MediaFlow-1.0.0-beta.15-Android.apk`. If Android refuses to update over the previous beta, uninstall it first — your data comes back when you sign in.
- **Windows**: run `…-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. Unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `…-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
