# MediaFlowApp — Milestone 41: Advanced Collections Browser & Personal Order Reference Audit

**Source baseline:** MediaFlow v410, using v274/v276 Collections mini-Library and v287 Personal Order `collectionAssignments` (further adapted by v392 Direct Add). Only `AlexGodly/MediaFlowApp` is modified.

## Implemented

- Native Collections detail now has **five actual presentations**: List, Compact, Cards, Covers and Covers + Titles. View controls are bounded and responsive, and never change the stored title sequence.
- Native filters for search (title/tags), category, status, priority, minimum rating and cover availability. Sort by saved order, title, priority, rating and progress. Page size 25/50/100/200, controlled next/previous with automatic clamping. Filtering and sorting are projections only, not collection mutations.
- User-selectable current-page members with Select Visible / Deselect Visible, confirmation-gated **Remove Selected** (up to 200 in one operation), and the inherited M40 undo/redo. Removal edits **Collection membership only**; Library, History, XP and Personal Order remain untouched. Checkboxes work across List/Compact/Cards/Covers/Covers + Titles.
- Source-grounded, **read-only** projection of `orderPlan.collectionAssignments`: `collectionId`, `categoryId`, queue inclusion/completion rules and traversed title identifiers. Original duplicate/unknown assignment records remain available for diagnostics instead of being silently rewritten.
- Collection Details expands to show Personal Order assignment count, direct title membership overlap and unique traversed members. It expressly does **not** invent queue ranks or count Collection members as directly ordered titles.
- Both the authenticated Supabase Repository projection and M37/M40 device previews retain Collection assignment references, without turning them into writable payloads.
- Tests for filtering, display-only ordering, pagination, v287 relationships, legacy unresolved refs, preservation through device previews, bulk confirmation and undo. CI checks native no-cloud-write guarantees.

## Parity boundaries

Still unfinished: v410 full Collection settings, drag reorder, extensive filtering facets (year/runtime/season count), collages/backgrounds, 30K-/100K-device performance benchmarks, all Personal Order queue token/rank algorithms, bulk edit metadata across Collections, Collection deletion tombstones, native persisted backups, cloud save and release signing. The legacy website unconditionally full-state UPSERTs; real native writes must await server-enforced CAS and consistent side effects across clients.

No changes to original personal MediaFlow, MediaFlow Plus, or production Supabase tables, functions, secrets or user data. Android/Windows CI builds are validation only.

**Next:** Milestone 42 — source-accurate Personal Order mixed Collection/title queues and read-only queue-rank foundations, with local-only future editing plans.
