# MediaFlowApp — Milestone 31: Offline-First Read-Only Architecture

**Date:** 2026-10-14  
**Scope:** Real Flutter repository behavior, encrypted recovery and status UI.  
**Production cloud writing:** **DISABLED**. Website, Plus and production Supabase: **unchanged**.

## Implemented

1. **Single-owner coordinator:** `NativeOfflineReadCoordinator` is now used by the production Supabase read-only repository. It is injected with the existing authenticated SELECT, encrypted snapshot store and account-validity callback, rather than reinventing a second persistence mechanism. Cloud is authoritative.
2. **Encrypted offline recovery:** If cloud access fails transiently, it loads the latest verified AES-GCM local projection for **the same authenticated owner**. If the primary is corrupt, the existing store may recover its earlier verified generation. The visible source and device save date are explicit. Read-only device copies are **never** cloud revisions or upload sources.
3. **Memory-only fallback:** When no usable encrypted copy exists, a previously authenticated catalog already in this running session can remain viewable after a transient connection failure. The UI clearly calls this volatile, read-only memory (not a durable offline snapshot). No copy is fabricated when there has not been an authenticated successful read.
4. **Cloud corruption vs network failure:** Missing/invalid core account state, unsupported compression and malformed cloud payloads fail closed. They must not be silently masked with an older device copy and mistaken for current cloud data.
5. **Stale-request suppression:** In-flight reads after sign-out, owner changes, and superseding refreshes cannot replace a newer result or repopulate another account's active view. The same authenticated owner must be present before every result is accepted.
6. **Reconnect UX:** Explicit Refresh buttons continue to be the only retry trigger. When refreshing an offline view, the offline warning remains visible until a **verified** fresh cloud response replaces it. Dedicated `refreshing` state distinguishes a network attempt from source provenance.
7. **Deletion hygiene:** Cache clear and sign-out invalidate pending cache work; existing encrypted snapshot store serializes writes and deletion. Sign-out clears memory, encrypted current/previous/pending generations, and account-specific pending-review encryption keys.
8. **Tests and CI:** Synthetic cloud/network race scenarios, offline/previous-generation recovery, cloud revalidation, missing/invalid cloud rejection, memory fallback, foreign-owner invalidation, encrypted cache write failure, device copy clear and sign-out. Static guard checks production write gates and enforces no cloud mutation methods were introduced.

## Security and operational limits

- Native app **does not** write to Supabase, create new tables, run RPCs, queue offline cloud edits, or auto-sync. Sync migration in Milestone 30 must first cover every website and mobile/desktop writer.
- The encrypted device cache is still a **lossy read-only projection** of original v410 JSON; it is not a full-fidelity, restorable website backup.
- Authenticity of the local cache is established by its existing per-owner encryption and integrity checks; cache storage can become unavailable when the operating system keychain/keystore is locked or reset.
- A formerly cached in-memory view can remain displayed after manual local cache removal until leaving that view; it cannot be uploaded or treated as authoritative.
- Automatic connectivity monitoring, background retry jobs, offline editing and conflict-free merge/replay remain **disabled**. The offline-first guarantee is safe read-only viewing of previously loaded data, not unconditional offline access on first installation.
- CI and synthetic tests do not establish production Android/Windows/iOS device performance or Apple signing readiness. Real signed-in device smoke tests and source-to-native parity verification remain outstanding.

## Next: Milestone 32

Continue safe native workflow groundwork (local draft review and comprehensive cross-client submission safeguards) without enabling production cloud writes until a coordinated migration is approved.
