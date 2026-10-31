# MediaFlow by Alex Godly — native app (Android, Windows, iOS)

A native **Flutter** app for your MediaFlow account. Same account, same data as the [MediaFlow website](https://alexgodly.github.io/MediaFlow/); logs you make in the app appear on the website and vice versa.

Download from [Releases](https://github.com/AlexGodly/MediaFlowApp/releases). Latest: **1.0.0 Beta 14** — [release notes](docs/releases/mediaflowapp-v1.0.0-beta.14.md).

| Platform | Release file |
| :-- | :-- |
| Android | `MediaFlow-<version>-Android.apk` |
| Windows 10/11 x64 | `…-Windows-x64-Setup.exe` or `…-Windows-x64-portable.zip` |
| iPhone / iPad | `…-iOS-unsigned.ipa` (re-sign to install) |

## What the app does today

Sign in · **Log tab with MediaFlow Recommends** (start / something else / skip / end, exact-title rerolls, System Respect XP) and the website's full logging form — Quick (progress reached or amount, multi-title, seasons, new titles) and **Advanced** (per unit: episode by episode with runtimes, times, rewatches; Reached / Amount per title) — with the draft shared live with the website · Batch Log · Library (search, status and category filters, covers, progress) · History · offline use with safe sync. Dashboard stats, Collections, Personal Order editing, Statistics and Settings are next.

## How logging stays compatible with the website

- `lib/src/logic/log_engine.dart` writes a log as the website's own **Batch Log** entry, including every follow-up rule the website applies (progress and seasons, completions, rewatch XP, start dates, category-health XP, streaks, XP-ledger awards).
- `lib/src/logic/recommend.dart` (task engine), `log_draft.dart` (the logging form), `rec_submit.dart` (the website's `submitLog` chain) and `resume.dart` (the shared draft) do the same for MediaFlow Recommends.
- `test/logging_golden_test.dart` and `test/recommendation_golden_test.dart` check them against reference results recorded from the **real website**: `tool/website_reference/generate_log_goldens.py` and `generate_recommendation_goldens.py` run MediaFlow's own code on fixed accounts and save the before/after data in `test/fixtures/`.
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

Every push to `main` runs `.github/workflows/release.yml`: tests → Android, Windows and iOS builds in parallel → one GitHub prerelease with all files and SHA-256 sums. Branches and pull requests run the same tests and builds via `ci.yml` without publishing. Each release needs a new version (see `CLAUDE.md`).

## Limitations

The APK is signed with a CI debug key; Windows and iOS builds are unsigned. The website itself saves without a version check, so a stale website tab can still overwrite a newer app log; refresh the website after logging in the app.
