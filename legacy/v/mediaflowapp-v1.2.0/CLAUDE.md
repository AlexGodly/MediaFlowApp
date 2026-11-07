# MediaFlowApp — working rules

## Standing instruction from the owner (Alex Godly)

**Every change ends in a release.** After any change to this repo: push to `main` (or open a PR and merge it), and make sure the GitHub Actions release workflow publishes a new **stable** GitHub Release (never a pre-release; owner's decision, 1.0.0) containing **all three platforms**: the Android APK, the Windows installer + portable zip, and the iOS `.ipa`. Do this every time without being asked.

**The app is native Flutter** (owner's decision, Beta 12). No WebView builds.

**Versions** (stable since 1.0.0; Beta 16 was the last pre-release): `X.Y.Z` — a new minor version (1.1.0, 1.2.0…) for releases with features, a patch version (1.0.1…) for fix-only releases. The build number after `+` keeps counting up by one every release (1.0.0 is build 17) so each release installs over the previous one.

A release only happens when the version is new, so every change must:

1. Bump the version everywhere: `pubspec.yaml` (`version: X.Y.Z+N`), `kAppVersionLabel` in `lib/src/config.dart` (`'X.Y.Z'`), and `APP_VERSION` / `TAG` (`mediaflowapp-vX.Y.Z`) / `app_version` in `.github/workflows/release.yml`.
2. Add `docs/releases/mediaflowapp-vX.Y.Z.md`.
3. Push to a branch first and let `ci.yml` pass (tests + all three builds); this workspace can't run Flutter, so CI is the compiler.
4. Refresh the byte-identical source archive `legacy/v/mediaflowapp-vX.Y.Z/` (every tracked file outside `legacy/`, plus `ARCHIVE_METADATA.md`; `python tool/make_release_archive.py --tag <tag>`) as the **last** step before merging. `python tool/verify_release_archive.py --tag <tag>` and `python tool/release_guard.py` must pass.
5. After merging, check the release run and confirm the release has the APK, Setup.exe, portable zip and IPA and is marked Latest (not a pre-release); fix and re-release if any platform failed.

## Product rules

- Goal: every feature of the latest MediaFlow website (repo `AlexGodly/MediaFlow`) natively. Normally one area per release; the owner may ask for more in one release (Beta 14 brought every area at once). **Logging is the top priority** and must never regress.
- Writes to the account must match what the website would write. Port the website's logic, then prove it with golden fixtures generated from the real website (`tool/website_reference/`), as `test/logging_golden_test.dart` does for logging.
- Cloud writes: compare-and-swap on `mediaflow_states.updated_at`, replayable operations with fixed ids, preserve every field the app doesn't understand.
- No Supabase schema/policy changes without the owner's explicit approval (project `wgeijxfdpgehesxialxm`).
