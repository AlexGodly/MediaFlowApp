# MediaFlowApp — Milestone 43: Native Personal Order Ranking & Recommendation Audit

**Read-only pinned website reference:** `AlexGodly/MediaFlow` release/tag `410`, especially `src/js/components/221-v287-personal-order-collection-queues.js` (`v287RecommendationEntries`, `v287CollectionItemsForAssignment`, `v287Queue`, `pickLibraryTitle` and the v180 reroll override). Implementation commits are exclusive to `AlexGodly/MediaFlowApp`.

## Implemented

- The native Personal Order mixed queue now shows **First eligible Personal Order candidate**, its exact v287 source type, category-specific outer queue slot and recommendation index. An *Inspect source slot* action focuses the correct direct title or expands the specific Collection block. *View all slots* restores the entire queue without rewriting saved positions.
- A **Title placements & recommendation audit** searches real Library titles by name or ID (bounded to 15 visible lookup results) and reports every saved occurrence across available category queues, including Collection assignment, member position, direct saved rank, category-scoped slot number and eligible recommendation index.
- Noneligible saved occurrences explain **traversed in this assignment**, **dropped**, **not matching task category**, **completed title skipped**, or **already recommended from an earlier source slot**. Collection's saved member order is separate from direct Personal Order title rank and from the recommendation index. One title can have multiple category/Collection placements without being duplicated in each category's recommendation stream.
- Personal Order priority toggle is retained as a **tri-state read-only snapshot value** (`true`, `false`, or `null` when absent) through the cloud reader and local M37/M40 previews. The UI explains that only an explicitly enabled toggle lets the website's v287 override prefer the queue; otherwise it uses its existing picker.
- An optional **excluded title IDs** field previews the queue-only v180 reroll exclusion step. This is not task generation or a reroll, doesn't simulate full website fallback, and does not persist exclusions.
- Per-category audit provenance caches lazily; tests include 50k Library titles and 7k Collection members, plus source-based eligible/skip/dedup cases and first-candidate deep-link and title-rank lookup widgets.
- Safety CI guard forbids cloud write routes in the added code and requires all CAS/queue upload flags to remain disabled.

## Known boundaries / next work

This is an explanation of v287 category queue recommendation order, not a prediction of the actual next task: other website task-category and fallback logic can still decide differently. No global queue rank is invented, and no Collection traversal progress is changed on this screen. It does not reproduce full v180 reroll history, active task lifecycle, account-wide Personal Order rank policy, editing/reordering categories/assignments, website XP side effects or synchronized cloud mutation. Source v410 remains read-only and untouched. No Supabase tables/secrets/functions or production data were modified.

**Next planned:** Milestone 44 — device-only Personal Order assignment planning, category rules and safe undo/redo with explicit conflict quarantine, never enabling production writes until shared server-side CAS + side-effect parity is proven.
