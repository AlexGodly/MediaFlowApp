# Milestone 06 — Collections, Statistics and platform build checks

**Baseline:** Original MediaFlow website v410  
**Target:** AlexGodly/MediaFlowApp (native Flutter, no WebView)  
**Data:** Existing authenticated Supabase account snapshot, read-only

## Delivered

- Projected v274+ `collections` from the existing compressed JSONB state, preserving ordered title references, descriptions and collection covers.
- Native Collections browser with search, collection detail, resolved Library titles, progress percentage and cloud refresh.
- Native Statistics: today/7-day/30-day session totals, consumption units, weekly category balance, lifetime minutes, daily average and session completion percentage.
- Connected both pages to the same memoized, authenticated snapshot as Library, Dashboard and History.
- Collection ordering and progress unit tests.
- Android debug APK and Windows release build workflows that publish CI artifacts when successful.

## Fidelity notes

Collections progress follows the v274 weighted-progress algorithm: sum of bounded progress / known totals, or completion fraction when no totals are known. Missing Library title references remain part of the saved membership but are not rendered as fabricated Library items.

Statistics totals exclude skipped sessions, consistent with the web helper `totalsForSessions`. The current native Statistics screen does not yet implement the full website's saturation, category-health, records, XP, streak or timeline systems.

These are read-only implementations. No cloud writes, collection modifications, statistics resets, Supabase migrations or changes to the original MediaFlow repo have been performed.

## Build scope

`.github/workflows/native-builds.yml` builds an **Android debug APK** and **Windows release binaries** as GitHub Actions artifacts. They are validation builds, not signed or published releases. Android production signing, Windows packaging, iOS/macOS Apple signing and actual device parity testing remain outstanding.

## Next milestone

Native Personal Order and Logging read-only inspection, then a conflict-safe write protocol with version-aware optimistic concurrency and recovery. Test real authenticated data and performance with large accounts before enabling mutations.
