# MediaFlow by Alex Godly — native app (Android, Windows, iOS, Mac, Linux)

A native **Flutter** app for your MediaFlow account. Same account, same data as the [MediaFlow website](https://alexgodly.github.io/MediaFlow/); logs you make in the app appear on the website and vice versa.

Download from [Releases](https://github.com/AlexGodly/MediaFlowApp/releases). Latest: **7.1.0.568** — [release notes](docs/releases/mediaflowapp-v7.1.0.568.md).

| Platform | Release file |
| :-- | :-- |
| Android | `MediaFlow-<version>-Android.apk` (universal, any phone) · per phone type: `-Android-arm64-v8a.apk` (most phones), `-Android-armeabi-v7a.apk` (older 32-bit phones), `-Android-x86_64.apk` (emulators / Chromebooks) |
| Windows 10/11 x64 | `…-Windows-x64-Setup.exe` or `…-Windows-x64-portable.zip` |
| iPhone / iPad | `…-iOS-unsigned.ipa` (re-sign to install) |

## What the app does today

Everything on the MediaFlow website, natively, online or offline:

- **Log** — MediaFlow Recommends and the full logging form (Quick / Advanced) with the Logging Library, the + button, Arrange your session, collapsing and XP for this log, shared live with the website.
- **Library** — sorts, filters, views, batch actions, Title Details, the title editor with online cover search, Rate Your Library, Missing Covers.
- **History** — edit and delete logs, Undo / Redo, XP History with export, Library History with restore.
- **Extras** — Today's Balance, On This Day, Stopwatch, Runtime Calculator.
- **More** — Collections, Personal Order with Collection queues, Statistics (every website section), Settings (account and app), Account.

Every change is saved on the device first and replayed on the newest cloud copy; when the same thing changed in two places, the newest change wins.

## How logging stays compatible with the website

- `lib/src/logic/log_engine.dart` writes a log as the website's own **Batch Log** entry, including every follow-up rule the website applies (progress and seasons, completions, rewatch XP, start dates, category-health XP, streaks, XP-ledger awards).
- `lib/src/logic/recommend.dart` (task engine), `log_draft.dart` (the logging form), `rec_submit.dart` (the website's `submitLog` chain) and `resume.dart` (the shared draft) do the same for MediaFlow Recommends.
- `test/logging_golden_test.dart`, `test/recommendation_golden_test.dart` and `test/edit_golden_test.dart` check them against reference results recorded from the **real website**: `tool/website_reference/generate_log_goldens.py`, `generate_recommendation_goldens.py` and `generate_edit_goldens.py` run MediaFlow's own code on fixed accounts and save the before/after data in `test/fixtures/`.
- Library, History, Collections, Personal Order and settings edits (`lib/src/logic/library_logic.dart`, `history_logic.dart`, `collections_logic.dart`) run the website's logic on a copy of the account; `lib/src/data/edit_op.dart` records the difference as replayable changes (each with the value it replaced, so a newer change made elsewhere wins).
- Sync (`lib/src/data/sync_engine.dart`, `account_ops.dart`) keeps logs, task actions and drafts as replayable operations with fixed ids. Each upload re-reads the cloud row and writes with a compare-and-swap on `updated_at`, so it never overwrites a newer version and never duplicates a log. It uses the existing `mediaflow_states` row and policies; no schema changes.

## Layout

```
lib/main.dart                 app entry (Supabase init)
lib/src/state/                account data codec (gzip+base64, like the website) and read-only views
lib/src/logic/                XP rules and the logging engine (ported from the website)
lib/src/data/                 Supabase access, device cache, sync, account controller
lib/src/ui/                   screens: sign-in, Log (Recommends + form), Library, Batch Log sheet, History, Account
test/                         golden parity tests, sync tests, a full UI flow test
tool/prepare_platforms.py     brands the platform folders `flutter create` generates in CI
tool/windows_installer.iss    Windows installer (Inno Setup)
tool/website_reference/       regenerates the website reference fixtures
legacy/                       earlier builds (Flutter Beta 7, WebView betas) and per-release source archives
```

The `android/`, `ios/` and `windows/` folders are generated in CI (`flutter create`) and branded by `tool/prepare_platforms.py`, so there's no hand-maintained platform code to drift.

## Build locally

```sh
flutter create --platforms=android,ios,windows --org com.alexgodly --project-name mediaflow .
python3 -m pip install pillow && python3 tool/prepare_platforms.py
TZ=UTC flutter test
flutter build apk --release          # Android
flutter build windows --release      # on Windows
flutter build ios --release --no-codesign   # on macOS
```

## Releases

Every push to `main` runs `.github/workflows/release.yml`: tests → Android, Windows, iOS, Mac and Linux builds in parallel → one stable GitHub release with all files and SHA-256 sums. Branches and pull requests run the same tests and builds via `ci.yml` without publishing. Each release needs a new version (see `CLAUDE.md`).

## Limitations

The APK is signed with the permanent MediaFlow key (the `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEYSTORE_PASSWORD` secrets); Windows and iOS builds are unsigned. Since website v556 the website saves record by record and merges newer changes first, and since v565 an older website tab can't replace a newer safety copy, so logs made in the app are not overwritten by a stale tab.
