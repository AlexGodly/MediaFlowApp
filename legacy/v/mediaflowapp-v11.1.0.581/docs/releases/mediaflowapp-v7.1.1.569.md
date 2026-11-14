# MediaFlow 7.1.1.569

A fix for Discord and logging with titles that have their own unit. Matches the MediaFlow website v569.

## Discord
- **Consuming… follows your open log.** With "While logging, progress shows: after this log" (the default), the title you're consuming now shows its progress with the units in your log draft, as you add them, not only the progress saved before the log. "Before this log" still shows the saved progress, and {before} and {after} are always there.
- **A title's own unit on Discord:** a title with its own unit (Edit title → Unit for this title) shows it on Discord, for example "Match 14" instead of "Session 14", in every status ({unit} and {units}).

## Logging
- **A title's own runtime counts in the log's minutes** (website v569): 3 matches of 20 minutes are 60 minutes, not 3 of the category's sessions. This applies to quick logging and to Batch Log's default minutes (itemized logging already did). Titles without their own runtime keep exactly the same numbers.
- The Log page names the title's own unit everywhere in an entry: "+3 matches", "Match reached", "Log another match", the units list and Before → After.
