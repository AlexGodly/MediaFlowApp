# MediaFlow 6.0.0.565

A big update. The app now matches the MediaFlow website **v565**, and has almost every website setting, every import and export, and every API.

## Logging
- **Log any title** is always on the Log page, and in the + menu.
- **Today** and **On This Day** are on the Log page. A setting hides On This Day.
- On desktop the Log page uses the whole window, in two columns.
- On phones, the task comes first and Today sits below it.
- View or edit any title straight from the Log page, and **+ Add title** adds one from your Library or creates a new one.
- **Consuming…** shows on Discord the title you're watching or reading right now, on every device, until you stop it.
- The task progress bar has the website's waves and movement.
- Two task progress settings:
  - finish at the **minimum** (the default) or the **maximum** of the goal;
  - when you go over: keep counting past 100% (the default, with a warning colour), show only the warning colour, or show only the status.

## Titles
- Each title can have **its own unit and runtime** (for example "matches", 20 minutes each). Tasks convert it to the category's unit.
- Titles can have **several names**, one per language. You choose which name to show for everything, per category or per title, and can turn it off for a title.
- Search finds a title by **any of its names**. Recoveries fill in the names too.

## XP
- **Every action earns XP**: Library, History, categories, collections, imports, themes, settings and the rest. The same action on the same thing earns once every 5 minutes. Only real changes earn.
- **Away XP**: time away from MediaFlow earns a quarter of the active rate.
- Automatic backups, finished recoveries and fresh-episode checks earn XP.
- App time keeps counting while MediaFlow is in the background.
- The streak in notifications shows the real number (56, not 50).

## Settings from the website
- Floating controls, **Choice & filter layout** (order and hide category, status and priority choices), **Category Classes**, title recommendations, daily goal, Leveling, Statistics, MediaFlow System and the scheduler's fresh-episode settings.
- **Data & Cloud**:
  - **Full Data Backup**, **Settings Preset**, **Collections** and **Personal Order** export and import, in the website's formats.
  - **Other services**: import from MyAnimeList XML, Simkl (with its watched History), AniList, Letterboxd, Trakt, TV Time and the rest, or any CSV or JSON. Export for those services too. Ported from the website and checked against it.
  - **Automatic Backups** on every device: every 5 minutes to daily, one file or many, in a folder you choose (Windows and Android) or in the app's Documents folder.
- **API Providers & Testing**: turn cover sources on or off and test every API.

## APIs
- Covers and details now come from **Tenrai** (MyAnimeList, with Jikan as a fallback), AniList, **Kitsu**, **MangaDex**, TVmaze, Open Library and iTunes.
- The verified providers behind MediaFlow's server are used too when they are set up: TMDB, OMDb, Fanart.tv, EpisoDate, AnimeSchedule, MyAnimeList Official and Gutendex.
- Recoveries use the same sources and respect your choice of cover sources.

## Collections and Personal Order
- A collection's cover can be **any title's cover** from the collection or from your Library.
- Collections: export, import and recoveries.
- Personal Order:
  - **Lists or Tabs** for categories, and **lists per row** on wide screens;
  - **Queue tools** (title queues, Collection queues, Collections inside queues, section order);
  - an **Add** button on each category, and recoveries for the whole Order;
  - smoother, even with a long Order.

## Discord
- Desktop can **link your Discord account** too, to show your status when the Discord app is closed.
- Custom Status:
  - fill it from a **Library title** (name, progress and cover);
  - images from the **MediaFlow logo**, a title's cover or your **image library** (search, rename, delete), with a button to save a pasted link to the library.
- **When MediaFlow is closed**: stop showing the status (the default) or keep it while MediaFlow still runs.
- **Never appear idle**.
- **Activity type**: MediaFlow decides (the default), or always Playing, Watching, Listening or Competing.
- **Online status** while MediaFlow runs (Online, Idle, Do Not Disturb or Invisible), with a linked account.
- Platform is shown by Discord itself; its SDK has no setting for it.

## Account and covers
- Change your **name, picture, email and password**, or delete your account, in the app. The app shows your name instead of your email.
- **Offline covers**: keep the covers of all titles, chosen categories or chosen titles on the device, kept up to date after each sync.
- The app reports its version to your account, so the website's **Get MediaFlow** window shows which devices need an update.

## History
- The History tabs are in the website's order, and Consumption history looks like the website's.

## Speed and fixes
- Faster and lighter on every device: big lists only build what is on screen, and Personal Order no longer lags.
- The Dynamic Cover Theme follows the title's colours, like the website.
- Account screen text fixes.
