# MediaFlow 8.0.0.573

A big update: live sync for everything, and an exact time for logs. Matches the MediaFlow website v573.

## Live sync
- **Changes from the website and your other devices arrive live.** While the app is open, it checks every few seconds whether anything was saved elsewhere and syncs right away when it was. Before, everything except the logging draft waited for the once-a-minute sync. The full sync every minute stays as a safety net.
- The website had a bug that made it skip changes the app had just saved, for example covers and details found by the app's Recovery. That's fixed in website v572, and the website catches up on anything it missed the next time you open it.

## Logging
- **Log a title: set the exact time** next to the date. Leave it on "Now" (or midday for another day) or pick a time; the log is saved at that date and time, never later than now. Same as Batch Log on the website (v573).
