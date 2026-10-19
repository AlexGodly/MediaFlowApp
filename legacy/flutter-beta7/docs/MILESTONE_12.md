# MediaFlowApp — Milestone 12: History and Collections performance

**Baseline:** MediaFlowApp Milestone 11 / original website v410. **Cloud write capability:** disabled.

## Delivered

1. **Milestone 11 CI confirmed:** Flutter validation succeeded for commit `c215cab2` (GitHub Actions run `38489469011`). The 100,000-title synthetic Library test is part of that suite.
2. **History snapshot index:** `MediaFlowHistoryIndex` sorts sessions once per loaded snapshot instead of sorting on every search or filter change. It applies category, result, note/title search, and date-range filters over the pre-sorted data.
3. **Bounded History cache:** At most six filtered-result lists are retained. Time-dependent filter keys include the current local minute, and a cloud refresh rebuilds the index. This avoids returning stale cached results across refreshes.
4. **Collections snapshot indexing:** Native Collections now builds the title-ID lookup, resolves member titles, and calculates collection progress once per loaded cloud snapshot. It reuses those values during searches and UI rebuilds, avoiding repeated full-Library mapping and repeated collection progress calculations.
5. **Tests:** History index regression comparisons against the existing `MediaFlowHistoryFilter` across all date ranges, category/status/search combinations, cache immutability/eviction, and a synthetic 50,000-session benchmark that prints timing telemetry.

## Limitations and accuracy

- This milestone targets repeated History/Collections work. It does **not** claim complete 100K-title, low-memory, 60fps or native platform parity.
- First History sort is still synchronous and must be measured on real hardware. Some Statistics/Dashboard computations and image decoding remain candidates for later optimization.
- The History date-range index preserves the original filter's 7/30-day cutoff behavior; its date-sensitive cache is intentionally short-lived.
- Benchmarks are synthetic and measured on GitHub CI hardware. No actual private user data was copied.
- Android/Windows platform builds run separately from Flutter analysis/tests. Their statuses must be checked independently.

## Next

Run Android and Windows device profiling, measure UI frame times and memory during first snapshot decode and navigation, then selectively move expensive work off the UI isolate. Continue native UI and feature parity without enabling unsafe cloud writes.

**Data protection:** Original MediaFlow and MediaFlow Plus repositories untouched; no production Supabase changes.
