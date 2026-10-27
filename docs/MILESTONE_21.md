# MediaFlowApp — Milestone 21: Source-Grounded Logging, History & XP Previews

**Baseline:** Milestone 20, original MediaFlow v410 read-only source. **Cloud writes and automatic offline sync:** disabled.
**Scope:** AlexGodly/MediaFlowApp only. **Original MediaFlow, MediaFlow Plus, production Supabase:** untouched.

## Source audit

The following original MediaFlow source files were inspected in the separate original repository **read-only**:

- `src/js/features/logging/008-session-flow.js` — `submitLog`, repetition vs Library progress, session grouping, `partial`/`over`/`complete`, completion timeline and skipped recommendation handling.
- `src/js/features/logging/098-v179-dual-logging-modes.js` — `v179StartProgress`, `v179ClampEndProgress`, `v179CalculatedQty` (last progress / amount consumed).
- `src/js/features/xp/037-v120-completion-xp-progression-integrity.js` — `v120IsCompleted`, one-time logged completion XP ledger and configured rates.
- `src/js/features/xp/054-v149-day-streak-xp-multiplier.js` — date-key selection, skipped-session exclusion, consecutive-day map and two-decimal multiplier `1 + 0.10 × log2(streak)`.
- `src/js/components/267-v369-itemized-logging.js` — contiguous unit-number progress, repeat exclusion, season ID requirements and archived unit evidence.
- `src/js/components/288-v394-advanced-logging.js` — exact consecutive units, season selection, per-entry runtime and mixed timestamps.
- `src/js/components/245-v348-universal-streak-action-xp.js` — configured/conditional global action XP multiplier and additional ledger.

The deployed v410 bundle includes later overrides; these isolated source functions and fixture tests do **not** constitute full, executed v410 parity verification. The native app intentionally refuses to fabricate the portions whose required data or algorithms have not been fully verified.

## Delivered

1. **Last-progress input** in the native Logging draft form alongside Amount Consumed. The projected quantity is nonnegative final progress minus current progress; completed titles begin rewatch/reread from zero. Last-progress input is clamped to known title totals, matching the audited v179 helper.
2. **Repeat consumption mode**, explicitly selectable for already completed titles. History units and minutes are shown hypothetically, while Library progress remains unchanged. The preview refuses invalid repeat use and does not create fake repeat achievements or XP.
3. **Completion transitions preview** for non-repeat logging. It identifies when a title would reach its total and tentatively displays the next status, but never mutates real statuses, completion timeline or ledgers. Dropped titles remain dropped.
4. **Historical-day streak diagnostic** using existing typed read-only History sessions: exclude skipped sessions, use stored YYYY-MM-DD before timestamp fallback, deduplicate same-day activity, compute consecutive days and show the audited v149 formula. Actual XP applies additional account settings and later multipliers; the displayed multiplier is *illustrative*, not a guaranteed payout.
5. **Contiguous unit-number arithmetic** as an independently tested pure function, stopping at the first missing unit, respecting totals and ignoring duplicates. Full itemized/season submission remains blocked because the native projection does not carry stable season IDs, the entire archived v369 unit record history, or the exact per-unit timestamp/duration semantics.
6. **Read-only hypothetical History shape** for a title/date/quantity/minutes/note/repeat. It is explicitly not a complete v410 session, supplies no IDs or XP values, and cannot be submitted as a cloud-write payload.
7. **Shared M20 draft integration**: store logging mode, repeat status, the calculated quantity, projected progress/status, possible completion and provisional streak information in the signed-in, RAM-only workspace. Settings exposes the draft mode and expected streak; drafts are discarded on sign-out.
8. **Fixture-based automated tests** for v179, legacy v81 repeat semantics, v120 completion recognition, v149 streak multiplier/date calculation, v369 contiguous unit behavior, season fail-closed behavior, M20 draft coupling and native form visibility.

## Not implemented / safeguards

- No session IDs, actual History insertion, XP grants, XP ledger writes, global level or streak persistence, completion timeline, auto-generated tasks, cloud modifications, imports or write replays.
- No exact configured XP amount: full leveling/category settings and action/XP ledgers are absent from the intentionally lossy native device catalog; showing invented XP would misrepresent the website.
- No exact v410 advanced per-unit, mixed timestamp, per-season, task-followed/not-followed, XP or batch transaction parity. No production saving is enabled by the hypothetical preview.
- The original website still uses unconditional full-state writes; any future native saving requires all writers to coordinate a database-enforced atomic CAS protocol and side-effect parity, as documented in Milestones 19 and 20.
- The synthetic fixtures verify the documented rule examples but are not differential tests against a running v410 browser, nor certification of 100K-title device performance.

## Validation

Flutter analyze and tests run on the milestone branch and merged `main`. Android debug and Windows builds run on `main`; consult GitHub Actions for actual results. Android and Windows validation builds are not production-signed releases.

## Next

Milestone 22: verify v410 advanced itemized/season model against real source/runtime fixtures, carry stable season/unit fields into read-only typed projections, and expand safe local-only previews. Actual cloud editing remains gated on cross-client transactional safety.