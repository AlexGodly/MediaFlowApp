# MediaFlowApp Android v1.0.0 Beta 10 — MediaFlow v553 Offline Sync and Draft Safety

**Frontend:** Official MediaFlow v553 Stable archive, pinned by SHA-256.
**Android host:** Kotlin + locally bundled Android System WebView.
**Focused surfaces:** Recommendations, Log, Library workspace, and Log history.
**Supabase:** Existing authenticated `public.mediaflow_states` row only. No schema migration, new table, policy, secret, or alternate account data model.
**Archive:** `legacy/v/android-webview-v1.0.0-beta.10/`.

## Preserved v553 functionality

The APK continues to run the actual v553 frontend and its canonical application functions, not a parallel recommender or XP calculator:

- Category rotation, recommended titles, exact-title recommendations, title rerolls, and reroll history.
- Quick, Advanced, and Progress logging modes; single and batch logging; per-unit selection, timestamps, notes, runtimes, and supported progress methods.
- Canonical XP reward preview and v553 amount-scaled reroll-title XP, credited by the real submission flow only after successful logging.
- The existing Library workspace and Log history, including the same authenticated account state.

## Offline-first account and draft continuity

- Reads the previously stored Supabase auth identity when connectivity prevents session restoration. A prior successful account can open its local workspace and continue drafting without a network connection or a forced sign-in screen.
- Keeps full account snapshots in IndexedDB, with the existing account-scoped recovery cache as fallback.
- Saves unfinished single and batch Logging forms locally and synchronizes eligible draft snapshots to the existing cloud row using the namespaced `__mfAndroidCompanionDraftV1` JSON field. No additional Supabase table is created.
- Completed offline logs and other account-state changes remain in the account-scoped queue. On reconnect, the app attempts session refresh and synchronizes while the app is active.
- If authentication has genuinely expired or been revoked, cloud submission requires reauthentication once a connection is available. Local drafts and queued state remain on the phone.

## Safer cloud writes and conflicts

- Replaces the Android companion's unconditional full-state UPSERT with a compare-and-swap update against the existing `updated_at` value.
- Reads the current cloud version before updating. If another save wins the race, the app re-reads and retries a bounded merge. It refuses unconditional writes and does not silently create a missing row when local changes are pending.
- Uses a three-way merge for settings and other scalar account fields where a previous cloud baseline is available. Independent Library titles, History sessions, activity, completion timeline and XP ledger entries are merged using the v553 data model.
- When the phone and cloud changed the same settings/task field, an in-app themed dialog lets the user choose which conflicting values to keep. Both copies remain local/cloud until the choice is made; no JavaScript alert is used.
- Cloud draft conflicts similarly offer “Keep this phone's draft” or “Restore the cloud draft here”. The local draft is not overwritten silently.
- Account ID is rechecked before and after cloud writes. An account switch aborts the pending write.

## Database impact

**No Supabase schema changes are included in Beta 10.** The earlier `mediaflow_native_logging_drafts` table remains deleted. This release uses the existing `mediaflow_states` table and its existing RLS policies through the authenticated Supabase client. It does not use a service-role key or write to MediaFlow Plus.

The draft extension lives inside the existing JSON state row. The website itself is unchanged and may omit this Android-specific field on its own subsequent saves; the app retains the phone's local draft and re-synchronizes it on a later active connection.

## Validation

CI checks the pinned v553 package contracts, archive integrity, Android package generation, JavaScript syntax, compare-and-swap behavior, stale-version rejection, account fencing, insert-if-absent behavior, and Android compilation. The APK is debug-signed for testing.

**Physical-device validation is still required** for airplane-mode startup, a genuine network loss while Android reports online, offline single/batch submission, app termination during a draft save, reconnect after token expiry, cross-device conflict choices, and long sessions with large libraries. Android background sync runs only while the app is active; this is not an Android background-service guarantee.
