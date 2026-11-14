# MediaFlow 2.0.0.560

A big update. The app now matches the MediaFlow website up to **v560** (TMDB covers from v559–v560 are left to MediaFlow+).

## New version numbers

Versions are now **MAJOR.FEATURE.FIX.WEBSITE**:

- **MAJOR** goes up for a big update with several changes (like this one).
- **FEATURE** goes up for one new feature.
- **FIX** goes up for a bug fix or a very small change.
- **WEBSITE** is the website version the app matches (560 = website v560).

"Check for updates" now compares the numbers, so it never calls an older release "new".

## Last uninstall: permanent signing key

The Android app is now signed with a permanent MediaFlow key.

- **Uninstall the old app once before installing 2.0.0.560.** Your data is safe in your account and comes back when you sign in.
- From now on every update installs straight over the previous one, like a normal app update. You won't see "package conflicts" again.

## Instant cloud sync (website v556)

Accounts that the website has moved to per-record storage now sync **record by record**, exactly like the website.

- Each log, title or setting you change is uploaded on its own, so changes from the website or another device show up within about a minute instead of up to 3 minutes.
- Two devices can no longer overwrite each other's changes: only the records that changed are written.
- The app checks for new changes every minute while it is open, and right away when you come back to it.
- It also keeps the website's backup copy of the whole account up to date (at most every 3 minutes, and when the app goes to the background).
- Every record is written byte-for-byte the way the website writes it, which is proven by tests generated from the website's own code. Accounts not yet moved keep the previous safe sync.

## Theme system (like the website)

**Settings → Account → Theme** now has the website's whole theme system:

- All **135 website themes** in the MediaFlow, Platform and Full-style collections, plus **Custom** with its 7 colours.
- **Global Light / Dark**: fixed light or dark surfaces with the theme's accent colour.
- **Dynamic Cover Theme**: colours taken from a cover, with every website source.
  - Dynamic
  - Library covers you pick
  - Image links
  - Recommended only
  - On This Day only
  - Source picker
  - A rotation interval for each
- The theme is saved to your account, so the website and the app share it. The app opens in your last theme straight away.

## External ratings and IDs (website v555)

- **Title Details → External ratings** shows the title's ratings with their source. **Refresh ratings** looks them up the way the website does:
  1. It uses saved IDs first.
  2. It finds missing IDs through Wikidata links and every name the title has.
  3. It checks again with the new IDs.
- Seasons without their own IMDb or TMDB entry share the whole show's rating.
- Saved IDs are never replaced, conflicting IDs are ignored, and names must match exactly with a matching year and type. When a match is uncertain, it is skipped rather than guessed. Ratings you set yourself or locked are never touched.
- **Edit / find IDs** opens the External IDs editor with the website's ID finder:
  - It searches one site or all of them with every name the title has.
  - It groups the results by ID, preselects a single exact match and marks loose matches "check this".
  - It never replaces an ID you already have.
- **Settings → Account → External ratings → Refresh all missing ratings** works through every title still missing ratings, starting with titles that have none. It shows progress, can be stopped, and pauses itself if the rating sites' daily limit is reached.
- Ratings and IDs are written exactly as the website writes them, proven by tests generated from the website's own v555 code.

## On This Day: recover in one tap

When today's On This Day titles are in your Library, a **recover** button appears next to the heading. It opens all of them in one list where you can:

- find each title's cover and details
- refresh ratings and IDs for all of them at once

## Collections: a mini library

- **Adding titles is fast now**, even with a very big Library: the picker search no longer lags.
- Inside a collection you get the Library's tools:
  - **Order** on/off, with drag-to-reorder
  - the same **view modes**: list, compact, cards, covers, covers with titles
  - **sorting**: order, title, priority, rating, progress, total, year; ascending or descending
  - **filters**: search, categories, status, priority, rating, cover, year, runtime, season and episode ranges
  - **select** several titles to change status or priority, or remove them
  - **Edit** or **Remove** any title from its menu
- View settings are saved to your account like on the website.

## Streak reminder

**Settings → This app → Streak reminder**: get a "you haven't logged today" notification at a time you choose (8:00 PM by default). On days you have already logged, it waits for tomorrow.

## Windows: tray and start-up

**Settings → This app → Windows**:

- **Close to tray**: closing the window keeps MediaFlow running in the tray (Open, Sync now, Quit).
- **Start with Windows**, and optionally **start minimized** to the tray.

## Install notes

- **Android**: uninstall the old app **once**, then install `MediaFlow-2.0.0.560-Android.apk`. Future updates install over it. Allow notifications if you want the streak reminder.
- **Windows**: run `MediaFlow-2.0.0.560-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. It is unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `MediaFlow-2.0.0.560-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
