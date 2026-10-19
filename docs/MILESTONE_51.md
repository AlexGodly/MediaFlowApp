# MediaFlowApp — Milestone 51: Native Dashboard-to-Logging Task Handoff

**Original website:** v410 remains the pinned, read-only parity reference. This milestone adds a safe native navigation handoff, not the website's live logging/task transaction.

## Delivered

1. **Dashboard task handoff:** In Next Task, a new **Review in Logging** button appears only when a saved task has an exact, unambiguous Library ID. The task's category, Library ID, low/high targets and unit are read from the authoritative catalog, not title-text matching.
2. **RAM-only owner/snapshot pinning:** NativeM51TaskHandoff preserves the source MediaFlowCatalog by identity, along with the authenticated owner ID and saved task fields. A different account, replacement snapshot, missing/duplicate title or changed task fails closed. It does not rebase or stage data.
3. **Logging review banner:** A pending validated request shows the saved Library title and task target. **Review saved title** opens the existing title details sheet; users must explicitly choose any optional local draft action. Handoff dismissal is always available.
4. **No draft or selection takeover:** Routing and banner display do not select titles, start units, reset filters, change draft timestamps, alter workspace drafts, record History or award XP. Existing local drafts remain unchanged and their status is shown in the banner.
5. **Regression coverage:** Owner pinning, invalidation even with identical JSON, missing/duplicate IDs, active session, cross-category forced recommendations, existing drafts, 100,000-title catalog, navigation, stale requests and dismissal. New CI safety guard.

## Safety & remaining work

A handoff proceeds only when Logging loads **the same catalog object** that the Dashboard saw. The production NativeOfflineReadCoordinator.load() caches this object within a session; refresh invalidates the handoff rather than risking stale account edits. It never changes the personal website, MediaFlow Plus or Supabase, generates a task, records progress or awards XP. Actual v410 Logging completion and production synchronization remain outside this milestone.

**Next:** Milestone 52 — native task-linked Logging draft context and advanced draft continuity verification without production writes.
