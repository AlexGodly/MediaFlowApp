# MediaFlow v410 native parity inventory

Source: `AlexGodly/MediaFlow`, `main`, VERSION=410 (verified 2026-10-13). This is a source-documentation inventory, **not** completed parity testing.

## Functional domains (all pending native implementation and verification)

| Domain | Required behaviors | Status |
|---|---|---|
| Authentication | Existing Supabase sign-in, sessions, account isolation | Pending |
| Dashboard | Next Task, recommendation, daily balance, task-progress dock, quick-action sheet, stopwatch, runtime calculator, rating and missing-cover utilities | Pending |
| Library | CRUD, categories, status, priority, ratings, dates, metadata, seasons, five display modes, Normal/Dynamic layouts, filters, sort, pagination, bulk actions, title details | Pending |
| Logging | Quick, Advanced Per Unit/Last Watched/Amount Consumed, season support, per-unit timestamps, draft preservation, submit to History and XP | Pending |
| Collections | CRUD, searchable multi-select picker, direct add, responsive views, filtering | Pending |
| Personal Order | Category queues, title/collection assignment, drag/arrow/numeric reordering, multi-select pickers, import/export | Pending |
| History | Sessions, units, dates, runtime, filtering, pagination, exports, management | Pending |
| Statistics and progression | Statistics, XP, levels, streaks, achievements, daily activity | Pending |
| Settings | Themes, dynamic cover modes, navigation, categories, icons, visibility, sizing, preferences, presets | Pending |
| Data management | Supabase sync, offline cache and edits, conflict handling, full/automatic backups, import/export, Sync Now | Pending |
| Platform | Android/iOS/Windows adaptive navigation, keyboard/mouse/touch, file picker/share, accessibility, update experience | Pending |

## Critical behavioral constraints

- **Never write to or alter the original MediaFlow repository as part of this migration.**
- **Do not create a second Supabase copy of each user's library.** Use existing authorized records and schema.
- Do not claim offline sign-in or instant synchronization; model offline operations and reconciliation explicitly.
- Logging drafts must not create History/XP before submission.
- MAL/SIMKL file import support is distinct from canceled live account tracking.
- v410 mobile quick actions: compact dock row and bounded full-width quick-action sheet; desktop remains separate.
- The native app must be a real Flutter widget implementation, not a WebView.

## Required audit expansion before parity sign-off

1. Enumerate every runtime page/component, setting key, and persistent entity from active v410 build manifests and source.
2. Capture screen reference states for light/dark/dynamic themes at phone/tablet/desktop breakpoints.
3. Record exact Supabase schema, RLS policies, cloud merge and backup format contracts without exposing credentials.
4. Build an interaction-by-interaction test matrix, including empty, large, offline, and conflict states.
5. Verify each feature with automated tests and device testing. No percentage parity claims until measured.
