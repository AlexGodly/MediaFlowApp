# MediaFlow 1.0.0

The first stable release of the MediaFlow app. From now on releases are normal (latest) GitHub releases, not pre-releases, and versions go 1.0.0 → 1.1.0 for new features and 1.0.1 for fixes. The app's in-app **Check for updates** now finds them.

## Leveling and Day Streak on the Log tab

The website's sidebar cards are now at the top of the Log tab:

- **Leveling**: your level, total XP, XP into this level out of what the next level needs, a progress bar, and "N XP to Level N+1" (or "Ready for Level N+1").
- **Day Streak**: days in a row (ending today) with at least one non-skipped log, and today's XP multiplier (×1.58 XP).

Both update as soon as a log is saved. They use the app's current look; they will follow the theme system when it arrives.

## Floating Task Progress

While the logging form is open, a floating card (next to the + button) shows how much of the current task you have added **before pressing Save**, like the website's Task Progress:

- the task's category, units added out of the goal, and the percentage (measured against the top of the goal, so 12 of a 12–16 goal is 75%);
- a bar with a marker at the goal's minimum;
- the status: Ready to log, In progress, Goal reached, Within target range, Recommended maximum reached, or Overwatched / Overread / Overconsumed;
- a short flash when you reach the goal.

It appears once a title from the task's category is in the log. The **–** button shrinks it to just the percentage; on phones it starts shrunk so it doesn't cover the form. **Settings → Default Logging Method → Show Floating Task Progress** (the website's setting, synced) hides it.

## Reroll titles as often as you like, and see your rerolls

- **Reroll title** is now also inside the logging form, not only on the recommendation card, and you can use it as many times as you want. The form stays open on the new title; titles you already added stay in the log. It never touches your streaks, as on the website.
- **Rerolls** opens the website's **Current rerolls** list: every title recommended for this task (Initial pick, Reroll #1, #2…), which ones count for exact-title Respect XP (Respect slot) and which are extra rerolls, which one is current, and **Edit** to open a title.

## "Units" on the Log page

The Log page now says **unit / units** instead of the category's own unit (episodes, chapters, pages…): Consume 12–16 units, Unit reached, +3 units, Add Unit 5, 0 / 12 units. Only the words on screen change; each category keeps its unit in your account, so the website and your saved data are unaffected.

## Library: no more freezing, built for 100,000+ titles

Changing a sort or filter on the Library page could freeze the app long enough for Android's "isn't responding". The whole Library was re-sorted on the screen's thread, and every comparison re-read both titles' fields and re-split both titles into natural-order pieces — millions of times for a big Library. It also happened again after every sync.

- Each title's sort values are read **once per change to your account** into compact lists; the natural title order ("Part 2" before "Part 10") is worked out once, as a rank.
- **Big Libraries sort in the background.** The previous order stays on screen with a thin progress bar until the new one is ready. Sorted orders are kept, so switching back to a sort is instant.
- **Search waits for a pause in typing** (on big Libraries) and searches text prepared once.
- **Counts are worked out once**: category counts in the category picker, and the Rate Your Library / Missing Covers badges. Rate Your Library picks the next title in one pass, and Missing Covers uses the prepared title order.
- **Typing in the logging form no longer re-sorts the Library.**
- The **Logging Library** (the picker on the Log tab and behind the + button) uses the same engine.
- Orders are exactly the ones you had before, now with a fixed final tie-break (title, then Library order), proven by tests that compare every sort, direction and filter against the old code.
- Fixed: **Library → Last logged** sorted every title as never logged. It now uses each title's last log (by Library id, then by title), like the website.

On the build server, a 100,000-title Library sorts in the background in well under a second per sort; see the CI test log (`100k titles: …`) for the measured times.

## Install notes

- **Android**: `MediaFlow-1.0.0-Android.apk`. It installs over Beta 16. If Android refuses to update over a previous build, uninstall it first — your data comes back when you sign in.
- **Windows**: run `MediaFlow-1.0.0-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. Unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `MediaFlow-1.0.0-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
