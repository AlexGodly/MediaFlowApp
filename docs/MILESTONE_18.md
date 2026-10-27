# MediaFlowApp — Milestone 18: Secure Offline Storage & Recovery

**Baseline:** MediaFlowApp Milestone 17, matching the read-only native projection of MediaFlow web v410.
**Cloud writes:** OFF. **Production Supabase / original MediaFlow / MediaFlow Plus:** untouched.

## Delivered

1. **Authenticated encryption:** device-local snapshot data is compressed and then encrypted using AES-256-GCM with a fresh random 96-bit nonce for every save. The authenticated data binds the snapshot envelope version, owner hash and save timestamp. Tampering with any of these fields or the encrypted contents prevents recovery. No personal Library titles or other projection fields are stored unencrypted in the snapshot document.
2. **OS-protected, per-account keys:** each owner's random 256-bit symmetric key is stored independently through the platform secure storage plugin (Android Keystore-backed storage, Apple Keychain, Windows OS-protected storage, subject to actual platform configuration). Keys are not written alongside snapshot payloads. A missing/unavailable/corrupt key fails closed; it is never replaced by a hard-coded application key.
3. **Recovery safeguards:** keeps two independently AEAD-verified generations, does not load an unfinished pending save, enforces compressed/file/expanded-size limits, and preserves the previous valid generation if the latest is unreadable. Access still requires the SDK to recognize the same signed-in identity. Offline content is not a cloud write source.
4. **Privacy-conscious upgrading:** Milestone 17 plaintext cache files for the authenticated account (current, previous, pending) are removed when reading/writing the new format. Old plaintext is NEVER displayed in offline fallback. The user needs one successful online refresh after upgrading to build a new encrypted cache. This is a deliberate security tradeoff; reconnect before relying on offline access.
5. **Recovery UX:** Settings > Offline recovery explains encryption, key loss, legacy cache invalidation, and clear actions. A local copy's saved timestamp is shown when it is being displayed. The existing app-wide offline/previous-generation banners remain in place.
6. **Sign-out and cache clearance:** deleting a signed-in owner's cache also deletes that owner's protected encryption key and that owner's legacy copies. The storage queue prevents an in-flight cache save from resurrecting data after a completed purge.
7. **Tests:** encryption roundtrip and restart, plaintext absence, account isolation, clear/key deletion, AEAD metadata/MAC/nonce tampering, lost key, locked secure storage, old cache cleanup, interrupted-save recovery, previous-generation fallback, write-clear ordering, and a synthetic 100,000-title encrypted persistence test.

## Trust boundaries and limits

- This is **encrypted local read-only recovery**, not an encrypted cloud backup, a shared key service, or production offline editing.
- Keys may be lost after application reinstallation, device restoration, an OS security change, or keychain resets. Encrypted cache files cannot be opened without their matching protected key. Reconnect to the original cloud account to rebuild the cache.
- OS secure-storage properties vary across Android, Windows and Apple devices. This feature does not claim that all device keys are hardware-backed, biometric-protected or export-proof.
- Metadata such as a one-way owner hash, encrypted cache format and saved timestamp remains visible in the local file. Account projection contents are encrypted.
- Cache encryption is not a substitute for device encryption, login security, or the website's existing cloud backup/export functionality.
- The current app's authenticated Supabase SELECT is still the only way to refresh the source data. **No native INSERT/UPDATE/DELETE/RPC, local write queue, automatic cloud replay, schema migration, RLS change, or user-data copy** was introduced.
- Flutter automated synthetic tests do not prove 100,000-title performance on production Android or Windows devices. Runtime secure-store behavior and true cold-start UX require signed-in device testing.
- Android and Windows GitHub build verification is separate from Flutter analyze/tests; passing a CI build is not equivalent to user-facing production readiness. iOS release requires Apple-specific signing/testing and keychain capability review.

## Suggested manual acceptance matrix

1. Sign in online and allow one cloud read to finish. Restart offline with the same signed-in session; expect a read-only offline banner and intact Library/History counts.
2. Return online and refresh; expect cloud source, no offline banner and encrypted local persistence.
3. With two encrypted generations, damage the newest current file on a development device; expect the previous one and an explicit recovered-previous warning.
4. Sign out; verify account-specific cache files and the matching device-protected key are gone. Sign in with a different account and confirm no access to the earlier identity's Library.
5. Lock or reset the device secure-storage backend in a test environment; encrypted cache cannot be read without its key, and the app must not silently present a blank account as authoritative.

## Next

Milestone 19 should tackle a server-enforced, cross-client versioned write protocol coordinated with the original website. It cannot safely enable native cloud editing while the website can still perform unconditional full-state UPSERTs. Keep the native write capability flag off until all writers have the same conflict rules.
