# MediaFlowApp — Milestone 35: Native Authentication & Transactional Readiness

**Status:** Implemented native authentication flows and expanded read-only simulated cross-writer test coverage. Not a production data-writing milestone. This milestone covers v410 QA matrix `FLOW-001`, `FLOW-002`, `FLOW-003` subsets; no claim of full parity or physical-device sign-off.

## Implemented

- Upgraded the real Flutter login/create-account interface to a native responsive mobile/desktop layout based on original MediaFlow v297/v298 authentication component. Preserves the original launcher identity, separate login/signup modes, email+password fields, six-character minimum and signup password confirmation; adds one purposeful visibility toggle per field and autofill.
- Signup and login use the existing Supabase Auth project via `MediaFlowAuth` with **no new tables and no copied Library/History records**.
- Password reset request now validates an email and avoids asserting whether that email belongs to an account. The actual link destination still depends on Supabase project's approved redirect URL and platform deep-link configuration.
- **Password recovery completion:** listens for Supabase `AuthChangeEvent.passwordRecovery` and shows an explicit native change-password form in place of the Library workspace. A token refresh or userUpdated event cannot bypass the form. Password updates go exclusively through `SupabaseAuth.updateUser(UserAttributes(password: ...))`, never `mediaflow_states`.
- Owner- and concurrency-bound `NativeM35PasswordRecovery` verifies the same signed-in user both before and after each credential update. Rejects account changes, invalid/mismatched passwords and simultaneous submissions. New password never enters the Library state, draft queue or diagnostics.
- Account-scoped shell stays keyed to the Supabase user ID; the existing sign-out path still purges encrypted offline snapshots and draft keys before removing the session, and no account-specific Library data is transferred between accounts.
- Tests: basic validation, rejection before Supabase call, owner switch before/during recovery, duplicate-operation guard, phone rendering, password visibility, signup confirmation, reset email validation, successful UI completion, and four-client (website/Android/iOS/Windows) revisioned **synthetic only** write-conflict and auth isolation matrix using the existing M30 model. All prod cloud write flags remain off.

## Limits / mandatory follow-up

- The original v410 website is still a direct full-state UPSERT writer; it has NOT been migrated. Synthetic CAS test results are not a deployed PostgreSQL transaction, durable idempotency or real cloud writes.
- Native password-recovery **deep-link reception** on an actual Android/iOS/Windows installation needs a verified Supabase redirect allowlist, URI scheme/app-link association and signed-device end-to-end test. The reset request works through existing Supabase configuration but could open the **website**, not the native form. Do not count the deep-link portion of `FLOW-002` as device verified.
- Supabase signup policy, email confirmation, password policies and throttling are enforced by the existing provider; native client cannot promise immediate signup without knowing project settings.
- Detailed native title CRUD, logging/History/XP writes, Collections actions and app-wide v410 edit/action parity remain incomplete, and no network retry or replay worker is enabled.
- Test suites on CI cannot certify real-device navigation, app lifecycle events, production email deliverability or 100k scrolling. Do not mark `parityVerified: true` in the 307-feature inventory.
- No changes to `AlexGodly/MediaFlow`, `AlexGodly/MediaFlowPlus` or any production Supabase project.

## Next

Milestone 36: native Dashboard tools and user workflows from the v410 interaction matrix (Stopwatch / Runtime Calculator / rating queue) while retaining read-only data safety until a coordinated, separately approved website/Supabase synchronization migration.
