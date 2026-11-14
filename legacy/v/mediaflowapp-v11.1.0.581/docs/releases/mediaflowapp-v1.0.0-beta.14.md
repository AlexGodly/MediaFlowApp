# MediaFlow 1.0.0 Beta 14 — the whole website, in the app

Beta 14 is one big release (the owner's choice): every area of the MediaFlow website is now in the app, and all of it works offline.

## Navigation

- Phones: **Log · Library · History · Extras · More**. *More* holds Collections, Personal Order, Statistics, Settings and Account.
- Wide screens (Windows, tablets): a side rail with every section.

## Log tab

- **Advanced** is the name of the episode-by-episode interface (as on the website). Each title's methods use the website's words: *Per Unit*, *Progress Reached* and *Amount Consumed*.
- **Covers everywhere.** The recommended title shows its own cover at the top of the form, and every added title shows its cover too. A title without one shows the placeholder with the category icon.
- **Add recommended title** is one tap, like the website's shortcut. If the title is already in the log, the button shows it instead of adding it again.
- **Logging Library**, both on the page and from the **+** button, with all the website's tools:
  - search;
  - category, status and priority filters;
  - every sort, with direction and Shuffle;
  - per-page setting and paging;
  - List / Compact / Cards / Covers / Covers + titles layouts;
  - multi-select with *Add selected*;
  - "already added" marks;
  - typed new titles (Quick).
- **The + button:**
  - **Add titles** opens the Logging Library.
  - **Save & get next task** asks once, showing the XP the log will earn.
  - With no form open, the button starts the current task's form.
  - With no session running, it opens the Batch Log.
  - It can be hidden with the website's "Show the floating + button" setting.
- **Arrange your session:**
  - all 13 orders: added, updated, consumed/total/remaining progress, priority, alphabetical, logging, edited, seen, date added, random with Reshuffle, and custom;
  - direction;
  - Move up / down / to top / to bottom, which switches to custom order;
  - **Clear all titles**.
- **Collapse and expand:**
  - each title;
  - **Hide / Show Added Titles**;
  - the whole **Logging Workspace** (*N titles · M units staged*), which is shared with the website. *Save* stays visible while it is collapsed.
- **Long logs:** Advanced titles show their last 40 units, with *Show all*.
- **Numbers apply when you leave the field.** Quick progress, Quick amounts and Advanced *Progress Reached* / *Amount Consumed* no longer need an Apply button.
- **XP for this log**, as on the website:
  - the total;
  - Consumption, System Respect and the day-streak bonus;
  - whether you followed the recommendation, with the day and multiplier;
  - every extra reward;
  - a full breakdown per category and for System Respect.

  It comes from a trial save in the background, so it shows exactly what saving will award.

## Library

- **Finding titles:**
  - search, including tags;
  - category, status and priority filters;
  - 11 sorts with direction: last edited, date added, title, priority, rating, progress, total, remaining, last logged, last seen, random;
  - List / Compact / Cards / Covers views;
  - paging and page size.
- **Select titles** (tap the boxes, or long-press). Batch actions: **Status…**, **Priority…**, **Move to…**, **Fix completed progress** and **Delete selected**, each with a confirm. **Fix all completed progress** is in the menu.
- **Title Details:**
  - cover, progress bar and units left;
  - rating; tap to rate;
  - status chips that change the status in one tap;
  - start, finish and added dates, estimated time, past repeats, tags, seasons, description;
  - every log of the title;
  - **Log progress**, **Edit**, **Rate** and **Delete**.
- **Add / edit title** (the website's title editor):
  - title, category, status, priority;
  - progress, total, rating;
  - cover URL with preview;
  - estimated minutes, tags;
  - start and finish dates;
  - past repeats (full repeats + extra units);
  - seasons.
- **Search online** finds covers and totals from AniList, TVMaze, Open Library and iTunes (the website's sources).
- **Rewards and history** match the website: edit XP, cover-change XP, completed-title XP, the completion timeline, Library History, the streak multiplier and first-start rewards.
- **Rate Your Library** — a queue of unrated titles with a 0.1–10 slider and *Skip for now*. It awards the website's one-time rating XP.
- **Missing Covers** — every title without a cover. Search online or paste a URL; the cover-change XP is awarded.
- **Undo / Redo** for changes made in this session.

## History

- **Logs:**
  - search across titles, notes and categories;
  - category and media-type filters, show or hide skipped logs;
  - page size and paging;
  - today's minutes and XP.
- **Editing logs:** tap a log to edit its category, date, status, target, actual amount, minutes and note. The XP is recalculated as on the website, and start dates are updated.
- **Deleting logs:**
  - delete one, the selected ones, or the visible page, with a confirm;
  - each deletion is one undoable change, recorded in Library History.
- **Undo / Redo**, and **Undo last entry**, which gives the last log back as the current task.
- **XP History** (the website's progression journal):
  - every award with its source, title, base XP and streak multiplier;
  - source filter, search and paging;
  - **CSV / JSON export**.
- **Library History** — every Library change with its field-by-field details and XP. Deleted titles can be **restored**, one by one or the whole deletion.

## Collections and Personal Order

- **Collections:**
  - browse as covers (collages) or a list; search and sort;
  - create, edit (title, description, cover, background) and delete;
  - add titles with search, category and status filters and multi-select;
  - reorder, remove or bulk-remove titles;
  - see progress.

  Collection XP (created, edited, titles added, reordered) is awarded as on the website.
- **Personal Order:**
  - **All titles** or **By category**;
  - add titles; move up / down / to a position / top / bottom; remove; **Clear Order**;
  - category display order (like Settings, or custom) and hiding categories;
  - **Collection queues**: assign a Collection to a task category, choose its title rule and completed-title rule, move it within the queue, reset its progress, remove it;
  - **Prioritize Personal Order**.

  Personal Order XP is awarded as on the website.

## Statistics

Every section of the website's Statistics page:

- profile, lifetime achievements, leveling (with the exact website XP total), active time in MediaFlow;
- today / this week / this month, lifetime, units, streak;
- 7-day minutes and sessions, 30-day daily minutes, 90-day activity;
- category mix, media type mix, Library status, priority distribution;
- repeat consumption, Library health, advanced metrics;
- consumption heatmap (per year, with started / finished days), monthly recap;
- category balance, recent saturation, records, ratings, title completion timeline.

**Customize** shows or hides sections. The choice is shared with the website.

## Extras

- **Today's Balance**:
  - every category's health today and overall;
  - progress against its target;
  - the website's guidance (On track / Needs attention / Ease off today);
  - the day's totals and the health overview.
- **On This Day**: History logs and title starts and finishes from this date in earlier years, grouped by years ago.
- **Stopwatch**:
  - Start / Pause / Reset / Clear;
  - Set time, Add and Subtract;
  - **Use for minutes** fills the open log's minutes.

  It keeps running while the app is closed and is shared with the website.
- **Runtime Calculator**: Carry-forward and Multi-row modes, Continue with result, Previous total, and Use for minutes. It is shared with the website.

## Settings

- **Account settings** (shared with the website):
  - intensity;
  - MediaFlow System (exact titles, Personal Order, goals and scheduler weights);
  - the default logging interface and mode, the collapsed workspace, the + button;
  - every Leveling and XP value;
  - Library page sizes;
  - Dashboard sections and Today's Balance;
  - Statistics sections;
  - category scopes;
  - **Categories**: enable or disable, edit (name, icon, color, unit, media type, target, minutes per unit, weight) and add.
- **This app** (this device only):
  - the tab the app opens on;
  - sync when the app comes back, Sync now, and what is waiting to upload;
  - saved covers (size, clear);
  - **Check for updates**, with a link to the download page;
  - diagnostics (copyable).

## Works offline

If you have signed in on this device before, the whole app opens and works with no connection. That includes logging, adding titles to a log, Library edits, History edits, Collections, Personal Order, settings and the Stopwatch.

- Every change is saved on the device and uploaded when you are back online.
- Covers you have seen are kept on the device.
- **When the same thing was changed in two places, the newest change wins.** Changes to different fields or different titles are all kept.
- If your sign-in expires while offline, the app keeps working and asks you to sign in again only when it needs to upload.

## Checked against the real website

Every new kind of account change was recorded from the real MediaFlow v554 website on the same data and must come out identical in the app. Those changes are: editing a title (completed, rating, cover), adding a title, deleting a History log, adding titles to a Collection, and changing the Personal Order. That includes every reward, multiplier, ledger entry and Library History entry. The earlier logging and recommendation checks still pass unchanged.

## Notes

- **Android signing**: the build is ready for a permanent MediaFlow signing key. Until its two repository secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`) are added, the APK is still signed with the temporary CI key, as before.
- **Online search** for covers and totals needs a connection. Without one it says so; everything else works offline.
- **Not in this beta:** reminders and the Windows start-up / tray options. They need extra system integration and are planned for a later beta.
- **Refresh the website** if it is open on another device while you use the app. The website saves its whole copy without a version check.

## Install notes

- **Android**: `MediaFlow-1.0.0-beta.14-Android.apk`. If Android refuses to update over the previous beta, uninstall it first — your data comes back when you sign in.
- **Windows**: run `…-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. Unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `…-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
