# MediaFlowApp — Milestone 37: Native Library Change Planning (Local CRUD)

**2026-10-14** · GitHub repo `AlexGodly/MediaFlowApp` only.

## Implementation

- Introduced `NativeM37LibraryPlan`, a signed-in owner-scoped **RAM-only** typed change planner for Library create, metadata edit, pending deletion and restoration. It is a live native user workflow, **not** an authorized cloud editing/synchronization pipeline.
- Native Library has **Create local title**, **Review local changes**, **Preview changes**, **Undo**, **Redo**, **Bulk select / Select visible / Deselect / Stage deletion** controls. Create/edit forms cover title, category, status, priority, progress/total, rating, cover URL, tags and description. The status/season/progress side effects from full v410 are not automatically replayed or assumed.
- Preview projects the Library over the original catalog only when explicitly requested. It does not alter the original catalog or its Sessions/History, Collections, Personal Order, tasks, settings, XP ledgers or unknown v410 fields. Local creation uses a clearly non-cloud temp ID. The original cloud view remains available at all times, and planned deletion titles can be restored through the review sheet or Undo. Source remains read-only even with preview toggled off.
- Bulk deletion requires explicit confirmation and warns about references from History, Collections or Personal Order. It is one reversible local operation, not a cloud deletion/tombstone, and does not remove related records.
- A fresh authoritative or offline cached catalog object **quarantines existing pending changes**, even if the displayed values look the same. No automatic rebase/upload against a different `state_data`, no stale commit. Discard re-attaches to the latest observed catalog.
- Invalid title/category, invalid numeric values, malformed cover URLs, ambiguous duplicate IDs, seasonal aggregate changes, oversized changes and absent owner context fail closed. Stage count is capped at 200, and up to 30 undo checkpoints; the preview references unchanged source title objects instead of cloning the entire dataset.
- Owner-specific plan is created/destroyed with the authenticated shell; it cannot cross account sign-out. The existing M20 priority-only RAM draft and M33 encrypted offline-priority queue remain independent; **M37 CRUD plans are not eligible for M33/M34 upload/review**.
- Added regression tests: create/edit/restore/undo/redo and atomic bulk deletion, 100,000 titles, format and duplicate validation, stale refresh, cross-owner isolation, responsive Library UI and modal confirmation. Existing Dashboard/Library/History tests remain in CI.

## Not yet complete

**Full MediaFlow v410 native Library CRUD is NOT production-ready.** The actual website's account-state writer still relies on unconditional full-state UPSERT. Coordinated database-enforced CAS/RLS/idempotent side-effect handling across website and native app is a blocker. Creating full-fidelity records needs v410 metadata/provider/season/external ID preservation and matching event side effects; deleting must resolve History, Collections, Personal Order, XP and tombstones without loss. The current projection is intentionally lossy and cannot be serialized to the account's cloud snapshot. Local plans expire on restart, as documented in the UI.

No Supabase mutations, GitHub website changes, deployment or production app distribution. No physical Android/Windows/iPhone design parity sign-off.

**Next:** Milestone 38 — title details, per-title metadata and batch UI parity, followed by an explicitly approved coordinated sync migration.
