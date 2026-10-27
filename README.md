# MediaFlowApp

**Native Flutter app for MediaFlow by Alex Godly. Target source: personal MediaFlow v553 Stable.**

The active app is being rebuilt in Flutter/Dart for Android first, with iOS and Windows kept buildable from the same codebase. It must not embed the MediaFlow website in a WebView.

## Current state

This branch reactivates the preserved native Flutter workspace and starts the v553 parity port. The earlier Android WebView Beta 10 artifact is historical and is not the target implementation.

- Native Flutter screens and the existing Supabase Auth/read-only account snapshot path are restored from the preserved Flutter Beta 7 source.
- A source-backed v553 reroll-title XP projection is being ported with regression cases for per-unit XP, category rotation, day-streak rounding, exclusion of the initial recommendation, and itemized unit counts.
- The app is **not yet feature-complete or release-ready**. The native recommendation engine, full Logging submission, History/XP commit parity, and safe bidirectional account sync still require implementation and validation before a usable release is claimed.
- Production cloud writes remain disabled until the app can preserve the full existing account payload and prove conflict-safe compatibility with the website.
- No Supabase schema, table, policy, secret, or account model changes are part of this work.

## Source of truth

The website source is [AlexGodly/MediaFlow](https://github.com/AlexGodly/MediaFlow), currently v553. Flutter logic must be checked against that version's real recommendation, logging, and XP behavior rather than approximated from old screenshots or a previous app build.

## Development

The Flutter project lives at the repository root:

- `lib/`: native application and domain code
- `test/`: Dart regression and widget tests
- `tool/parity/`: source-contract and safety guards
- `docs/`: parity notes and milestone evidence

Typical validation:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

CI generates the platform templates so this repository does not need checked-in generated Android, iOS, or Windows build output.

## Previous WebView artifact

The existing Kotlin `app/` module and its Beta 10 release are retained as historical material while the Flutter implementation is brought back. They are not used by the Flutter validation workflows and must not be presented as the native Flutter app.

## Release policy

Do not publish a new app release until the v553 recommendations and logging path, local persistence, account boundaries, XP award timing, and sync conflict behavior have automated coverage and platform builds pass. Unsigned iOS artifacts are not installable on ordinary iPhones; device distribution requires Apple signing and provisioning.


## Historical parity audit

The preserved Flutter workspace includes the **Milestone 55** native v410 release-readiness audit. Its decision remains blocked and is historical evidence only, not a claim of v553 parity or release readiness for this app.


The preserved source also includes the **Milestone 56** writer inventory and staging preflight. It documents an incomplete source audit, unprovisioned staging, and disabled production writes; it does not authorize cloud changes.
