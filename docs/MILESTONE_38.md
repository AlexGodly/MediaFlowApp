# MediaFlowApp — Milestone 38: Native Title Details and Batch Metadata

**2026-10-14** · Scope: `AlexGodly/MediaFlowApp` only; no website, MediaFlow Plus, or production database modifications.

## Implemented

- New native Library **Title Details** sheet: cover, full selectable title, category, current status and priority, rating, progress fraction/bar, date-added/completed labels, tags, description, and existing season-progress summary.
- Title Details now provides a direct **Edit local metadata** action using M37's validated RAM-only field editor, and a confirmation-gated **Stage local deletion** action. It identifies cloud source versus unsaved local preview and warns on stale plans or related-reference counts.
- Native Library multi-select now offers **Batch edit metadata** alongside bulk deletion. Supported patch dimensions: category, status, priority, and additive deduplicated tags. Unselected dimensions keep their per-title values. The sheet explicitly reviews the selected count and demands confirmation.
- `NativeM37LibraryPlan.batchEdit` validates **all** selected IDs and the resulting title fields *before* committing changes. A mixed valid/invalid selection fails atomically. Existing title/cover/rating/progress/description/season fields remain untouched. One Undo/Redo checkpoint covers the complete successful batch; no-op batches create no checkpoint.
- Newly created local temp IDs can participate in a batch. Duplicate cloud title IDs, deleted/stale entries, non-existent IDs, max 200 selected/changed titles, invalid tags or statuses, or quarantined snapshots fail closed. Projection caching and source identity checks remain in place.
- Widget/model regression coverage for inspector, edit navigation, batch confirmation, tag merge, atomic rollback, 200-change cap, local drafts and undo/redo. CI static guard checks that this milestone cannot switch on cloud-write capabilities.

## Safety and remaining work

These are **device-only session plans**, not authoritative edits. No account-state updates, History/XP changes, collection/order mutation, provider calls or automatic session logging. Existing original v410 fields not represented in the read-only catalog (including external IDs/provider metadata) are *not* claimed to be editable; seasons remain read-only. Website-equivalent bulk actions, season editing, metadata provenance, duplicate-ID resolution, 100K physical performance, visual parity on devices and verified native persistence remain unfinished.

The original MediaFlow website uses a full-state account UPSERT; a cross-client server-enforced CAS/RLS and idempotent v410 side-effect protocol is required before native changes can sync safely. M33 offline priority queue remains separate and M38 changes are not eligible for upload. No signed app release is produced by this milestone.

**Next:** Milestone 39 — source-driven full-fidelity title metadata/season/external-ID parity, and safe simulation contracts, still without production cloud writes.
