# MediaFlowApp — Milestone 36: Native Dashboard Tools

**Scope:** Implement source-informed, useful, working **device-only** Dashboard utilities and review queues in actual Flutter widgets. Native task scheduling, rate/write-to-cloud, logging and XP submission remain intentionally disabled.

## Implemented

- **Stopwatch:** account-shell-scoped monotonic timer with Start / Pause / Reset. A lightweight 200 ms UI ticker exists only while the Dashboard tool is mounted and running. Paused time does not accumulate. The timer survives navigating away from Dashboard and back while the same authenticated shell remains alive; no timers persist to an unrelated account or across app restarts.
- **Runtime Calculator:** source-derived v256/v334/v335 carry-forward and multi-row modes; positive hours clamped to 99,999 and minutes/seconds clamped to 0–59; unlimited output-hour formatting; zero-row validation; count only non-zero runtimes; at least two multi-row inputs; continue with result; previous total; clear; original half-up seconds-to-minutes calculation. Result is **preview-only**—does not submit to the logging draft, History, XP, or Supabase.
- **Local review queues:** read-only Rate Your Library (unrated titles) and Missing Covers (empty-cover titles) queues on the native Dashboard, with category filtering, bounded rendered result lists, local Skip suggestion and navigation to Library. No rating, cover or account data is modified.
- **Responsive Flutter layout:** collapsible Stopwatch and Calculator cards, wrapping numeric inputs and action controls for narrow phones and desktop. Existing Dashboard stats, Next Task and recent History remain intact.
- **Lifecycle isolation:** tools owned by `MediaFlowShell`, which is keyed to the authenticated account; disposed on shell teardown and signout. Test-only standalone Dashboard owns and disposes its own controller. No automatic elapsed-time XP (v334) is awarded.
- **Test/CI:** deterministic v256 arithmetic and result-count fixtures, stopwatch start/pause/resume/reset, non-mutating read-only flags, narrow-screen widget flow and runtime interactions; static safety guard.

## Source provenance

Original `AlexGodly/MediaFlow` `src/js/components/190-v256-cover-sizing-runtime-calculator.js` implements `v256NormalizeTime`, `v256TimeToSeconds`, `v256CalculateRuntime`, `v256ContinueRuntimeResult`, `v256RestorePreviousRuntime` and both modes. v334/v335 add mode button icons and Dashboard semantics. This milestone reproduces core calculator and UI behavior without claiming pixel-perfect CSS/layout or undocumented provider integrations.

## Not implemented / acceptance still pending

- Stopwatch and runtime calculator persistence across app restart, hidden Dashboard settings toggles, and stopwatch transfer to existing logging draft are not enabled: do not invent History or XP changes.
- Rate Your Library's actual **rate/save and skip persistence**, Missing Covers assignment, On This Day/today balance, and the original v410 full Dashboard experience remain unfinished. Skip is strictly a local view preference.
- Mobile, tablet and Windows CI builds are development checks; no physical-device parity sign-off or production release. Existing sync restriction (legacy website direct full-state UPSERT) remains in force.
- Original MediaFlow website, MediaFlow Plus and production Supabase remain unchanged.

**Next:** Milestone 37 — native Library CRUD/parity foundations and safe local editing staging, still without cloud writes until all writers coordinate under an approved server CAS protocol.
