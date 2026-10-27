# MediaFlowApp architecture (planned)

Flutter/Dart app for Android, iOS and Windows. One adaptive widget tree with platform-specific affordances; shared existing Supabase account and data. Recommended layers: `app/` (router, bootstrap), `design_system/` (tokens, themes, components), `features/` (screens and state), `data/` (repositories, DTOs), `services/` (auth, sync, backups, files), `core/` (errors, diagnostics). Riverpod and GoRouter are proposed dependencies, pending implementation.

Use local indexed persistence for offline read/edit and an idempotent operation queue for reconciliation. Never store service-role secrets in client code. Enforce existing Supabase RLS and avoid unreviewed schema migrations. Use virtualization/pagination for 100k-entry targets, measure performance on real devices.

CI: analyze/test on Linux; build signed Android artifacts when signing configured; Windows build on Windows runner; iOS build on macOS runner with Apple signing. Tag `vNNN` triggers draft release; publish only after checks and required artifacts are verified. iOS IPA distribution is subject to Apple's provisioning rules.

Initial milestone: documentation and source audit only. Flutter scaffolding and platform builds are not yet implemented.
