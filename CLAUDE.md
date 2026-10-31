# MediaFlowApp — working rules

## Standing instruction from the owner (Alex Godly)

**Every change ends in a release.** After any change to this repo: push to `main` (or open a PR and merge it), and make sure the GitHub Actions release workflow publishes a new GitHub Release containing **all three platforms**: the Android APK, the Windows installer + portable `.exe`, and the iOS `.ipa`. Do this every time without being asked.

A release only happens when the version is new, so every change must:

1. Bump the version everywhere: `app/build.gradle.kts` (`versionCode` = beta number, `versionName` = `1.0.0-beta.N`), `desktop/package.json` `version`, `ios/project.yml` `CURRENT_PROJECT_VERSION`, and `APP_VERSION` / `TAG` in `.github/workflows/release.yml`.
2. Add `docs/releases/mediaflowapp-v1.0.0-beta.N.md`.
3. Refresh the byte-identical source archive `legacy/v/mediaflowapp-v1.0.0-beta.N/` (every tracked file outside `legacy/`, plus `ARCHIVE_METADATA.md`) as the **last** step before committing. `python tool/verify_release_archive.py --tag <tag>` must pass.
4. Run `python -m unittest discover -s tests`, `python tests/release_guard.py`, and the e2e test (`python tests/e2e/smoke.py <packaged www>`) before pushing.
5. After pushing, check the workflow run and confirm the release has all four binaries; fix and re-release if any platform failed.

## Product rules

- The apps must expose **every feature of the latest MediaFlow website** (repo `AlexGodly/MediaFlow`, releases `MediaFlow_v<N>_Stable.zip`). Check for a newer website release at the start of each task and update `VERSION`/`ARCHIVE_SHA256` in `tool/package_mediaflow.py` plus `MEDIAFLOW_VERSION` in both workflows.
- **Logging is the top priority.** Never ship a build where titles can't be logged; the e2e test covers it.
- Don't hide or replace website pages. App-specific code goes in `tool/android_assets/companion-mode.js`, which is injected **inside** the website bundle's private scope (separate scripts cannot see `S`, `App`, `render`, etc.).
- No Supabase schema/policy changes without the owner's explicit approval; the apps use the existing `mediaflow_states` row (project `wgeijxfdpgehesxialxm`).
