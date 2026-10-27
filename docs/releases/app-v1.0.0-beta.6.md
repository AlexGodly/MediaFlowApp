# MediaFlowApp v1.0.0 Beta 6 — Website-style Native Workspace

**Website reference:** MediaFlow v507 Stable (October 18, 2026).

## Why Beta 6 exists
The earlier Fresh Start beta removed most pages and did not meet the owner's intent. This release restores the original native Flutter workspace and uses the actual MediaFlow website screenshots/design as the primary UI reference. **No WebView is used.**

## Restored native sections
Dashboard, Library, Logging (Advanced Logging), Personal Order, Collections, History, Statistics, Account and Settings; their existing Flutter implementations and all connected read-only data flows are back. Old Beta 5's native Logging picker, exact-ID recommendation queue and local per-unit logging drafts return.

## Added native sections
- **Old System:** Real category consumption/Library-progress overview and logs-by-category using the signed-in account snapshot.
- **Background Processes:** Read-only missing-cover and missing-external-ID diagnostics, search/filter/pagination and useful Copy Diagnostic Summary.
- **Fresh Episodes:** Real incomplete Library candidates, searchable and paginated. Clearly labels them as **unverified**; no fabricated release counts or dates.
- **Theme Studio:** Immediate native Dark/Light/AMOLED appearance controls and design palette previews; the website-only Advanced/Custom/Living Theme generation is identified as not yet ported.
- **About:** Native app credits, supported snapshot data and website version source.

## Website-oriented design improvements
- Desktop: full-height persistent MediaFlow sidebar, selected gold accent bar, section-specific header with a functional **Sync Now** account refresh.
- At 1080 logical pixels and below: mobile bottom navigation with an accessible More sheet; desktop sidebar activates from 1081 pixels.
- Shared navy surfaces/gold accents, card borders, serif headers, coherent corner radii and meaningful icons match core MediaFlow website visual vocabulary.
- Responsive layout built in **Flutter widgets**, not by embedding the website.
- Keeps the original native authentication, saved account session, state decoding, Data Health diagnostics and fail-closed read behavior.

## Explicit limits
This is **not yet 1:1 operational website parity**. Website-only engines (live Fresh Episodes providers, background cover repair writes, complete theme generation, automatic export/import, XP/history cloud updates) require native implementations. Logging editing/drafts remain local; submitting them to production MediaFlow cloud is **disabled** while the website's single-snapshot atomic synchronization and XP/History side effects are unverified. The personal website and Supabase account are not modified.

## Validation and distributables
Flutter analyze, Flutter automated tests, existing safety/source guards, Android debug APK, Windows x64 package and unsigned iOS developer IPA must all pass CI before GitHub prerelease publication. The unsigned iOS archive is not installable on a regular iPhone without provisioning/signing.

## Archived versions
- Prior full native state: `archive/beta5-before-rewrite`
- Fresh-start minimal beta: `archive/fresh-start-before-full-restoration`
