# MediaFlow 11.0.1.580

A fix to Edit title on phones. Matches the MediaFlow website v580.

## Edit title: parts and seasons on phones
On a phone, a part's row squeezed six boxes into one line: the Kind and Total boxes showed no label at all, "Done" was cut to "D…", and the number didn't fit. Each part now uses three lines on narrow screens:
- **Kind** and **Name** (and the remove button),
- **Done** and **Total**,
- **Unit** and **Time per unit**.

Every box always shows its label, even when it's empty. Seasons (Normal titles) get the same treatment: Name on its own line, then Done and Total. Wide screens keep the one-line layout.
