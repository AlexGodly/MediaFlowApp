# MediaFlowApp v1.0.0 Beta 5 — Complete Advanced Logging Workspace Pass

Based on the latest personal **MediaFlow v505 Stable** (v504 logging engine + v505 responsive menu fix). Native Flutter, following the interactive R2 design direction.

## Added to native Logging
- Full MediaFlow recommendation browser: saved exact-ID task and additional bounded Personal Order queue suggestions, including queue search, category and already-added filters. Secondary queue entries are correctly labeled previews, never live generated recommendations.
- Full Library picker experience: **List, Compact, Cards, Covers, Covers + Titles**, multi-selection, Select Visible, Clear Selection, Add Selected, Show All / Not Added / Already Added, category/status/priority filters, 12 sort choices, pagination, per-page adjustment, cover-size slider, responsive small-screen controls and safe category-icon fallback artwork.
- Prevent ambiguous or duplicate Library IDs from being selected via the enhanced picker.
- Advanced Logging remains default, with **Per Unit**, **Last Watched/Read Unit** and **Amount Consumed**, each title retaining its own method and draft.
- Per Unit: selectable unit grid in 30-unit pages, up to 2,000 units per season, Add Next, Remove Last, Clear Season, individual Logged At timestamp editor and per-unit duration in seconds.
- Amount/Last Unit: v504 quantity steppers and numeric editing, accurate seasonal bounds, and explicit confirmation before replacing sparse unit selections, distinct timestamps or custom per-unit runtimes.
- Season-aware per-unit selections and timestamps survive method and season switches.
- Repeat/rewatch uses its own zero-based selection, without falsely advancing Library progress.
- Preview progress now follows MediaFlow's contiguous-unit rule: skipped or nonconsecutive units still count as consumed, but cannot auto-complete skipped progress.
- Per-title runtime: per-unit default minutes, individual duration overrides, and optional manual total runtime.
- Improved added-title cards with cover/category fallback, title metadata, progress preview, notes, reorder controls and removal.
- Session organization with sorting options and direction; draft review and clear confirmation remain intact.

## Safety
- **This is a full visual/workflow feature pass, not a real History/XP/cloud logging submission.** Production writes stay disabled. The website's concurrent data writes still need a compatible, tested cross-client transaction strategy.
- Library is authenticated/read-only, and draft changes live only in this app session.
- App still does not claim complete MediaFlow v505 UI/settings/provider parity.
- Source MediaFlow website, MediaFlow Plus, and production Supabase are unchanged.

## Validation / distributables
- Native regression tests for gaps, repeat, seasons, timestamps, per-unit runtimes, quantities, ordering and no-write behavior.
- GitHub Actions validates Flutter and the existing source guards, then builds Android debug-signed APK, Windows x64 ZIP, and **unsigned** iOS IPA.
- An unsigned iOS archive is not installable on a normal iPhone; Apple Developer signing/provisioning is still needed.
- Build links are available only after the full release workflow succeeds.
