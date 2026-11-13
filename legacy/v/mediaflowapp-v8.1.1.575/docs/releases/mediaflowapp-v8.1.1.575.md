# MediaFlow 8.1.1.575

Lighter on the database, and the Log a title XP preview. Matches the MediaFlow website v575.

- Besides saving each title and log on its own, MediaFlow keeps one complete copy of your account as a safety net. That copy is several MB, and the app rewrote it every 3 minutes and every time it lost focus (on Windows, every switch to another window), which used up the free Supabase project's disk budget. It's now rewritten at most every 30 minutes, and when you leave the app only if the last copy is at least 10 minutes old. Your data is saved and synced exactly as before; only the extra copy is rarer.
- **Log a title (Batch Log): the XP line is always there** once a title and an amount are filled in: "Working out the XP…", then "This log earns +N XP". The calculation runs on its own in the background (in 8.0.1 it could fail without showing anything).
