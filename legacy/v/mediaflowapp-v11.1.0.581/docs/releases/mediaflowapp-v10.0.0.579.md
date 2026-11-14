# MediaFlow 10.0.0.579

A big update: speed and memory on big accounts, pickers with real tools, titles logged by parts everywhere, History in each title's own unit, and fixes. Matches the MediaFlow website v579.

## Speed and memory (31k-title accounts)
- **Fixed the 1–5 second freezes:** after every sync (even of your own edit) the background worker handed the whole account back to the screen. A sync now sends back only what changed and patches it in place; the full account is rebuilt only when it has to be.
- **Log page cards no longer re-read the whole account** after a log: the XP total comes from the background with the new log's XP added straight away.
- **Diagnostics** say on which screen a slow frame or freeze happened, what happened just before it (a sync, a save…) and how much memory the app used.
- Smaller image memory cache.
- **Timings on a 31,468-title account** with 6,000 History logs (`test/perf_31k_test.dart`, measured on the CI machine):

  | Step | Time |
  |---|---|
  | Open the account (all Library titles) | 20 ms |
  | Library index | 9 ms |
  | Log page cards | 67 ms (22 ms again after a log) |
  | Category lists in your order (×100) | 3 ms |
  | Search all titles | 64 ms |
  | Split into records for sync | 209 ms |
  | Rebuild from records | 147 ms |

  With 100,000 titles, the Library's sorts take 35–174 ms in the background and filter + search 212 ms.

## Titles logged by parts
- **The same layout everywhere** (Logging and Log any title, like the website's Batch Log): a "Parts · N parts · N in all" header, chips, one card per part with a wide "Match reached" / "Amount" box, *Match 0 → 1 (+1 match) · 15m* and a bar, then "+N in all · time".
- **MediaFlow Recommends:** adding a recommended by-parts title (or quick-adding one from the Logging Library) starts it on the part logged last, one unit, so the log moves that part (it logged nothing before). The recommendation names the next part: **Next: Mode · Live · Match 5 of 10**.
- History shows one short line per part, with the kind once.

## History in each title's own unit
Consumption history, Recently viewed and Most consumed titles count each title in its own unit ("3 matches", not "3 sessions").

## Pickers with tools
- **Add titles** (Personal Order, Collections, Titles to keep offline, everywhere titles are chosen): the Library's tools — search, categories, statuses, priorities, sort with Asc/Desc, five views, pages ("N matches · Page x/y"), Select visible / Select all matches / Deselect all, a count, and titles already added shown greyed.
- **Add collection:** its own Collections tools — search names and titles, filter by the categories of their titles, "in a queue" filter, sort by name, count, created or edited (Asc/Desc), list / cards / covers, pages, select several at once, and the category at the top (or preset).

## Personal Order
- **Drag and drop** in a category's queue: drag a title or a Collection by its handle onto another row of the same category (Collection queues tab and "Collections in this list").
- The "Collections in this list" chip has a plain icon, ✓ when on.

## Covers for offline use
- **Why a cover was not downloaded:** "Why N could not be downloaded" lists each title with the reason (gone from its site, the site refuses downloads, too slow, no connection, a web page instead of an image…).
- Covers that may work later are tried again twice, a little later; nothing is marked unavailable for good — "Try them again" and every later run try again.
- Browser-like requests (the site's referer, a desktop browser's headers) get past more hot-link protection.
- **Find new covers** opens Cover Recovery for exactly those titles.

## Also
- **Title recovery: Select all / Deselect all** for details, and cover + details.
- **Category icons** render everywhere (no broken-image placeholder; a test checks every screen).
- **Every category list follows your category order** and the choice/filter layout (a test checks every screen).
- **Discord Rich Presence: no crash on on → off → on.** One connection for the app's lifetime, switches applied in order (only the last one counts), every step in Diagnostics, with a test.
- **Log page cards update instantly** after any log (Log any title, recommendations, Batch Log), with a small animation; edits and logs from other devices follow with the next sync.
- The fallback copy of your account (`mf556`) was already gzip-compressed, on both the app and the website; nothing to change there (no database changes).
