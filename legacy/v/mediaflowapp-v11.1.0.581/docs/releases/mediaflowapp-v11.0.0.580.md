# MediaFlow 11.0.0.580

A big update: titles logged by parts in Advanced logging, a "+ add" bar for amounts, Customize total runtime with the Stopwatch and Runtime Calculator, and task goal XP. Matches the MediaFlow website v580.

## By-parts titles in Advanced logging
Advanced logging now logs a by-parts title the same way Log any title and Quick logging do, in all three tabs:
- **Progress Reached:** the parts panel with each part's "Match reached" box.
- **Amount Consumed:** the parts panel with each part's Amount box.
- **Per Unit:** the same parts panel; each unit still has its own row and time below it ("Live · Match 5").

Chips pick the parts, each part has its card with *Match 4 → 7 (+3 matches) · 45m* and its bar, and the panel ends with "+N in all · time". Adding a by-parts title to Advanced logging starts it on the part logged last, one unit. Behind the scenes a part's box sets that part's units, so totals, runtime, XP and History are the ones Advanced logging already uses.

## "+ add" under Amount boxes
Every Amount box has a small second bar: type the next amount, press + (or Enter), and it is added to the box with the sum shown — **3 + 4 = 7** — so you don't add in your head. In Quick logging, Advanced logging (Amount Consumed), Log any title, and each part's Amount box.

## Customize total runtime, with the Stopwatch and Runtime Calculator
- **Log any title** has **Customize total runtime** (HH:MM:SS), like Advanced logging; turned off, the runtime goes back to automatic.
- Every Customize total runtime (Advanced logging and Log any title) has **Use stopwatch time** and **Use runtime calculator**: they fill in the Stopwatch's time or the Runtime Calculator's result (Extras).

## Task goal XP
A recommendation's goal now pays XP (Settings → Leveling & XP → Task goal, all editable, can be turned off):
- reaching the **minimum**: **+100 XP**;
- reaching the **maximum**: **+300 XP** more;
- **each unit past the maximum**: **+10 XP**, up to **+100**.

Once per task, by whichever log gets there — Logging or Log any title (everything logged in the task's category since it was recommended counts). The day streak multiplies it like other session XP, and it is saved on the log that earned it exactly as the website saves it. The XP previews in Logging ("Task goal · minimum (2) +100") and Log any title include it, and MediaFlow Recommends shows what the goal is worth.
