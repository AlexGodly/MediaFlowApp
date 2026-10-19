# MediaFlowApp — Milestone 11: Large-Library native search and sorting

**Baseline:** Original MediaFlow v410. **Native cloud writes:** OFF.

## Delivered

- Added `MediaFlowLibraryIndex` to reuse lazily sorted views across search and filter changes. Previously the native Library sorted all matching titles after every search or filter change.
- Preserved all existing `LibrarySort` modes and their original tie-break behavior by reusing the same comparator.
- Search, category, status, and priority filters now scan the selected pre-sorted list without re-sorting each result.
- The index belongs to one loaded snapshot. Cloud refresh constructs a new index, preventing stale search results.
- Query-result caching is bounded to eight recent combinations, limiting retained list references during extended typing.
- The Library screen retains the index when filters change and preserves the existing debounced, focus-safe search and pagination.
- Added parity tests across every sort mode and multiple filter combinations, cache eviction tests, and a synthetic 100,000-title correctness/performance test.
- The 100K test prints timing telemetry to CI logs without making brittle pass/fail promises based on runner speed.

## Scope and limitations

This improves repeated sorting and query handling on an already decoded snapshot. It does **not** prove smooth 60fps rendering on every device, low-memory Android performance, or efficient transfer of a compressed 100K-title snapshot. The first sort of a newly loaded snapshot still runs synchronously, and large datasets require real-device profiling. No production user data is used in the benchmark.

No edits to original MediaFlow or MediaFlow Plus, no Supabase migrations, no production writes, no offline journal changes.

## Next

- Profile first-load decode, initial sort, History/Collections indexing, and UI frame times with synthetic 100K-title fixtures on Android/Windows.
- Move expensive initial indexing to an isolate if measured frame times demand it; avoid speculative parallelism.
- Continue completing native feature parity while cloud writes remain safely disabled.
