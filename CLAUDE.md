# MediaFlowApp — working rules

## Standing instruction from the owner (Alex Godly)

**Every change ends in a release.** After any change to this repo: push to `main` (or open a PR and merge it), and make sure the GitHub Actions release workflow publishes a new **stable** GitHub Release (never a pre-release; owner's decision, 1.0.0) containing **all five platforms** (owner's decision, 7.1.0): the Android APK, the Windows installer + portable zip, the iOS `.ipa`, the Mac `.dmg` + `.zip` (unsigned, ad-hoc signed; owner's decision) and the Linux AppImage + `.tar.gz`. Do this every time without being asked.

**The app is native Flutter** (owner's decision, Beta 12). No WebView builds.

**Versions** (owner's decision, 2.0.0.560): `MAJOR.FEATURE.FIX.WEBSITE`.
- **MAJOR**: a big update — several changes at once (not one simple thing).
- **FEATURE**: one feature / one area.
- **FIX**: a bug fix or a very small change.
- **WEBSITE**: the MediaFlow website version (repo `AlexGodly/MediaFlow`, e.g. v560) whose features the app matches.
- Raising a number resets the ones after it to 0 (except WEBSITE, which always shows the matched website version): 2.0.0.560 → 2.1.0.560 (a feature) → 2.1.1.560 (a fix) → 3.0.0.565 (a big update that also catches up to website v565).
- Stores only take three numbers, so `pubspec.yaml` has `version: MAJOR.FEATURE.FIX+N`; the label, workflow and tag carry all four. The build number after `+` keeps counting up by one every release (2.0.0.560 is build 20) so each release installs over the previous one. 1.0.0–1.2.0 used `X.Y.Z`; Beta 16 was the last pre-release.

A release only happens when the version is new, so every change must:

1. Bump the version everywhere: `pubspec.yaml` (`version: MAJOR.FEATURE.FIX+N`), `kAppVersionLabel` in `lib/src/config.dart` (`'MAJOR.FEATURE.FIX.WEBSITE'`), and `APP_VERSION` / `TAG` (`mediaflowapp-v<label>`) / `app_version` in `.github/workflows/release.yml`.
2. Add `docs/releases/mediaflowapp-v<label>.md`.
3. Push to a branch first and let `ci.yml` pass (tests + all five builds); this workspace can't run Flutter, so CI is the compiler.
4. Refresh the byte-identical source archive `legacy/v/mediaflowapp-v<label>/` (every tracked file outside `legacy/`, plus `ARCHIVE_METADATA.md`; `python tool/make_release_archive.py --tag <tag>`) as the **last** step before merging. `python tool/verify_release_archive.py --tag <tag>` and `python tool/release_guard.py` must pass.
5. After merging, check the release run and confirm the release has the APK, Setup.exe, portable zip, IPA, Mac .dmg + .zip and Linux AppImage + .tar.gz and is marked Latest (not a pre-release); fix and re-release if any platform failed.

## Product rules

- Goal: every feature of the latest MediaFlow website (repo `AlexGodly/MediaFlow`) natively. Normally one area per release; the owner may ask for more in one release (Beta 14 brought every area at once). **Logging is the top priority** and must never regress.
- Writes to the account must match what the website would write. Port the website's logic, then prove it with golden fixtures generated from the real website (`tool/website_reference/`), as `test/logging_golden_test.dart` does for logging.
- Cloud writes: compare-and-swap on `mediaflow_states.updated_at`, replayable operations with fixed ids, preserve every field the app doesn't understand.
- Accounts the website moved to per-record storage (website v556, `mediaflow_records`) sync record by record exactly as the website writes them (`test/records_golden_test.dart`), plus the `mf556` fallback copy in `mediaflow_states`.
- No Supabase schema/policy changes without the owner's explicit approval (project `wgeijxfdpgehesxialxm`).
- **Discord Rich Presence stays current** (owner's decision, 3.0.0): every new or changed screen, section or feature sets its Discord status in the same release — section statuses in `sectionPresence` (`lib/src/ui/presence.dart`), screens opened on top wrap themselves in `PresenceScope`, sections refine theirs with `PresenceHub.section`. `test/presence_test.dart` fails if a screen has none. Covers come from the title when it has one, the MediaFlow logo otherwise; the privacy setting must hide titles and covers.
- Discord uses only Discord's official Social SDK (no user tokens or unofficial clients). The SDK is licensed and private: CI downloads it from `AlexGodly/discord-social-sdk` with the `DISCORD_SDK_TOKEN` secret (`tool/discord_sdk.py`); never commit it, cache it in Actions, or put it in the source archive. Application ID `1554979701787992225`.
