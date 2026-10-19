# Milestone 05 — Shared account snapshot, native Dashboard and History

Baseline: original MediaFlow web v410.
Repository: AlexGodly/MediaFlowApp.
Implementation: native Flutter widgets only, no WebView.
Database: untouched.

## Sources inspected

- src/js/core/state/002-state.js — top-level state keys.
- src/js/features/logging/008-session-flow.js — session schema, dates, quantities, XP, logged titles.
- src/js/pages/history/015-view-history.js — History date/category/result filtering.
- src/js/pages/dashboard/011-view-dashboard.js — daily goals, current task, recent progress.
- src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js — existing JSONB account snapshot and gzip envelope.

## Implemented

1. Decode sessions, currentTask, sessionActive, dailyMinutes and tasksPerDay alongside Library/categories from the same original compressed or plain JSONB snapshot.
2. Cache an authenticated, owner-scoped SELECT future and share it between Library, Dashboard and History. Explicit refresh downloads a new snapshot.
3. Dashboard read-only widgets: Library title counts, active/completed statuses, today's logged minutes/units, goals, active task/recommended title, recent sessions.
4. History read-only screen: search by logged title/note, category and status selectors, Today/7-day/30-day filter, pagination, session details.
5. Native account info, sign-out and password-reset email request, plus login reset link and signup password confirmation.
6. Persist native dark/light/AMOLED appearance preference on the local device per account.
7. Added unit/widget tests for compressed History/task decoding, dated filters and Dashboard/History widget interactions.

## Safety and limitations

- Still incomplete: task mutation, Logging submission, History edit/delete/undo/export, XP/streak parity, Collections, Personal Order, full Statistics/Settings, robust offline operation queue.
- Stored session XP is reported as stored; the website's complete progression algorithm is not reimplemented.
- App does not write to the website account snapshot; it does not overwrite Library, History or settings.
- Appearance preference is device-local and does not modify website cloud preferences.
- A refresh downloads the entire original compressed account snapshot, because that is the current data model.
- Unit/widget tests cannot prove signed-in live authentication or large 100k library performance.
- Password reset emails use the existing Supabase Auth URL configuration; native recovery deep links still need testing.
- No original MediaFlow repository edits, migrations, RLS changes or data writes.
- No signed/distributed APK, Windows or IPA release yet.

## Next

Audit v410 Collections/Statistics field semantics, implement their first read-only native pages, and establish a conflict-safe offline operation pipeline before enabling write actions. Add native Android/Windows/macOS CI build coverage and device testing.

See .github/workflows/native-ci.yml for source analyzer and test execution.
