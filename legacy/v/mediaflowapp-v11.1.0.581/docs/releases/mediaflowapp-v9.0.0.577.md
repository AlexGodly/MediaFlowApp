# MediaFlow 9.0.0.577

A big update: a smooth Personal Order, titles logged by parts, and more. Matches the MediaFlow website v577.

## Personal Order
- **Fixed: Personal Order could crash or stay grey.** Two screens cached different things under the same name; the Order screen got the wrong one. Cached values now keep their type apart.
- **Smooth on big Libraries** (tested with 31,468 titles): the Order, its search and filters are worked out once per change instead of on every frame, search waits for a short pause in typing, and the Collection queues no longer re-read the whole Library for every row (that froze the app for up to a minute). Only the rows on screen are drawn, in both tabs.
- **Add title** and **Add collection** buttons in both the Titles and Collection queues tabs (and per category).
- **Collections in the titles list:** "Collections in this list" shows the Collections assigned to each category inside its list, at their place in the queue, with move, rules, reset and remove. Adding a Collection from the Titles tab turns it on.

## Titles logged by parts
Edit title → **How this title is logged**: *Normal* (as before) or *By parts*.
- Each part (a game mode, a chapter, anything) has its own kind, name, counter, and optionally its own unit and time per unit (empty: the title's own, then the category's). The title's number is the sum of its parts; a part with a total can be completed; the title is completed only by hand.
- **Logging (Quick):** chips pick the parts; each chosen part gets its own line and bar — *Competitive · Match 41 → 44 (+3)* in Progress reached, or an amount. Several parts at once.
- **Advanced:** each unit is tagged with its part and takes that part's time.
- **Log any title / Batch Log:** the same part chips.
- Minutes, XP and the category amount use each part's time; History and Discord show the parts. Proved against the real website (golden fixtures).

## Also
- **Recovery reviews: "Show all results"** for covers and details runs the full search — every source, every name the title has, like a manual search — right inside the review card.
- **XP History adds up:** rows for adding and completing titles (and the completion streak bonus), so the list sums to your total XP.
- **Every keyless source, connected:** covers from Wikidata, Wikimedia Commons, Library of Congress, Inventaire.io, EpisoDate and Deezer; details from Wikidata, Library of Congress, Crossref, Inventaire.io, EpisoDate, German National Library, BnF, Grand Comics Database and Deezer. In Sources and category presets. Sources that now need a key or block requests say why. All checked live (tool/live_sources.py); of the seven earlier cover sources, Steam, iTunes, MusicBrainz, VNDB and IFDB answered, Gutendex was down (HTTP 503) and Google Books was over its keyless quota (HTTP 429) at the time of the check — both are kept and retried.
- **Log any title: "Add it to your Library"** when a search finds nothing; the new title is then the one being logged.
- **The Batch Log draft is shared:** the multi-title Log any title saves its titles, amounts, parts, date, time and note to your account, continues on the website's Batch Log or another device, and follows changes made elsewhere within seconds.
