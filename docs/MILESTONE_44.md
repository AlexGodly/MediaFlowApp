# MediaFlowApp — Milestone 44: Native Personal Order Collection Assignment Planning

Pinned reference (READ ONLY): original personal MediaFlow website tag `410`, `src/js/components/221-v287-personal-order-collection-queues.js` (v287 Assignment creation, rules, queue position, traversal, removal, mixed queue reconciliation). Only `AlexGodly/MediaFlowApp` is modified.

## Implemented

- New **Manage assignments locally** tab in Personal Order. The planner is owned by the authenticated user in `MediaFlowShell` and disposed when the shell ends.
- Local-only **Add Collection to category** picker: uses live Collection IDs in the existing state projection, bounded searchable results (60), one assignment per category/Collection pair, default `categoryRule: match`, `completedRule: skip`, empty traversed list. No duplicated Library, Collection or account data; newly generated assignment IDs have a `local_m44_` prefix so they cannot be mistaken for website IDs.
- Change category rule **match / force** and completed rule **skip / include**, preserving existing traversal. Change Collection *outer queue* position one slot up/down or by a 1-based position. This reorders Collection tokens among direct title tokens within that category, using the existing native v287 queue reconciler; it does not change the direct Personal Order title sequence.
- Confirmation-gated **Remove assignment** (does not remove the Collection or its titles) and **Reset traversal in local preview** (does not mark real task history).
- RAM-only revisions with **Undo/Redo** (30 history steps), **Discard**, at most 200 staged operations, source identity verification and fail-closed protections against ambiguous/duplicate IDs.
- **View local queue preview** switches to the existing Native Personal Order mixed-queue visualizer and M43 first-eligible recommendation audit. A toggle returns to the authoritative saved queue; the original state and cloud remain unchanged.
- Source-identity and owner-pinned **conflict quarantine**: a new authoritative catalog while dirty or an authentication owner switch disables edits and preview until the user explicitly discards. A signed-out/different owner cannot reuse the original owner's planner. No auto-rebase or background synchronization.
- Tests cover create/remove/rule edits, mixed title/Collection queue move, undo/redo/discard, ambiguity protection, stale account revisions, owner isolation, 50K-title/9K Collection member synthetic dataset and native interaction. A CI guard enforces no-write source boundaries.

## Strict scope boundaries

This is a **device-session-only plan**, not durable storage and **not a production web editor**. Changes vanish on app restart and are discarded explicitly or quarantined when source changes; they are not exported to cloud. The source projections deliberately do not contain all v410 `orderPlan` fields, assignment timestamps, background UI state, task generator and XP side effects. Therefore **do not** serialize them back to Supabase or consider the planner eligible to upload.

v287 live website task generation, recommendation history, traversal commit and rollback, schedule and XP side effects, queue add/remove server writes, and complete native/website UI parity remain future work. Android/Windows/iOS production releases require later milestones and signing. Original `AlexGodly/MediaFlow`, `AlexGodly/MediaFlowPlus`, and production Supabase are unchanged.

**Next: Milestone 45 — Personal Order direct-title edit planning, category-aware ordering and reversible bulk operations, with the same explicit owner and cloud guards.**
