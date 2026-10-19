# Milestone 03 — Authentication integration foundation

## Implemented in source
- Supabase Flutter SDK dependency and session-aware auth gate.
- Existing MediaFlow Supabase account sign-in, sign-up and sign-out service methods; password-reset service method.
- Credentials injected at build time with `--dart-define=SUPABASE_URL=...` and `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`.
- Login screen with loading, error and email-confirmation states.
- Unconfigured builds show the navigation shell as a developer preview; this preview does **not** imply authentication or live data access.

## Critical limitations
- The native Library has NOT been connected. Existing MediaFlow stores canonical state in a custom cloud snapshot and merge pipeline; directly writing a guessed table would risk data corruption.
- Auth has NOT been exercised against live Supabase. The original app and production data were not modified.
- No Flutter compiler or SDK was available in the execution environment; compilation, tests, Android/Windows/iOS platform generation and builds remain unverified.
- Sign-out UI, password-reset UI and robust redirect/deep-link handling are not yet wired.
- No APK/EXE/IPA or release has been produced.

## Next
1. Establish CI and generated platform projects.
2. Inspect active v410 cloud snapshot and merge functions and implement read-only Library repository with exact schema mapping.
3. Test auth with a dedicated test account, then add safe mutations and offline sync.
