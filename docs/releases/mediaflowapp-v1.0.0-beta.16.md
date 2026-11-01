# MediaFlow 1.0.0 Beta 16 — no more "isn't responding"

Large MediaFlow accounts made the app freeze, often long enough for Android to show **"MediaFlow isn't responding"**. One real account is about 38 MB of data once unpacked (3 MB compressed). Beta 15 copied the whole account on the app's main thread several times for every change. Each copy can take seconds on a phone, so the screen stopped responding.

Beta 16 removes those copies. Nothing changes in what the app does or what it saves.

- **Syncing runs in the background.** Before, after every change the app copied the whole account on the main thread to upload it, and again to save it on the device. Now unpacking the cloud copy, adding your changes and packing it for upload all happen in the background.
- **The account is kept on the device in its compressed form** (the website's own format, about a tenth of the size). Opening the app reads and unpacks it in the background. The first start after updating converts the old device copy once.
- **No re-download when nothing changed.** Each sync first asks the cloud for the account's version, which is a tiny request. The account is downloaded only if it was changed somewhere else, for example on the website. Your changes are still only written if the cloud copy is the one they were made on.
- **"XP for this log"** is worked out in the background from the device copy, one calculation at a time. Changes you make while it runs are included in the next one. It no longer copies your account each time you change the form. **Save & get next task** reuses the figure on the card when it is up to date.
- **Edits only copy what they change.** Editing a title, a log, a Collection, the Personal Order or a setting used to copy and compare the whole account. Now only the parts the edit touches are copied and compared. For a title, that is the Library, the XP ledger, Library History and a few small parts, but not your History. Undo and Redo work the same way.
- **Big Histories are read once, not once per category.** The scheduler, Statistics and Today's Balance used to read every log again for each category and each time window. They now group History in one pass, with exactly the same results. Measured on a test account the size of the largest real one (35 MB, 22,000 logs), on the build server:

  | | Beta 15 | Beta 16 |
  |---|---|---|
  | Opening Statistics | 1.6 s | 0.3 s |
  | Today's Balance (Extras) | 0.66 s | 0.08 s |
  | Something else / Skip (next task) | 0.46 s | 0.18 s |
  | Saving a log (incl. the next task) | 0.82 s | 0.42 s |
  | Editing a title | 0.6 s | 0.16 s |
  | Copying the account on the main thread, per change | 0.15 s × 3–4 | none |

  Phones are slower than the build server, so these differences are bigger on a phone.
- **The open logging form syncs 10 seconds after your last change** (was 3), and right away when you leave the app. Each sync uploads the whole account, as the website does, so fewer uploads keeps the phone cooler.
- **Smaller fixes:**
  - Titles and logs on screen are read from your account only when a page needs them.
  - Device-copy writes can no longer overlap.

## Fixed: fields set to empty by an edit

When an edit set a field to nothing (for example a title's year or finish date), the app removed the field, while the website keeps it with an empty value (`null`). Saved edits now keep it, like the website. Every website-recorded edit check now also runs the way the app saves it (copy, compare, then apply), and the results are identical.

## Install notes

- **Android**: `MediaFlow-1.0.0-beta.16-Android.apk`. If Android refuses to update over the previous beta, uninstall it first — your data comes back when you sign in.
- **Windows**: run `…-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. Unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `…-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
