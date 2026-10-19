# MediaFlowApp — Milestone 40: Native Collections Management Foundation

**Source:** original `AlexGodly/MediaFlow` tag `410`, particularly `src/js/components/208-v274-collections-library-rating-order-layout.js` and `286-v392-collections-instant-add.js`. **Change target:** `AlexGodly/MediaFlowApp` only.

## Shipped in Flutter code

- New owner-scoped `NativeM40CollectionPlan` for **RAM-only** Collection creation, metadata editing, reversible deletion/restore, adding/removing Library title memberships, reordering with explicit position, undo/redo (30 checkpoints), independent bounded 200 affected Collection changes and changed-snapshot quarantine. Local creations have temp IDs, not cloud Collection IDs.
- The existing Collections screen now has a visible local-change toolbar with Create, Preview/Source toggle, Review, Undo, Redo, stale warning, pending-deletion Restore and explicit Discard confirmation. Source data stays available even when a preview has been staged.
- Create/Edit form accepts Collection title, description and optional http(s) cover URL. Native detail has Edit Collection, Add Titles and confirmed stage deletion. Member list has manual-order up/down and confirmation-gated Remove (from Collection only; never from Library). Ordering is disabled while a filtered/sorted view is displayed so move arrows can't change an unseen queue position by accident.
- Add Titles sheet includes **v392-style Direct Add** while picker stays open, plus optional Multi-Select/Add Selected, search and All/Not added/Already added membership filters, 75-row bounded results. Original membership ordering remains stable; duplicates cannot be inserted, and additions require an unambiguous actual Library ID.
- On preview, other Catalog roots (`library`, `sessions`, `personalOrderIds`, settings projections, XP evidence) reuse the original immutable references; old cloud Collection objects are retained by reference unless explicitly locally edited. Unresolved legacy membership references are retained automatically, never guessed; deletion of an unresolved reference must be explicit.
- Regression coverage includes CRUD, atomic validation, source immutability, duplicate title/Collection ID refusal, missing references, 200-change cap, 100K title catalog, undo/redo, owner isolation, refresh quarantine and Flutter create/add/order/remove UI. CI static safety guard verifies cloud-write-disabled gates.

## Safety and incomplete parity

This is a **preview-only, session-scoped planner** and it cannot be serialized to full v410 `state_data`. Actual v410 Collections include `titleIds`, `order`, `autoBackground`, `createdAt`, `updatedAt`, `lastViewedAt`, Collection tombstones, drag-and-drop, category/rating advanced filters, artwork collage, multi-select removal, Personal Order Collection assignments and action XP events. Some are not represented in `MediaFlowCatalog` and must **not** be dropped or manufactured by a native writer. The website still uses a full-state account UPSERT; no native cloud writes are authorized until all writers have a shared database-enforced version/CAS and idempotent side-effect protocol.

Not a pixel-perfect or fully featured v410 Collections replacement. No Supabase changes, no changes to personal MediaFlow or MediaFlow Plus, no production deployment or signed Android/iOS/Windows release. Android/Windows CI builds are validation artifacts only.

**Next:** Milestone 41 — expand native Collections parity with source-grounded filters, display modes, bulk memberships and Personal Order reference analysis; continue local-only until coordinated synchronization is approved.
