# MediaFlow 1.1.0

Logging numbers work like the website now: − and + buttons, a number you choose yourself for Per Unit, and the category's own words inside each title.

## − and + on the logging numbers

Like the website's quantity steppers, these fields now have − and + buttons. You can still type any number.

- **Quick → Progress reached**: from your saved progress up to the title's total.
- **Quick → Amount consumed**: now labelled "Amount consumed", from 0 up to what's left of the title.
- **Advanced → Progress Reached** and **Amount Consumed**: from your saved progress (or 0) up to the title's total, at most 2,000 at a time. Changing the number still asks before replacing detailed per-unit entries.

The buttons switch off at the limits.

## Per Unit: you choose the number

Each title now has the website's **Log another episode** row:

- an **Episode number** box (with − and +) showing the next episode — type any number instead;
- **Log Episode** logs exactly the number in the box;
- **Log rewatch / reread** logs that number as a rewatch, so you can log an episode behind your current progress.

Fixed: after logging 8 and deleting it, the app still offered 9 — and the button's label could show a different number from the one it logged. Now the box shows exactly what will be logged, and deleting the unit you just logged gives its number back (delete 8 → the box says 8).

Each logged unit also has an **Episode #** chip: tap it to change that unit's number without deleting it, like the website's per-unit number box.

## Category words inside each title

Inside a title's logging controls the category's word is back: **Log Episode**, **Episode number**, **Episode reached**, **+3 episodes**, **2 chapters · 0:46:00** (chapters for manga, and so on). Everything outside a title — the task's goal, the Workspace bar, **This log** and the Task Progress card — keeps saying **units**.

## Install notes

- **Android**: `MediaFlow-1.1.0-Android.apk` installs over 1.0.0. If Android refuses to update, uninstall first — your data comes back when you sign in.
- **Windows**: run `MediaFlow-1.1.0-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. Unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `MediaFlow-1.1.0-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
