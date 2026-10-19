# MediaFlowApp v1.0.0 Beta 8 — Real Cloud-Backed Advanced Logging Drafts

**Website reference:** personal MediaFlow v507.

## First real writable cloud feature in the native app

Native Advanced Logging now saves **unfinished drafts** in the existing MediaFlow Supabase account, separate from the website's original `mediaflow_states` record. This is real owner-scoped cloud storage, **not a simulation**, and it does not submit viewing/reading History, award XP or replace website Library data.

- Native app automatically restores a saved draft on opening Logging if its local editor is empty.
- Draft edits are automatically saved after a brief idle interval while the Logging screen is active; manual Save, Check Cloud, and Restore are provided.
- Preserve all selected titles, seasons, exact per-unit timestamps, per-unit runtimes, logging method, repeat flag, custom total runtime, notes, title order and Keep Titles.
- Validate the **whole** imported draft before applying any part of it, refusing invalid time values, duplicate title IDs, orphan durations and excessively large drafts.
- Two-device optimistic concurrency: each update compares the last read `revision` atomically in PostgreSQL; stale writes refuse to replace a newer draft. Manual overwrites require confirmation when separate local and cloud drafts exist.
- Cloud-unavailable or invalid payloads leave the local session untouched.
- App-wide cloud indicators and Settings distinguish full MediaFlow consumption/cloud mutation sync from this separate draft backup.

## Database safety

An **additive-only** migration installs `public.mediaflow_native_logging_drafts` on the connected personal MediaFlow project. `public.mediaflow_states`, accounts, Library, website History/XP data, the MediaFlow website and MediaFlow Plus are unchanged.

Verified live database: RLS enabled; 3 owner-scoped INSERT/SELECT/UPDATE policies; `anon` has no SELECT; the newly created draft table initially has zero rows. No privileged `service_role` key in Flutter. CAS conflicts never silently overwrite another device's draft.

## Known limitations

- This is a real cloud draft backup, **not complete bidirectional MediaFlow account synchronization**. Submitting finished logs and updating progress, History, XP, streaks and tasks remains blocked until website/native atomic full-state parity is validated.
- The editor's automatic timer runs while the Logging screen is open; rapidly exiting or killing the app before its save finishes may leave edits unsaved. Check the cloud status or use Save Draft before exiting.
- Unrelated settings, Library edits, order/collections mutations, Fresh Episodes provider runs and recovery writes are not enabled.
- Mobile OS build artifacts are previews: Android debug; Windows package; iOS unsigned developer archive requires signing.

## Validation

Flutter analysis/tests, source guard and Android/Windows builds are required in CI before merge. GitHub prerelease publication additionally requires an iOS unsigned build and uploaded packages.
