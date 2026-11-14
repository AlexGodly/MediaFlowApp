# MediaFlow 1.0.0 Beta 13 — the Log tab: MediaFlow Recommends and per-unit logging

Beta 13 brings the website's whole recommendation logging flow into the app as a new **Log** tab (the first tab).

## MediaFlow Recommends

- **Start session** and MediaFlow hands you one category at a time, with the amount to consume and why it picked it — the same task engine as the website (neglect, balance, repetition, seasonal bonus, session size), including your scheduler category scope, category classes, Personal Order queues and Collections, and external-rating influence when you have those turned on.
- **Exact title recommendations** (when enabled in your settings) show the recommended title; **Reroll title** moves to the next one without hurting your streaks.
- **Log & Complete**, **Give me something else**, **Skip** and **End session** work exactly like the website, including your no-skip and first-pick streaks and the **System Respect XP** bonus for following the recommendation (shown on the card before you log).
- The current task, session and streaks are synced: start on your phone, continue on the website, or the other way round.

## The full logging form

- **Quick**: *Progress reached* (enter the episode/chapter you got to; seasons supported) or *Amount consumed* (with minutes). Add as many titles as you like, from any category, adjust them with − / +, or type a brand-new title (created in the task's category when you save).
- **Per unit**: log episode by episode — each unit has its own number, season, runtime and time, can be marked as a rewatch, and can be removed. Per title you can also switch to **Reached** or **Amount** for a whole run of episodes, set when you watched them, and customize the total runtime.
- **Note**, then **Save & get next task**. The log is written exactly like the website's: one History row per category, the recommendation outcome (partial / complete / over, or "Recommendation not followed"), System Respect XP, Library and per-season progress, completion and logged-completion XP, rewatch XP, start dates, first-episode and first-start rewards with the streak multiplier, the reroll-title bonus, the Activity Log entry and the next task.

## The same draft as the website

The open form is saved to your account as you go (the website's own resume draft). Start a log in the app and finish it on the website, or the reverse; per-unit drafts edited in both places keep every unit. Saving or cancelling closes the draft everywhere.

## Also in this beta

- The Batch Log (outside recommendations) is still one tap away: the list icon on the Log tab, or the **Log** button on Library and History.
- Batch logs now also award the website's **first-episode** XP when an episode title gets its first progress.
- Every new piece was checked against reference results recorded from the real MediaFlow v554 website on the same data (task picks, skips, rerolls, quick, mixed-category, not-followed, per-unit, Progress Reached, title reroll and new-title logs).

## Notes

- The app never writes the website's "forecast shortfall" XP receipts: in Progress-reached mode the app always derives minutes from the progress (as the website saves them), so there is nothing to make up.
- The website's "fresh episodes only" filter for seasonal recommendations needs episode-availability data the app doesn't load yet; with that filter on, the app may suggest a seasonal title without a new episode.
- If the website is open on another device while you log in the app, refresh it afterwards (the website saves its whole copy without a version check).

## Install notes

- **Android**: `MediaFlow-1.0.0-beta.13-Android.apk`. If Android refuses to update over the previous beta, uninstall it first — your data comes back when you sign in.
- **Windows**: run `…-Windows-x64-Setup.exe`, or unzip `…-Windows-x64-portable.zip` and run `MediaFlow.exe`. Unsigned, so SmartScreen will ask the first time (More info → Run anyway).
- **iOS**: `…-iOS-unsigned.ipa` must be re-signed to install (AltStore, Sideloadly or an Apple Developer account).
