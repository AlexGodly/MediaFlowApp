# MediaFlowApp Beta 7 — native UX and cloud-parity audit

**Reference:** current Flutter Beta 6 / personal MediaFlow v507 (October 19, 2026).  
**Scope:** all 14 native navigation destinations, shared shell, Supabase read/restore flow, offline draft safeguards and release gates.

This inventory describes existing *implemented surfaces* and *remaining parity work*, not a claim that the native app is a complete copy of the website. The older v410 307-surface ledger is retained for historical requirements but must be **revalidated against v507+** before asserting full parity.

## Cross-cutting changes shipped in the Beta 7 branch

1. **Every destination:** shared native ambient gradients, subtle light/AMOLED adaptations, redesigned shared card surfaces and section headings, consistent scrollbars and transitions.
2. **Navigation:** indexed search across all 14 destinations (including More-only mobile screens), desktop quick switch, always reachable mobile search.
3. **Read synchronization:** a truthful cloud-status chip distinguishes cloud reads, encryption/cache trouble, recovered copies, offline memory and invalid cloud. Explicit refresh on desktop and mobile; last-good cloud copy stays isolated by authenticated owner.
4. **Foreground awareness:** when the app is resumed after 15 minutes, one read-only refresh is allowed. The automatic refresh does not unmount Library, Logging, Collections, Personal Order or Settings edit screens.
5. **Safety:** NO new Supabase write path, no changing website storage schema, no automatic draft replay and no credentials embedded in code. Read-only is not silently labeled 'synced'.

## Coverage and remaining parity by destination

| Destination | Native implementation already available | Highest-value missing work |
|---|---|---|
| Dashboard | Library counts, activity, Next Task evidence, Stopwatch and runtime utilities | Website-equivalent task generation/skip/reroll and atomic XP/History effects; richer hero visual/cover treatment |
| Library | High-volume browsing, filtering, multiple view modes, title details, reversible local edit plan | Verified metadata/cover recovery, production CRUD/bulk changes, all v507 picker/filter details |
| Advanced Logging | Per-unit, last-unit and amount-based local drafts; timings, repeats, preview, task handoff | Authenticated atomic cloud logging that consistently updates Library progress, History, XP, streaks, collections and task state |
| Personal Order | Category/collection/direct-title planning, native selectors and ordering previews | Cloud persistence and complete website ordering/task algorithms; cross-device consistency |
| Collections | Existing collections read and browsed, local membership planning | Create/edit/delete cloud writes, smart collection behaviors, sharing/public edition separation |
| History | Authenticated History projections/search/filter | Editable actions, deletion/undo, export, local date/time corrections, atomic logging receipts |
| Statistics | Read-only categories and sessions | All website XP/streak charts, period controls and reliable derived metrics |
| Account | Supabase authentication/session/recovery subset | Device-specific deep-link recovery QA and comprehensive sign-out/restore validation |
| Settings | Device Dark/Light/AMOLED, review panels, conflict diagnostics and offline cache tools | Complete v507 settings tree; website settings export/import; cloud preference parity; automatic backup verification |
| Old System | Read-only per-category overview and legacy progress summaries | Remaining v507 operational controls, migrations and editing parity |
| Fresh Episodes | Unverified candidate Library with search/pagination | Real provider adapters, explicit verification status, all media types, Alex Godly's Smart Fresh Episodes Engine |
| Background Processes | Missing cover/external ID diagnostics, safe search/filter/copy | Recovery queue, provider health, cooldowns, cancel/resume, cover/metadata repairs and safe progress checkpointing |
| Theme Studio | Native palette picker and previews | Legacy/Advanced/Custom theme generation, Cover Intelligence, custom image/palette studio, Living Themes, motion/atmosphere settings and cross-device theme persistence |
| About | Branding and native-version/about content | Version/updater status, help, diagnostics and feature maturity accuracy |

## Highest-risk shared gaps

- **Actual bidirectional cloud sync is NOT enabled.** Website still has a legacy unconditional full-state UPSERT path; enabling an independently implemented native writer risks overwriting newer data.
- Safe enablement requires owner-scoped server-enforced revision checks, full-state merge/side-effect validation and exact History/XP/task parity against current website code.
- A cloud write transaction must reject missing/invalid snapshots, changed accounts, stale revisions, duplicate logging receipts and replays; it must have no bypass path from offline queues.
- Secure local drafts are not equivalent to synchronized cloud mutations. Treat them as pending until the server has durably acknowledged an idempotent receipt.
- Test on two browsers and Android/Windows/iOS against an isolated Supabase environment before production rollout. Keep production MediaFlow data and MediaFlow Plus separate.
- Provider API keys, cloud secrets and service-role keys must never be embedded in Flutter bundles.

## Suggested completion order

1. Validate current v507 website state codec, all write points and side effects; create an isolated Supabase staging copy using synthetic data.
2. Introduce the same atomic optimistic-concurrency mechanism to **every** web and native writer (or a compatible migration) with verified idempotent receipts.
3. Complete Logging submission and History/XP/task side effects with multi-device conflict tests; then enable controlled Library CRUD, Collections and Personal Order writes.
4. Restore advanced settings, themes, backups, automatic exports, recovery engines and provider-based Fresh Episodes.
5. Accessibility, phone widths down to 320dp, tablets/foldables, keyboard, mouse, reduced motion, 100K titles and account switching QA. Only then certify full parity and signed releases.

**Beta 7 is a genuine app-wide experience/read-sync enhancement, not a completed cloud-write or 1:1 website-parity release.**
