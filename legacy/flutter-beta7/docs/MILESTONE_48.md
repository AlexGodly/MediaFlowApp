# MediaFlowApp — Milestone 48: Native Personal Order Recommendation & Task Coordination Preview

**Original website parity reference (read-only):** Personal MediaFlow tag 410, src/js/components/221-v287-personal-order-collection-queues.js lines 358–490, especially v287RecommendationEntries, v287OrderSourceForTask, v287StageTraversal, v287SubmitLog, pickLibraryTitle, and v180RecommendationCandidates. The v139 prioritization toggle and v180 reroll history remain authoritative on the website.

## Implemented

- **Read-only category/task coordination** in the mixed-queue workspace. Shows whether the authoritative snapshot has an active task in the selected category and whether Personal Order prioritization is **enabled / disabled / unknown**. The UI does not claim to predict the actual task when the priority setting is disabled or missing.
- **Candidate order and provenance:** Display first five eligible v287 queue recommendations, stable saved recommendation ranks, source outer slot, and direct-vs-Collection source. Force-category Collection members remain eligible as the v410 source permits. Queue deduplication, dropped/completed/traversed filtering, and priority setting are preserved.
- **Hypothetical reroll exclusions:** Input title IDs separated by spaces, commas, or semicolons (up to 200 unique). The candidate queue filters those IDs without recording a reroll, changing the task, or renumbering underlying recommendation ranks. An empty queue is explicitly marked as requiring the website fallback; it does **not** guess fallback results.
- **Successful-log what-if:** For an eligible Collection-sourced title, preview the *next queue* after imagining that the title was consumed and the website's successful-log validation passed. Only the owning assignment's traversal is changed in a fresh immutable catalog projection; source Library, History, Collection contents, existing current task, and assigned traversal remain unchanged. Direct-title candidates have no Collection traversal.
- **Saved-vs-local comparison:** When the M44–M47 RAM-only planner has changed the queue, view saved and projected first candidates side-by-side in the same read-only panel. Changes immediately reflect undo/redo and discard, without syncing.
- **Native tests:** Priority tri-state, active/absent task, Force Collection, exclusion behavior, successful-log what-if, direct-title no-op, cross-user quarantine, 100,000 synthetic title catalog, and widget interactions. Added a CI safety guard for the new service and view.

## Strict boundaries

This preview is **not** the real v410 task generator, reroll mechanism, History logger, automatic task advancement, save transaction, successful-log determination, or server-side synchronization. The real site checks quantity/progress and rolls back staged traversal if the save fails. The native service assumes success ONLY for a labeled hypothetical demonstration; nothing persists. No mediaflow_states writes, service writes, v410 edits, MediaFlow Plus edits, or production release. Task metadata does not include a lossless v410 current task libraryId, so an exact original task-source assertion is not possible.

**Next:** Milestone 49 — native task/recommendation evidence parity and deterministic preview integration with Dashboard, still without enabling production cloud writes.
