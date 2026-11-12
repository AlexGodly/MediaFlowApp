# MediaFlow 4.0.0.561

A big update. The app still matches the MediaFlow website **v561**.

## Discord Rich Presence, your way

- Customize everything Discord shows, from **Settings → Discord**, with a live preview. Your look is saved to your account, so every device shows the same thing.
- **Presets:** *Detailed* (title, progress and what you're doing) or *Simple*. You can also write your own two lines for each situation, such as logging, Library, a title's page, Statistics or Recovery.
- **Placeholders** you can use in your own lines: `{title}`, `{progress}`, `{total}`, `{unit}`, `{season}`, `{category}`, `{level}`, `{streak}`, `{xp}` and more. A part with nothing to show disappears together with its separator.
- **Status line:** your Discord status can say "Watching **Frieren**" instead of "Watching MediaFlow". Discord's profile card still names MediaFlow.
- **Logging:** pick which title the status shows from your log draft (the last one you touched, the first, or "Title + 2 more"). Its progress comes from the draft. Show "Logging…" with it, or just the title.
- **Pictures:** the title's cover or the MediaFlow logo, a small MediaFlow badge, and hover texts.
- **Also:**
  - a timer per title, per screen, per app session, or none
  - "Watching / Listening / Playing" per category (Discord has no "Reading", so reading shows as Playing)
  - categories to hide
  - privacy levels
  - an idle status after a few minutes
- Switching Discord on and linking it are still per device.

## The floating + is the website's

- The **+** in the corner now opens the same menu as the website:
  - 01 Add to Logging
  - 02 Add to Library
  - 03 Add Collection
  - 04 New Cover Recovery
  - 05 New Metadata Recovery
  - 06 New Combined Recovery (covers first, then details)
  - 07 Show / Hide the Background Processes widget
- On the Log page it also offers **Save & get next task** while a log is open.
- The separate + buttons on Library, Collections, Order and Log are gone. Order's "Add titles" moved to its toolbar.
- **Background Processes:** a small floating card with each running recovery, its progress, and Pause / Stop.
- **Settings → Recovery Shortcuts & Background Processes** chooses where recovery shortcuts appear (the + menu, Library, title editor, Title Details, Collections, Order, the widget) and when the widget shows. These settings are shared with the website.

## Recoveries keep running

- **Android:** a recovery keeps going while MediaFlow is in the background, and even after you swipe it away. A notification shows the progress with **Pause / Resume** and **Stop**.
- **Windows:** closing the window keeps MediaFlow in the tray until the recovery is done. The tray shows the progress and has Pause / Stop.
- **iOS:** iOS stops apps in the background, so a recovery pauses when you leave MediaFlow and continues when you come back.
- Running jobs are saved. A job cut short (app closed, phone restarted) continues the next time MediaFlow opens.
- Pause / Resume is also in the Recovery Workspace and in the Background Processes card.

## Better recoveries

- **Cover Recovery links verified IDs.** A cover you pick can also save the IDs its source reports for that exact record (for example AniList + MyAnimeList, TVmaze + IMDb, Open Library, TMDB). An ID that conflicts with one you already saved is never replaced. You can turn this off per title. This uses the website's rules (v433), checked against the website's own code.
- **Quick Title Recovery** from a title's page (⋮ → Recover cover / metadata / both) and from the title editor. It previews new covers and missing details for that title, and nothing is saved until you confirm. Replacing an existing cover asks first (website v453 / v456).
- **More details recovered.** Metadata Recovery now also fills the website's universal fields. Examples: original and alternate titles, broadcast season, episode / chapter / volume counts, creators, networks, release status, original language, authors, keywords, album artists, labels, track count, platforms and main-story hours. Sources now also return synopsis, genres and studios where they have them. Values you already have, or that you locked, are never replaced. This is checked against the website's code (v437 / v439).

## Notifications

A new **Settings → Notifications** section, per device. Each kind has its own switch:

- **Streak reminder:** a daily nudge at your time when you haven't logged.
- **Streak at risk:** later in the evening when your streak would end at midnight.
- **Recovery:** when a recovery finishes or stops (and, on iOS, when it pauses).
- **New episodes & chapters:**
  - anime with an AniList or MyAnimeList ID, from AniList's airing schedule
  - manga with a MangaDex ID, from MangaDex's newest English chapter
- **Level up** and **Milestones:** streak, Library size, completed titles.
- **Weekly summary:** on the day and at the time you pick.
- **Sync problems:** when your account couldn't sync for a few minutes.
- **New version:** when a new MediaFlow version is out.
- **Discord link:** when the Discord link expired and needs linking again.

Plus **quiet hours** (timed notifications wait until they end) and a **test** button. On Windows, timed notifications show while MediaFlow runs (it can stay in the tray).

## Android: an APK for every phone type

Each release now has four Android files:

- `MediaFlow-<version>-Android.apk`: **universal**, works on any phone.
- `-Android-arm64-v8a.apk`: most phones from the last several years (smallest download).
- `-Android-armeabi-v7a.apk`: older 32-bit phones.
- `-Android-x86_64.apk`: emulators and Chromebooks.

Stick to one kind. A per-phone-type APK installs over the universal one, but Android won't install the universal APK over a per-phone-type one.

## Home screen and shortcuts

- **Android home-screen widget:** your Day Streak, today's time and level, the title you're on with its progress, and **Log** / **Add title** buttons.
- **Long-press the app icon** (Android and iOS) for Log progress, Add title, Library and Recovery.

## Smoother sync

- Syncing, live log updates, saving the device copy and JSON work now run on one long-lived background worker. Before, each job had to start its own, so the screen never waits for that any more.

## Notes

- No database changes.
- Discord still uses only Discord's official Social SDK.
- An iOS home-screen widget isn't included. It needs a separate signed widget extension, which the unsigned iOS build can't carry.
