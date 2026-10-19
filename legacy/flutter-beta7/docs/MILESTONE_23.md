# MediaFlowApp — Milestone 23: Executable Website History and XP Parity Harness

Baseline: independent native Milestone 22, original MediaFlow v410 source. Date: October 14, 2026.
PRODUCTION CLOUD WRITES, HISTORY MUTATIONS, XP AWARDS AND OFFLINE REPLAY: DISABLED.
Scope: only AlexGodly/MediaFlowApp. Original MediaFlow, MediaFlow Plus and production Supabase untouched.

## Implemented

1. Pinned original JavaScript functions in tool/parity/m23_website_reference.mjs, with source path and blob SHA for v331LogicalSessionCount; v149 date/streak calculations; v120IsCompleted; v369ContiguousProgress; and submitLog's multi-category grouping. These excerpts are executed against synthetic inputs with minimal dependency shims, and are NOT the full deployed browser runtime.
2. Shared fixture source test/fixtures/m23_source_vectors.json: Node verifies original-JS outputs, and Dart verifies native implementations on the SAME vector inputs. CI runs the pinned Node reference before Flutter analysis and tests.
3. Read-only logical History action counts distinct from physical rows. Grouped Dashboard or Batch Log submissions remain separate stored records but count as one action.
4. Known-base and illustrative v149 day-streak XP audit ONLY for positive stored XP. Zero, missing or invalid baseline XP remains unresolved; category/health fallback XP is deliberately NOT invented. Skipped sessions contribute zero. No level or new reward is calculated.
5. Completion timestamp and exact libraryId source evidence in the native typed model. Conservative validation requires a non-skipped matching session within five minutes of the title's completedAt. No completion bonus is awarded.
6. Native recommendation grouping preview: grouped category consumption, weighted runtime, partial/over/complete statuses, skipped recommendation record. Task rotations and respect/XP ledgers are not mutated.
7. History screen shows source-audited logical count and incomplete known XP diagnostic. Streak-day index uses FULL History even when visible sessions are filtered, cached per loaded snapshot.
8. Encrypted offline read-only projection includes actual sessionGroupId, batchGroupId, healthStatus, assignedCategoryId and title completedAt as read-only evidence.
9. Fixtures cover original-JS matching, completion recognition, contiguous unit gaps, 5-minute evidence, and a synthetic 100,000-row audit.

## Verification caveats

- Pinned copied original functions plus dependency shims are only a verified reference subset; this is NOT full end-to-end v410 browser parity.
- Missing XP formula inputs, settings, achievement/bonus ledgers, account level and many newer overrides still cannot be reconstructed safely from the intentionally lossy native catalog.
- Streak bonus diagnostic assumes leveling is enabled, never claims a guaranteed award, and does not recalculate XP from a post-multiplied amount.
- Completion evidence is NOT permission to award a bonus; existing one-time completion ledger state may already contain that award.
- The original website still has unconditional full-state writes; native cloud editing remains disabled until every writer uses a shared database-enforced CAS protocol.
- CI builds and synthetic 100K tests are not signed release builds or device performance certification.

## Commands and next steps

Reference: node tool/parity/m23_website_reference.mjs
Flutter: flutter analyze && flutter test
Native platform builds: GitHub Actions, post-merge commit.
Milestone 24: expand read-only fixture parity for advanced per-title History timing, configured XP and ledger logic without enabling production writes.
