# MediaFlowApp — Milestone 42: Native Personal Order Mixed Queues

Source of truth: original personal MediaFlow tag `410`, specifically `src/js/components/221-v287-personal-order-collection-queues.js` (v287 Collection blocks, v368 reconciliation), with the existing read-only Personal Order native screen. Only repository `AlexGodly/MediaFlowApp` was modified.

## Implemented

- New **Mixed title & Collection queues** tab in the native Personal Order screen, with the existing **Direct ordered titles** view retained as the default.
- Read-only `orderPlan.categoryQueues` per-category token projection (`t:{titleId}` and `c:{assignmentId}`) and Collection assignment `createdAt` timestamp. The authenticated cloud repository and M37/M40 local previews preserve these references without rewriting or synthesizing account `state_data`.
- Source-aligned v287 reconciliation:
  - Extract unique, real, category-matched direct title tokens from the saved title order.
  - Extract unique Collection assignments sorted by `createdAt` then assignment ID for appended blocks.
  - Preserve valid saved mixed slots, reorder direct title tokens *within direct title slots* when direct ordering changes, and append missing direct/Collection tokens.
  - Treat Collections as **one contiguous outer queue block**, regardless of member count. Collection members keep their internal saved order.
  - Apply per-assignment **Match category / Force cross-category**, **Skip completed / Include completed**, traversed-unit exclusion, dropped-title exclusion and deduplication across the category recommendation sequence. Completed also includes progress >= total, as in v287.
- Native per-category queue view with expandable Collection blocks, real eligible member titles, queue slot numbers, saved Collection member positions and deduplicated **recommendation index**. Search is display-only and does not renumber slots. Paging shows 30 blocks per page.
- Read-only reference diagnostics for malformed/stale/duplicate queue tokens and ambiguous IDs. Missing/ambiguous Library, Collection or assignment records are **not guessed** or written back.
- Automated tests against v287-style fixtures including mixed tokens, ordering reconciliation, Collection slot vs member order, traversed titles, completion & Force Queue, category-specific deduplication, ambiguous references, immutable raw data, 50K synthetic Library performance projection and Flutter screen mode switching.

## Important scope limits

Queue positions are **per category**, not fabricated global Personal Order ranks. A Collection may have an outer slot such as #2 and the 1st eligible member within it; those two ranks are separate. A recommendation index is the position in the currently eligible **per-category** stream, which may change when progress/traversal/status changes. The source website's full task generator, Personal Order priority toggle, reroll history, active tasks, collection queue traversal commit/rollback, changes to assignments, and full v410 account persistence are **not** replaced.

This milestone is a read-only rendering and calculation foundation, **not** synchronized editing, and does not authorize cloud writes. No new Supabase writes, schema/Edge Function/secrets changes, production website changes, signed iOS/Android/Windows releases, or changes to `AlexGodly/MediaFlow` and `AlexGodly/MediaFlowPlus`.

**Next:** Milestone 43 — source-grounded read-only Personal Order expanded ranking, queue navigation and first-eligible recommendation audit, before considering local-only assignment edits.
