# MediaFlow 8.2.0.576

Log several titles at once. Matches the MediaFlow website v576.

## Log any title (Batch Log)
- **Add another title:** fill in a title, tap **Add another title**, pick the next one, and so on. The titles waiting in the log are listed at the top (remove any with ×). **Log N titles** saves them together as one Batch Log, like on the website; the date, time and note apply to all of them.
- **The XP preview covers the whole log:** "These N titles earn +N XP", worked out exactly as saving does (consumption, streak, completions and the Batch Log bonus once).

## Also in this update (prepared as 8.1.1.575)
Lighter on the database, and the Log a title XP preview. Matches the MediaFlow website v575.

- Besides saving each title and log on its own, MediaFlow keeps one complete copy of your account as a safety net. That copy is several MB, and the app rewrote it every 3 minutes and every time it lost focus (on Windows, every switch to another window), which used up the free Supabase project's disk budget. It's now rewritten at most every 30 minutes, and when you leave the app only if the last copy is at least 10 minutes old. Your data is saved and synced exactly as before; only the extra copy is rarer.
- **Log a title (Batch Log): the XP line is always there** once a title and an amount are filled in: "Working out the XP…", then "This log earns +N XP". The calculation runs on its own in the background (in 8.0.1 it could fail without showing anything).
- **Personal Order export / import keeps Collections:** Collections assigned to task categories, their queues and the queue view now go into the Order file and come back on import (as on the website); before, an Order exported from the app lost them.
- **Exports are stamped with the current MediaFlow version** (575, like the website) instead of an old 565.
