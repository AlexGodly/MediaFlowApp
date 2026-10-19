# MediaFlowApp — Milestone 47: Advanced Mixed Queue Interaction Parity

**Pinned website reference (READ ONLY):** personal MediaFlow tag 410, src/js/components/221-v287-personal-order-collection-queues.js, particularly the v287 mixed outer queue reconciliation and Collection block movement. Original website, MediaFlow Plus, and production Supabase were not modified.

## Implemented

- **Opt-in local mixed queue workspace** integrated directly into Personal Order, rather than requiring a switch between the direct-title and Collection editors. Saved queue remains read-only by default.
- **Atomic mixed-slot ordering:** Move either a direct title or a Collection block one outer slot up/down or to an exact 1-based position. Each Collection remains exactly one contiguous outer queue position. Direct-title moves that cross other direct titles atomically reconcile that category's direct order in the existing M44/M45 shared undo history; other categories keep their original global positions.
- **Live recommendation audit:** Existing M42/M43 eligible recommendation numbers recalculate from the projected queue. Changing Collection precedence respects original member order and duplicate suppression, with no real task, History, XP, or traversal side effects.
- **Collection member pagination:** Expanded blocks show 20 eligible members per page, including pager controls. This avoids mounting thousands of ListTile widgets at once for large Collections.
- **Safety and UX:** Local edit badge, shared Undo/Redo/Discard controls, position input with bounded validation, separate saved-vs-draft preview switch, fail-closed stale-account/snapshot behavior, and immutable source catalog. Invalid, duplicate, cross-category, and unresolved references cannot be silently rewritten.
- **Regression suite:** explicit outer-vs-member ordering, cross-category invariants, rule-based deduplication after move, stale-source protection, large-Collection regression, and Flutter interaction/paging tests. A dedicated CI guard enforces no-cloud-write boundaries.

## Boundaries

This is **local device-session staging** only. The website has additional save, task advancement, and assignment timestamp behavior that is **not** implemented natively and is not simulated here. The native mixed direct-title slot movement is a safe extension of the source reconciliation semantics; the website v410 primarily offers Collection-position controls in its mixed board. Complete v410 lossless account write parity and signed production distribution remain future milestones. No uploaded state_data, no background synchronization, and no release published.

**Next:** Milestone 48 — additional native Personal Order recommendation and task coordination parity, without enabling production account writes prematurely.
