# MediaFlowApp — Milestone 50: Advanced Native Dashboard Task & Recommendation Presentation

**Reference:** personal MediaFlow v410, read-only. Native integration builds on M49 exact task ID and v287 provenance checks, not invented scheduler capabilities.

## Implemented

- Replaced the Dashboard's flat Next Task text card with a polished adaptive task hero, preserving the exact **NEXT TASK** heading and the read-only Dashboard workflow.
- **Responsive** card layout: poster beside details on wide layouts and a compact stacked composition on 320–600px mobile/tablet content panes. Breakpoint depends on actual card width rather than device width; actions wrap and long titles/reasons are bounded.
- **Safe saved-title presentation:** lookup is exclusively by currentTask.libraryId. Duplicate/missing IDs fail closed (no unrelated cover, progress, or saved title metadata). The website task title is displayed separately from the Library title so no title-text ID guesses are made.
- **Cover and progress:** HTTPS-only poster with failed-image placeholder. Invalid or embedded-credential links are not fetched. Library status/priority/progress appear only on exact, unique matches. Progress requires finite positive total and finite progress; percentage is bounded.
- **Task information:** category icon/name, recommended title, saved target range/unit, explicit Library ID or explanation, four task reasons (with overflow count), accessible progress, and an explicitly **unverified** label for raw source annotation.
- **Navigation-only actions:** Browse Library and (when available) Personal Order. Live task start/reroll/skip/submit and cloud state edits remain unavailable.
- **Regression tests:** direct resolution, duplicate IDs, missing IDs, untrusted image URLs, bad totals, 320px/360px Android screens, desktop presentation, inactive state, missing cover, navigation and original Dashboard/History integration. Dedicated CI guard checks boundaries.

## Limitations

The UI uses the native snapshot, not the website's live task scheduler or exact DOM styling. The full M49 evidence explorer remains the place to confirm queue provenance; a raw task annotation shown here is never treated as independently verified. No actual reroll history, logs, task actions, XP or Collection traversal changes, uploads, database edits or signed application release.

**Next:** Milestone 51 — native task information and Dashboard-to-Logging handoff parity, preserving the no-write account safety boundary.
