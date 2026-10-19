# MediaFlowApp — Milestone 10: Local draft journal and conflict lab

**Baseline:** original MediaFlow v410. **Production write capability:** OFF.

## Implemented
- A new account-scoped, **memory-only** `NativeDraftJournal` stores immutable local edit proposals with unique operation IDs, consistent base revisions, explicit discard/clear operations and defensive account checks.
- Multi-proposal previews are copy-on-write and all-or-nothing: each proposal is validated against the preceding proposed snapshot, but the resulting CAS plan still references the **single original cloud row**. A failed intermediate step blocks the entire batch.
- A changed cloud revision **quarantines** the batch; there is no automatic rebase, retry or last-writer-wins behavior.
- Drafts have an explicit versioned JSON serialization format, validated for account identity and capped at 1,000 entries. This is **not** an automatic persistence layer, encryption mechanism, or a cloud import feature.
- A Settings **Offline draft safety lab** uses only synthetic demo titles and lets the user stage a priority change, preview its effect, simulate another device changing the revision, and discard drafts. It never touches real account data.
- Added tests for all-or-nothing previews, conflict detection, cross-account rejection, duplicate operation IDs, import account checks, no-op detection, and UI interactions.

## Safety boundaries
- No production SQL, Supabase table, RLS policy, edge function or user account data changed.
- No modifications to the original MediaFlow website or MediaFlow Plus.
- Native cloud writes remain disabled. There is no cloud replay, background task, durable encrypted journal, or live account editing.
- Drafts exist in memory only and disappear when the journal is disposed or the app restarts. The lab is explicitly **synthetic** and is not a working offline edit queue.
- The Milestone 9 CAS draft remains review-only. Original v410 website writes still bypass CAS.

## Next
- Complete real native read-only feature parity, verify native builds, and benchmark large libraries.
- To implement durable offline editing later: encrypted per-account storage, authenticated account-key lifecycle, atomic journal writes, recovery after crashes, durable operation IDs and reconciliation of ambiguous server results, plus a shared server-enforced transaction protocol for every writer.
