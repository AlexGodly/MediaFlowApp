# MediaFlowApp — Milestone 49: Native Dashboard Task & Recommendation Evidence Parity

**Pinned personal MediaFlow reference (READ ONLY):** GitHub tag \`410\`, \`src/js/components/221-v287-personal-order-collection-queues.js\` lines 390–489 and \`src/js/pages/personal-order/045-v139-prioritize-personal-order-for-recommendations.js\`. The original MediaFlow website, MediaFlow Plus, and production Supabase were not modified.

## Delivered

1. **Exact current task identity and source projection:** Decode the real v410 \`currentTask.libraryId\` and optional \`currentTask.v287OrderSource\` (source type, category, Library ID and Collection assignment). Preserve the title, category, target, reasons and session status. Never infer a title ID from title text.
2. **Confidence-preserving evidence classification:** Distinguish inactive session, absent/unknown category, missing Library ID, missing Library record, duplicate Library IDs, currently ineligible/missing queue entry, queue occurrence with no explicit annotation, confirmed annotation-to-current-queue match, and conflicting annotation. Show exact queue recommendation index, category-local outer slot, and direct vs Collection provenance only when supported by source.
3. **Lazy, expandable Dashboard evidence workspace:** The primary Next Task card shows the saved Library ID or explicitly says unavailable. A separate expand-on-demand evidence inspector can inspect selected category, current task eligibility and source, first five queue candidates, v139 priority tri-state, and hypothetical v180 title-ID reroll exclusions. Compute costly Library/Collection projections only when expanded.
4. **Safe Personal Order navigation and draft comparison:** Dashboard button routes to native Personal Order. The shared M44–M48 local draft appears only when owned, current, dirty and **identical** to the Dashboard's authoritative catalog object. Compare saved and local first title; a stale or different-account plan is never projected.
5. **Regression safety:** Test confirmed/unverified/mismatched/stale/ambiguous annotations, absent IDs, categories, force-category Collection rules, v180 exclusions without rank mutation, 100,000 source titles, widget expansion/navigation, live local draft comparison and discard. A CI guard protects exact-ID semantics and disabled cloud-write gate.

## Boundaries

This implements evidence and explanatory previews, **not** v410 scheduler task generation, live reroll history, production logging, saving, Collection traversal advancement, XP/History changes, or signed distribution. Source annotation can confirm a task's historical queue provenance only when still compatible with the **current** queue; it does not prove *why* the scheduler originally chose the task or that it was the first candidate. Queue fallback (when prioritization is disabled, missing, or exhausted) remains the original website's decision. No external account mutations or cloud writes occur.

**Next:** Milestone 50 — native Dashboard task and recommendation presentation parity, with continued strict data/synchronization safety.
