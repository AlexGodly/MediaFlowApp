# MediaFlowApp

Native Flutter application for Android, iOS, and Windows, based on MediaFlow web v410.

## Goals
- Reimplement the MediaFlow v410 interface and functionality in native Flutter (not WebView).
- Keep the original website and repository unchanged.
- Reuse existing Supabase accounts and user data without duplicating libraries.
- Preserve offline support, themes, import/export, logging, collections, statistics, and settings.
- Validate functionality against an explicit v410 parity inventory before production releases.

## Release policy
- Public tags and release names: `v410`, `v411`, etc.
- Each release includes changelogs and verified platform build artifacts.
- Android APK and Windows packages are distributed through GitHub Releases.
- iOS IPA requires macOS/Xcode and valid Apple signing/provisioning; installation/distribution depends on Apple rules.
- Do not publish a production release until required build and parity checks pass.

## Development status (milestone 05)
- Flutter adaptive shell and original-theme foundations committed.
- Existing Supabase authentication integrated using the same project's **publishable** configuration.
- Read-only Library implemented: gzip cloud snapshot decoding, filters, search, sorting, five layouts, details and pagination.
- Native read-only Dashboard and History screens now show signed-in account information directly from the same cached account snapshot.
- Account screen supports sign-out and password reset; native appearance selection persists locally per user.
- Native source tests cover history decoding, filtering, Dashboard/History widgets and Library search.
- Flutter Analyze and automated tests passed on GitHub Actions in the milestone 04 source-validation run. Milestone 05 has its own CI validation.
- Original MediaFlow website, repository and production database remain unchanged.
- No signed APK, Windows package or iOS IPA has been released. The remaining website features are not yet ported.

Source details: [Milestone 05](docs/MILESTONE_05.md), [Milestone 04](docs/MILESTONE_04.md) and [parity audit](docs/V410_PARITY_AUDIT.md).

Source: https://github.com/AlexGodly/MediaFlow (VERSION 410 verified on 2026-10-13).
