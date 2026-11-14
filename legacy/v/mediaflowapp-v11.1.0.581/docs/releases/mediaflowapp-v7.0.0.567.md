# MediaFlow 7.0.0.567

A big update: smoother on Windows, Consuming… and Discord names, Settings search, and logs that count on the day you consumed. Matches the MediaFlow website v567.

## Faster, no more freezes
- **Automatic backups** are built and written in the background. With backups every few minutes, the app used to freeze for several seconds each time.
- **Syncing** hands your account back to the app without copying it on the screen's thread, and a sync starting no longer redraws every page.
- **Discord's level, XP and streak** are worked out with each sync in the background, not on the screen after every change.
- **App time** is saved once a minute without redrawing every page.
- **Recovery** saves in batches while it runs and the Recovery page updates a few times a second, so it stays smooth with big libraries and long review lists.

## Discord
- Everything sent to Discord fits Discord's limits: text that's too short or too long, or a link that isn't a web address, is left out instead of reaching Discord's SDK.
- **Turn Discord on or off** right from the Log page.
- **Title names:** Discord shows the name MediaFlow shows for each title (English, Romanised Japanese…), or always the main name (Settings → Discord → Title name on Discord).
- **Name on Discord:** pick any of a title's languages, or type your own name, for Discord only. By default it's used while that title is the one you're consuming; "Keep for this title" uses it every time. The title itself never changes.
- **Custom Status:** a Library title goes in with the name it shows, and you can pick any of its other names.

## Consuming…
- **Where the title comes from:** the last title you edited in the log (default), the last reroll, the recommended title, or only a title you choose.
- **Clear** removes the title, and Discord goes back to its normal status.
- **Stop** now stops the title you chose (it used to fall back to the last edited title).

## Logging
- **Logs count on the day you consumed** (website v566), not the day you pressed Save or Save & get next task, so a log kept open for days no longer breaks your streak. Setting: Settings → Account → Default Logging Method → Log time (when each unit was logged, the default, or when the title was added; shared with the website). A log over several days is saved as one session per day; XP and amounts are split, totals unchanged.

## Details Recovery and ratings
- **Select all / Deselect all** when you review what to save for a title.
- **Ratings found by Details Recovery are saved as the title's external ratings**, and replace an older automatic rating with a newer value. A later ratings refresh updates them when there's a newer value, and keeps them when there's none or a source can't be reached. Ratings you entered yourself never change.
- **External ratings on titles:** Settings → App → General → Show external ratings on titles. Off by default.

## Settings
- The two tabs are now **Account** and **App**.
- **Search settings** with the search button at the top: matching cards open, and long groups show only the matching settings.
- **Floating Controls** has every floating-controls setting of the website in one place.
