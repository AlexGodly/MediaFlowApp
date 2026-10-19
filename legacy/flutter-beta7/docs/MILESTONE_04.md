# Milestone 04 — Native read-only Library

Status: source implementation committed; GitHub Actions Flutter validation configured.

## Source contract reviewed

- Original MediaFlow v410 in AlexGodly/MediaFlow; VERSION = 410.
- Cloud reader and compressor in src/js/services/cloud-sync/004-v115-cloud-data-loss-prevention-recovery-guard.js.
- Production database metadata inspected with read-only queries: public.mediaflow_states has user_id (uuid), state_data (jsonb), updated_at (timestamptz), and RLS enabled.
- The current cloud row uses a gzip/base64 envelope with keys __mediaflowCompressed = gzip and data.
- Real title properties include id, title, categoryId, status, priority, progress, total, rating, coverUrl, and seasons.

## Implemented in MediaFlowApp source

1. Native Dart models for categories, titles and season progress.
2. Gzip/base64 or uncompressed JSONB snapshot decoding on an isolate.
3. Authenticated SELECT-only repository scoped to auth.currentUser.id.
4. Read-only Library screen with List, Compact, Cards, Covers, Covers + Titles.
5. Search debounce, category/status/priority filters, multiple sorts, lazy row/grid rendering, pagination, details, loading/empty/error/retry.
6. Dart codec/filter tests and UI search test using an in-memory fake repository.
7. GitHub Actions Flutter validation workflow that generates missing platform folders on its runner, runs flutter analyze and flutter test.

## Safety and limitations

- NO database writes, migrations, backend schema change, or edits to the original MediaFlow repository.
- Still missing: Library mutations, cloud merge/offline queue, metadata-editing parity, dynamic layout, dashboard, logging, imports/exports and complete app pages.
- Authentication with real accounts, native platform installation and live Library reads have not been verified by device tests.
- Whole-user cloud snapshot read remains necessary under the current schema. Lazy UI builds do not establish a 100K-title performance benchmark.
- HTTPS cover URLs are displayed; embedded/local image handling and artwork parity remain to be completed.
- CI validation is not a packaged APK/Windows/iOS release; code must pass the workflow and platform builds.

## Testing/build

On a machine with Flutter SDK:
1. flutter create --project-name mediaflow_app --platforms=android,ios,windows .
2. flutter pub get
3. flutter analyze
4. flutter test

For authenticated debug builds, use --dart-define=SUPABASE_URL and --dart-define=SUPABASE_PUBLISHABLE_KEY for the *existing* original MediaFlow project. Never embed a service-role or secret key.

Next steps: verify GitHub Actions, resolve static/build issues, test existing-account read-only Library on real devices, then implement additional native pages and safe offline-sync contracts.
