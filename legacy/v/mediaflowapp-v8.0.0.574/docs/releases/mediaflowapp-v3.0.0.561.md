# MediaFlow 3.0.0.561

A big update, matching the MediaFlow website **v561** (released together with this app).

## Title editing no longer freezes

- Editing a title, and saving it, used to copy and compare your whole Library and History on the screen. On big libraries this froze the app ("wait or close"), and the change was lost when you closed it.
- Edits now copy only the titles they change, so saving is quick even with 100,000 titles.
- The once-a-minute check for changes also does no work when nothing is new.

## Live logging with the website

- On accounts that use the website's per-record storage, the log you're filling in now follows along live in both directions.
  - **App → website:** what you type in the app reaches the website within about a second.
  - **Website → app:** while the app's Log page is open, it checks the website's log every 3 seconds and shows the newer one.
- Starting, rerolling or ending a recommendation on one side shows up on the other right away.
- It works while a Windows window sits unfocused next to the website, too.
- A log you're typing on the website is never replaced while you type (website v561).

## Time in the app earns XP

- Time spent in the app counts for XP like time on the website: the same XP per minute, times your streak multiplier, with no idle timeout and no daily cap.
- It counts while the app is on screen, including a visible but unfocused Windows window.
- App time is stored apart from website time, so neither side overwrites the other, and minutes from two devices add up.
- **Statistics → Active time** shows website time and app time separately, with a breakdown by platform (Android / Windows / iOS), in the app and on the website. **XP history** lists "MediaFlow app time".

## Discord Rich Presence

- MediaFlow can show what you're doing on Discord, for example:
  - "Logging Frieren · Episode 12 / 28" with the cover
  - "Browsing the Library · 1,240 titles"
  - "Checking stats · Level 24"
- The picture is the title's cover when it has one, and the MediaFlow logo otherwise.
- **Windows:** works whenever the Discord app is open. Nothing to link.
- **Android and iOS:** go to **Settings → This app → Discord → Link Discord** once. This is Discord's own sign-in. MediaFlow never sees your password or account token, and you can remove it any time under Discord → Settings → Authorized Apps.
- Settings:
  - **What to show:** everything; what you're doing without titles or covers; or just "Using MediaFlow"
  - **When idle:** after 5 minutes, show "Idle in MediaFlow" or clear your status
  - **Hidden categories:** categories whose titles are never shown
- Uses only Discord's official Social SDK, so nothing in it risks your Discord account.
- Every screen has its own status, and future updates keep it current.

## Recovery Workspace

**Library → ⋮ → Recovery Workspace**, or **Settings → External ratings → Open the Recovery Workspace**.

- **Covers:** finds covers for titles that have none, across the whole Library, one category, or a set of titles.
  - Only confident matches (same title and year) are saved automatically.
  - The rest wait for you to pick from a row of covers.
  - Existing covers are never replaced, and recovered covers earn the usual cover XP.
- **Details:** fills missing descriptions, genres, year, format, studios and external ratings from verified sources, the same way the website does.
  - Existing and protected values are never replaced.
  - Conflicting or uncertain results wait for your review, with a choice between the sources' values.
- **Sources (Provider Management):** turn metadata and rating sources on or off, see which ones are set up on MediaFlow's server, set the batch size, and give a category its own list of sources. This is shared with the website.
- **On This Day:** the recover button now opens the Recovery Workspace with today's titles.
- **Automatic rating catch-up:** while the app is open, titles still missing ratings are refreshed in the background, one at a time (up to 60 an hour). It follows the website's "Automatically retrieve ratings" setting, which you can now change in the app.

## Dynamic Cover Theme backdrop

While the Dynamic Cover Theme uses a cover, that cover now sits faintly blurred behind the app, like on the website.

## Install notes

- **Android:** `MediaFlow-3.0.0.561-Android.apk` installs straight over 2.0.0.560.
- **Windows:** run `MediaFlow-3.0.0.561-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. It is unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS:** `MediaFlow-3.0.0.561-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
