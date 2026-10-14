# MediaFlowApp — Milestone 17: Offline Architecture & Synchronization Safety

**Reference:** original MediaFlow website v410. **Native cloud writes:** disabled. **Original repositories and production Supabase:** unchanged.

## Delivered

1. **Device-local, read-only recovery.** A successful authenticated read of the existing owner-scoped cloud row produces a minimal Flutter projection of Library, History, Collections, Personal Order, categories, and Dashboard/task fields. Only that projection is cached, not the complete v410 state, hidden website metadata, authentication secrets, or a cloud-write payload.
2. **Account isolation.** A SHA-256-derived per-account file namespace plus an owner hash in the cache envelope prevents another signed-in identity from loading an unrelated snapshot. Each repository rechecks the current identity after network and disk awaits; the Flutter shell is keyed by auth identity, avoiding old account state being reused when switching users.
3. **Crash-safe two-generation storage.** Device cache files are stored under the application's private support directory. A flushed temporary file is renamed into place, with the previous validated generation retained separately. Damaged/truncated/incompatible files fail closed; when the current generation is unreadable the previous valid generation may be recovered. Leftover pending files are not treated as committed snapshots. Cache writes and purges are serialized, so an in-flight save cannot recreate a copy after a completed sign-out purge.
4. **Explicit offline status.** The native UI shows an offline/recovered-previous warning banner on all pages when displaying a device copy. Settings > Offline recovery offers refresh and a confirmed Clear device copy action. Clear does not delete cloud records or replace the current in-memory page.
5. **Failures are non-destructive.** A failed refresh does not overwrite a valid cache with an empty snapshot. Missing cloud rows and malformed snapshot data are not silently treated as an empty authoritative account. A cache cannot be used by unsigned-in users and is never an editing/synchronization source.
6. **Performance and tests.** Cache serialization and expansion use Flutter compute isolates rather than blocking the UI thread. Tests cover projection round trips, account separation, clearing, checksum/owner tampering, corrupt-primary recovery, ignored temporary files, serialized purge behavior, and a synthetic 100,000-title save/reload.

## Safety boundaries

- Native cloud-write capability: **OFF**. Existing Supabase access is SELECT-only in this repository.
- Offline editing, offline write replay, automatic cloud synchronization, database migrations, conflict-resolution RPCs, cloud backup restoration, and copying account data into shared tables: **NOT implemented**.
- The device projection cannot reconstruct the entire v410 account state and is intentionally ineligible as a source for cloud mutations.
- Cache checksums provide **accidental corruption detection, not cryptographic authentication or encryption**. The cache is compressed and stored in the OS app-private support folder, **but is not encrypted at rest**; device/OS access restrictions still matter. Do not use this as the sole secure backup.
- Read-only offline recovery requires an authenticated session that the Supabase SDK still recognizes locally. Signed-out users cannot browse cached snapshots. Explicit native sign-out purges the current account's local copies; OS-level app uninstall also removes app-private files.
- Crash recovery provides two local generations, not guaranteed durability against disk/OS failure. Local projections may be stale. A fresh, successfully decoded cloud response is the authoritative read when connectivity returns.
- 100,000-title testing is synthetic and is not a real Android/Windows performance certification.

## Validation

Flutter analyze, automated tests, and Android/Windows build validation are run by GitHub Actions on the Milestone 17 commits. Consult the linked workflow runs for final pass/fail status; a test file existing does not establish a passing platform build.

## Next

Milestone 18 should focus on encrypted-at-rest local persistence and a realistic recovery/UX audit, then a separately reviewed cross-client atomic cloud-write design. Cloud editing must remain disabled until the original website and all native clients implement compatible server-enforced conflict checks.
