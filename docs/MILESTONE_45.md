# MediaFlowApp — Milestone 45: Native Direct Personal Order Title Planning

**Reference only:** Personal MediaFlow website tag `410`, `src/js/pages/personal-order/044-v138-personal-order.js` (`v138AddSelectedOrderTitles`, `v138MoveTitle`, `v138MoveTitleInCategory`, `v138RemoveOrderTitle`), together with `src/js/components/221-v287-personal-order-collection-queues.js`. Original MediaFlow, MediaFlow Plus and production Supabase were not modified.

## Shipped

- Native Personal Order adds **Manage direct titles locally**, next to Direct ordered titles, Mixed queues and the M44 Collection assignment planning workspace.
- **Add Library titles**: searchable available-title picker, global or category scope, up to 60 matching results shown; select visible, individual checks, and stage up to 200 unique IDs per atomic, reversible batch. New title references are appended in real Library sequence, matching the v138 selection behavior, not tap order. Existing/ambiguous/missing titles are not added.
- **Direct ordered titles**: original positional order visible with global/category-scoped 1-based positions. One-tap up/down and exact position dialog; category-only moves preserve all other categories' global slots. Display search never changes saved positions. Lists render 40 rows per page.
- **Remove selected locally**: confirmation-gated 1–200 direct-order references in one transaction; neither Library titles nor Collection assignments/membership are deleted. This also enables deliberate cleanup of explicit dangling order references, without inferring replacement IDs.
- The existing M44 owner-pinned, RAM-only plan now checkpoints **both direct `titleIds` and v287 Collection assignments/category queues together**. Add, remove, position, rules, Collection moves, undo, redo, and discard share the same 30-history-entry reversible journal and 200-operation limit. No parallel draft models or cross-account mutation.
- **Live native preview** of the resulting mixed title/Collection queue uses the existing v287 reconciliation. Saved Collection slots remain in place while direct titles follow newly staged global/category ordering. The screen can toggle back to the authoritative saved queue and discard changes.
- **Fail-closed owner/snapshot quarantine** still blocks a changed user or new authoritative cloud snapshot from rebasing staged drafts. Ambiguous Library IDs are never added or moved. Production writes, replay, and task/History/XP side effects remain off.
- Regression tests cover Library append order, category/global moves, duplicate/missing IDs, reversible bulk removal, interleaved assignment+title undo, owner/source changes, synthetic **100,000-title** catalog and Flutter planner interactions.

## Boundaries

This is **not synchronized Personal Order editing** and does not persist drafts across restarts. The catalog projection does not contain every source v410 `orderPlan` field, timestamps, or save-side effects; thus it must never be serialized as full cloud `state_data`. No new hosted release, no signed app, no Supabase writes, and no original personal edition or Plus changes.

**Next:** Milestone 46 — native direct Personal Order workspace parity and larger-scale category/picker UX, with continued immutable source and no-cloud-write guarantees.
