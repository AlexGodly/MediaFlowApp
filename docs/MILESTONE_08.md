# Milestone 08 — Conflict-safe native edit proposal foundation

**Baseline:** Original MediaFlow website v410  
**Repository:** AlexGodly/MediaFlowApp  
**Cloud write state:** **DISABLED** — no production data changes

## Delivered

- Introduced a typed, JSON-serializable native edit proposal carrying:
  - target account ID,
  - expected base revision,
  - timestamp,
  - operation kind,
  - minimal operation payload.
- Implemented a pure, copy-on-write local simulator for title priority/status changes and Personal Order reorder.
- Rejects wrong-account edits, stale revisions, unknown titles, invalid values, duplicate title IDs and reorder requests that silently add/remove entries.
- Does not alter unrelated settings, sessions, XP, collections or other snapshot fields.
- Added regression tests for owner/revision protection, exact order membership, unknown titles, serialization and input immutability.
- Fixed the previous milestone's Collections Dart analyzer error caused by duplicate wildcard parameters in image error callbacks.

## Crucial security and data integrity boundary

**A local revision check is NOT sufficient for safe cloud writes.** A second client could modify the account between fetching its revision and uploading a replacement snapshot. Before enabling any operation, the server must enforce a single atomic compare-and-swap against the expected `updated_at` or stronger revision token, with RLS owner enforcement. The current Flutter implementation intentionally has **no network write method** for proposals.

The original MediaFlow state is a large compressed per-user JSONB snapshot. Updating it without reproducing the website's atomic transaction and merge/recovery behavior risks losing unrelated changes. Do not simply add a Supabase `update` call to this simulator.

The current accepted status strings and edit fields are a **prototype**. They must be cross-checked against the v410 status/category rules before native writes are enabled. XP, task logging, history entries, backups and offline queues are explicitly out of scope here.

## Next

1. Audit the live website's cloud conflict prevention protocol and complete canonical status/priority mapping.
2. Build a tested server-side compare-and-swap RPC under an explicitly approved, reversible migration. Do not change the original Supabase backend without separate user approval.
3. Implement a durable encrypted/local queue, idempotency keys, crash recovery and conflict resolution.
4. Enable one low-risk native write at a time only after signed-in integration and recovery tests pass.

The original website/repository and Supabase database were not modified.
