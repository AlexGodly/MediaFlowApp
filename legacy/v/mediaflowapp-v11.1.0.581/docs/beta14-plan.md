# Beta 14 — working plan (owner decision: everything in ONE release)

Living checklist kept in the repo so work survives across sessions. Tick items as
they land on branch `flutter-beta14`; release only when everything is done.

## Decisions (owner, or defaults the owner was told about on 2026-10-31)

- One release containing everything below.
- Offline-first for everything: every change is saved on the device and replayed
  on the newest cloud copy (CAS on `updated_at`). Conflicts: **newest change
  wins**; changes to different fields/titles are always both kept; logs never
  lost or duplicated.
- Navigation: bottom bar Log · Library · History · Extras · More (Collections,
  Personal Order, Statistics, Settings, Account). Wide screens: side rail with all.
- Log form: long recommended title on its own line; heading "Titles"; Advanced
  title tabs use website wording (Per Unit / Progress Reached / Amount Consumed);
  Reached/Amount apply on leaving the field (no Apply button); Save stays visible
  when the workspace is collapsed; XP preview above Save; no Collapse All.
- "+" button: Add titles / Save & get next task (one-tap confirm showing XP total).
  No form open → Add titles opens the form for the current task; no session →
  Batch Log.
- Rate Your Library and Missing Covers are part of the Library.
- App settings: start tab, theme, sync options, storage, reminders, stopwatch
  options, update check, Windows start-up/tray, diagnostics.
- Permanent Android signing key (GitHub secret).

## Areas

### 0. Foundation
- [x] Navigation (bottom bar + More + side rail)
- [x] Generic replayable edit ops with newest-wins field merge
- [x] Offline sign-in robustness (expired token while offline keeps the app usable)
- [x] Cover image cache
- [x] Permanent Android signing key

### 1. Log tab (items 1–10)
- [x] Quick / Advanced label, recommended title cover + own line, "Titles"
- [x] Covers on every added title (Quick rows + Advanced cards)
- [x] "+" button: Add titles / Save & get next task
- [x] Logging Library (search, category/status/priority filters, picker sorts,
      direction, shuffle, page size + paging, 5 layouts, multi-select + bulk add,
      already-added marks, add recommended title, new title) — state in
      `resumeStateV285.logging.ui`
- [x] Arrange added titles (`logDraft.v373Ordering`, 13 sorts, custom drag, random)
- [x] Collapse: per title (`v369Collapsed` / `v379QuickCollapsed`), Hide Added
      Titles (`v379HideAddedTitles`), Logging Workspace (`settings.v419LoggingCollapsed`),
      last-40 units + Show all (`v369ShowAll`)
- [x] XP preview card (trial save)
- [x] Website tab wording; apply on blur

### 2. Library (complete) ✓
### 3. History (complete) + Library History + XP History + undo/redo ✓
### 4. Collections + Personal Order ✓
### 5. Statistics (27 sections) + Extras (Stopwatch, Runtime Calculator, Today's Balance, On This Day) ✓
### 6. Settings (website + app) ✓ — reminders and Windows start-up/tray deferred (need system plugins)
### 7. Verify offline, release


Status 2026-11-01: all areas landed; website goldens for title edit/add, History delete, Collections and Personal Order pass. Android permanent key waits for the two repository secrets.
