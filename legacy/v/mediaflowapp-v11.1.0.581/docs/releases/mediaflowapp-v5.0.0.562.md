# MediaFlow 5.0.0.562

A big update. The app now matches the MediaFlow website **v562**.

## Discord

- **Show any title on Discord.** Use "Show on Discord" from a title's ⋮ menu (or from Settings → Discord). Choose how long it stays: until you stop it, 1 hour, 3 hours, or until the app closes on this device. It syncs to your account, and a Stop button ends it.
- **Custom Status** works like PreMiD's. You can set:
  - the activity type and name
  - the details and state lines, each with an optional link
  - large and small images (links), each with a hover text
  - party size
  - elapsed, remaining or exact times
  - up to two buttons
  Save your statuses as **profiles** (free). A profile can turn itself on during a daily or one-time **schedule**. Everything is saved to your account.
- While logging, progress can show your count **before** or **after** the draft. There are new `{before}` and `{after}` placeholders.
- The Discord profile card's header can show the title (or your own text). Settings shows a preview of what will be sent and **what Discord actually accepted**.
- New Discord statuses for the new pages and History tabs.

## Look and feel

- The MediaFlow logo has rounded corners and a transparent background everywhere: Discord, the Android icon (including adaptive icons), and the Windows app, tray and installer. On iOS it's a square, as Apple requires.
- All items in the **+** menu are the same size.
- **Background Processes** has the website's design:
  - a minimised bar, or expanded cards for each job
  - left or right placement
  - Setup, Pause/Resume, Review, Stop, New Recovery, Recovery Settings and Hide
  - whether it's open or minimised syncs with the website
- The **task progress card** is animated like the website's: waves, an aura, a flowing bar with a goal marker, a count-up percentage and a flash when you reach the goal. It can be minimised to a pill. Reduce motion is respected.

## Logging

- Every log entry shows progress **before → after**: in quick logs, advanced logs and Batch Log, including seasons, a rewatch that "Starts at 0", and "Completed".
- In the log form you can still see:
  - the reasons a title was recommended or rerolled (collapsible)
  - your no-skip and first-pick streaks
  - the live "Follow it" System Respect bonus

## New pages

- **Recovery Workspace**, **Rate Your Library** and **Missing Covers** are now their own pages in More. They are no longer in the Library. The + menu, Background Processes and shortcuts open the right page and tab.
- **Old System** has all its features:
  - **System**: balances, categories, conversion rules, recording consumption, and Undo
  - **View**: a simulation from your History
  - **Date View**: the same simulation for chosen dates
  - **Stats**: exact consumption per category
  It saves exactly what the website saves. Consuming now applies your conversion rules and can be undone; the website currently drops both.
- **Custom navigation** (Settings → Navigation), saved to your account. On phones, choose 3–5 dock pages and their order, and the order of More. On desktop, choose the sidebar order. Settings is always reachable, and new pages are added to More.
- **Library Overview** in Extras: the percentage of known totals cleared, a bar for each category, and estimates (≈) where totals are unknown. It has 15 rows per page, and tapping a row opens the Library filtered to that category. Its settings: show or hide, which categories (follow your categories, the MediaFlow System, a custom list and order, or Today's Balance), and rows per page.

## History

- **Logs** is unchanged.
- New **Consumption history** tab, like the website:
  - filters
  - your latest consumed titles
  - weekly summaries: total, active days, average, most active day, peak hour, longest session, categories, and most consumed titles
  - daily cards
  - Newer/Older weeks
  - select mode, Export CSV, and Edit/Delete
- New **Recently viewed** tab: one entry per title, grouped by day and time of day, with filters and Browsing Behavior Insights.
- New **Ratings** tab: a summary with a distribution, filters and sorting.
- **Library History**: up to 3 changed titles appear as chips. **More · N titles** opens a list with every title's cover and full name, what changed, **Edit** or **Restore**, and a search. The website got this too (v562).

## Recovery

- **Cover Recovery** matches like the website:
  - your saved External IDs are tried first
  - the search compares **every name** a source knows the title by
  - the confidence levels are the website's
  - it saves a cover automatically only for a saved ID with a matching title; everything else waits for your choice

  Titles with no match get **Search manually**. Quick Title Recovery uses the same matching.
- The **cover review** shows:
  - full titles in a wrapping grid
  - "Looking for: your title (year)"
  - year, source, format, match level and IDs
  - the name that matched ("also known as")
  - a large preview when you tap a cover
- The **Details review** shows the source record: full title, year, format, ID and the name it matched. Tap a value to see all of it. Titles with no match get **Search manually** (marked "Picked by you"). Existing and locked values are never replaced.

## Titles

- The title editor and Title Details have every field the website has:
  - **Title metadata**: year, format, runtime, release date, season, age rating, community score, source material, demographic, studios, producers, genres, themes and synopsis. Fields you edit are marked MANUAL.
  - **More details**: the media type plus the shared fields. Fields you edit are locked against recovery.
  - **External Media IDs** for every provider, with search and the website's validation.
  - the imported or created source.
- Title Details shows a title's metadata, extra details, source and External IDs.
- Add a title to your Personal Order, or remove it, from the title's ⋮ menu.

## Categories

- A full category editor:
  - name
  - icon: the emoji palette, your saved icons, any emoji, or an icon link with a preview
  - colour: the palette, your saved colours, or any hex
  - unit, type, target and weight (1–5)
  - default runtime per unit (HH:MM:SS)
  - seasonal and enabled
  - a default cover for titles without one
- **Reorder categories** by dragging, or with the arrows.
- **Clear** a category's Library titles; they can be restored from Library History.
- **Delete** a category and restore it later. Restore any missing default categories.
- Category icons from links now show up everywhere. They're kept on your device, SVG works, and you'll never see the 🖼️ placeholder: if an icon can't load, you get the category's first letter in its colour.

## Personal Order

- Drag titles to reorder them.
- Search, filters and sorting only change what you see, never the Order itself.
- Views: list, compact, cards, covers, or covers with titles, in 1–4 columns.
- **Export**, **Import**, **Clear** and **Restore last Order** work like the website.
- Moving titles in a big Order is quick.

## Speed

- Adding titles to a collection no longer freezes the app. CI checks this by adding 2,000 titles to a collection in a 50,000-title Library.

## Accounts

- **Sign up** and **Forgot password** from the app, with the website's messages. Email links open the website.
- A brand-new account's first data is created exactly like the website's first save.

## Version

- Android's App info and the Windows exe now show the full version (5.0.0.562). iOS still shows three numbers.
