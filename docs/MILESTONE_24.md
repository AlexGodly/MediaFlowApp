# MediaFlowApp — Milestone 24: XP Completion Ledger, History Clock & Native Branding

**Baseline:** MediaFlowApp Milestone 23, original personal MediaFlow website v410. **Production cloud writes, actual XP awards, History mutations and offline mutation replay remain DISABLED.**

## App identity

- Display name (Android, iOS, Windows and in-app): **MediaFlow**.
- Android application ID/Gradle namespace: **com.alexgodly.mediaflow**. The generated MainActivity Kotlin/Java package is moved to match.
- iOS CFBundleIdentifier: **com.alexgodly.mediaflow** (build configuration prepared; actual iOS device signing/release requires Xcode/macOS/Apple provisioning).
- Windows executable: **MediaFlow.exe**, resource product description/name **MediaFlow**.
- Original MediaFlow launcher graphics are copied into native repository as base64 text assets from the original website (v410), along with its Windows mediaflow.ico. The exact original source asset Git blob IDs are: PNG 58c090aff64c1e1133c3583c7509a84de66a0ce1; maskable PNG 922aade8685984c2eed7aeda6ad53553f132b4a4; ICO 8fbc1c0415ddcd0f43f8356631ff700e1d9aa856. Builds use these locally pinned bytes, not network copies or generated substitute logos.
- The repository maintains its `mediaflow_app` Dart *package/module* name for backwards-compatible imports. **This internal pubspec name is not the Android package ID, iOS bundle ID or displayed app name.**
- Each CI build recreates platform templates and applies `python tool/branding/apply_branding.py --platforms=...` before compile. Pillow supplies correct iOS launcher image catalog sizes. Branding is deterministic and platform-template-only, with no changes to either website.

## Native feature additions

1. **Source-pinned v120 one-time completion XP ledger simulation.** A read-only, cloned map evaluates the original website's `v120EnsureXPState`, `v120LoggedCompletionXP`, `v120AwardLoggedCompletionXP` semantics, including configured rate, disabled leveling, blank title IDs, one-time credit and persistence of zero-value completion entries to block future re-awards. All actual user ledgers remain unmodified.
2. **Source-pinned v331 per-title event clock parity.** The original `v331ValidTimestamp`/`v331EventDate` functions are copied and executed with deterministic synthetic timestamps. Native mirrors priority of valid per-title loggedAt, then group date at local noon, then session timestamp; the five fixture cases are tested in UTC. This is History display only, not a session write or date correction.
3. **History title timestamp display.** Read-only History details display per-title event dates/times, preserving parent session grouping and Statistics counts.
4. **Shared source fixtures.** `test/fixtures/m24_ledger_clock_vectors.json` is verified by both copied website JS (`tool/parity/m24_website_reference.mjs`) and Dart (`test/native_m24_ledger_clock_parity_test.dart`), with a 100,000-ledger-entry synthetic mutation-isolation check.
5. **Native build CI branding.** Platform build workflows generate Android or Windows projects with organization `com.alexgodly`, apply exact name/package/icon updates and build validation artifacts. Flutter CI also generates/brands an iOS project and checks Dart analysis + tests. It does not sign or export a production IPA.

## Safety and incomplete parity

- The original v410 runtime awards many other XP sources (consumption, v149 streak, v348 action awards, category health, completion timeline, etc). **These are not fully implemented or awarded in native MediaFlowApp**. The local completion ledger output is a hypothetical decision, not a real account reward.
- Web originals and Supabase were not modified. Native cloud writes and automatic offline replay remain prohibited until every writer adopts compatible server-enforced CAS and website-compatible side effects.
- Android build validation APK is **debug only**, Windows is an unsigned validation application. iOS signing requires a Mac and Apple signing; no iOS IPA is claimed.
- The signed releases/version-tag policy in README remains: no premature production release unless parity/device/build requirements are met.

## Validation

Actions check: Node reference fixtures M23 + M24, install Pillow, generate+brand Android/iOS/Windows templates, Flutter analyze, Flutter test; then Android debug APK and Windows release-mode unsigned build on main. Check Actions for actual run conclusions rather than assuming completion.

## Next

Milestone 25: native XP settings/ledger read-only projection audit, v348 universal action XP source fixtures, and end-to-end fixture validation of session grouping/completion side effects. Then coordinated cross-client atomic CAS migration needs explicit scope/approval before enabling cloud writes.
