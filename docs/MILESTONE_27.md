# MediaFlowApp — Milestone 27: Native Design System

**Date:** 2026-10-14  
**Source:** Personal MediaFlow v410 (read-only source comparisons).  
**Scope:** Flutter-only visual foundations. Website / MediaFlow Plus / production Supabase unchanged.

## Delivered

- Source-pinned base colors from `legacy/v/410/assets/css/00-foundation.css`: dark, light, AMOLED; semantic state colors; borders; raised panels and text contrast.
- Typed `MediaFlowTokens` ThemeExtension with interpolation/copy, plus shared spacing (4/8/12/16/20/24/32), radii (6/12/20), and adaptive breakpoint contract.
- Consistent native Material component styling across screen scaffolds: cards, forms, focus outlines, chips, buttons, dialogs, sheets, popup menus, progress indicators, navigation, snackbars and tooltips.
- Reusable UI primitives: `MfPanel`, `MfPageHeader`, `MfBadge`, `MfEmptyState`, `MfNavigationTile`, `showMfAdaptiveDialog`. These own **presentation only**, never mutations.
- Desktop sidebar with active accents and keyboard-accessible InkWell links, intermediate-size rail, phone bottom navigation with More sheet. Replaced older desktop >=1100 threshold with the source-backed >=1081 breakpoint.
- Dashboard, Library and Settings now consume reusable design-system primitives rather than duplicating their page headers and panels.
- Theme and navigation widget tests for tokens, light/AMOLED rendering, responsive thresholds, navigation, and appearance selection.

## Comparison notes and visual acceptance gaps

| v410 source reference | Flutter mapping | Status |
| --- | --- | --- |
| `assets/css/00-foundation.css` root variables | `MediaFlowTokens` palettes | Token values implemented and unit-tested |
| `assets/css/142-v277-navigation-breakpoint-fix.css` | `MediaFlowBreakpoints.desktop` | Navigation breakpoint verified in widget test |
| Desktop sidebar | `MfNavigationTile`, native shell | Functional baseline, screenshot parity **pending** |
| Tablet/phone navigation | Rail, bottom tabs and More sheet | Native adaptation, screenshot parity **pending** |
| Site forms/cards/popups | `ThemeData` + reusable primitives | Shared treatment, screen-by-screen parity **pending** |
| Website Manrope/Fraunces typefaces | Platform font fallback | **Not equivalent** until legally distributable font assets are bundled |
| All custom / cover-derived site themes | Device-local 3 base appearances | **Not implemented**; Milestone 49 |
| All 307 feature behaviors | Source feature inventory | **Not validated** by this visual milestone |

### Required future visual fixtures

Capture **actual v410** browser screenshots at phone (360×780), compact phone (390×844), tablet (820×1180), and Windows desktop (1440×900), for Dark/Light/AMOLED and empty/populated/offline states. Create corresponding Flutter captures and compare screenshot diffs with agreed tolerances. Historical v398/v400 screenshots are not v410 acceptance fixtures. Font bundling, dynamic themes, dialog-specific parity and platform screenshots still require work.

### Safety

There are no new cloud writes, schema changes or restore operations. All existing read-only/offline rules remain. This is a component foundation, **not a claim of complete UI parity**. The 307 feature entries remain unverified until actual functionality is proven.

## Next

**Milestone 28 — Full Data Model Compatibility:** preserve unknown fields and nested v410 state in round-trip models and tests, without enabling unsafe writes.
