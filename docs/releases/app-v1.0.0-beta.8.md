# MediaFlowApp Flutter v553 Native Foundation — Beta 8 (development branch)

This is a development milestone, not a published or release-ready app.

## Included in this branch

- Restores the existing Flutter application, native screens, source guards, and automated tests from the preserved Flutter workspace.
- Sets the target website contract to personal MediaFlow v553 Stable.
- Adds a pure Dart port of the v553 reroll-title XP projection, including configured per-unit XP, category rotation, day-streak rounding, exclusion of the initial recommendation, and itemized unit counting.
- Adds regression tests based on the website's v553 contract vectors.

## Not yet complete

- This does not claim full v553 recommendation parity.
- The native Logging draft and successful-submit flow still need to be connected to this projection.
- Native History and XP award commits and production bidirectional sync remain disabled until transaction and conflict safety are proven.
- No Supabase schema or policy changes are included.

## Validation

Flutter CI runs analysis, regression tests, Android debug build validation, and Windows build validation. A successful CI run is required before this branch is considered ready for merge or release.
