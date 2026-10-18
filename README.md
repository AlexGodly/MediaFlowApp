# MediaFlowApp — Fresh Start

Rewritten from a **completely clean Flutter tree** on October 18, 2026.
The previous Beta 5 source is preserved at GitHub branch
`archive/beta5-before-rewrite` and the old releases remain available.

## Exactly two screens
1. **Connect to my cloud**: email/password sign-in using the **existing MediaFlow personal Supabase project**. Persistent session, automatic token refresh, explicit sign-out and no new accounts/tables.
2. **Logging**: load the real signed-in Library, search and select titles, prepare Per Unit / Last Unit / Amount logging drafts, preview progress and inspect the draft.

No Dashboard, Statistics, Collections, Settings, Personal Order or other workspaces are included.

## Critical release limitation
The first rewrite does **not** mutate the production MediaFlow account snapshot.
The Logging editor is genuinely interactive, but **cloud submission is disabled**.
This is **not** equivalent to a real saved log; no Library, History, XP,
streak or recommendation side effects are written.

The original website stores many interconnected account roots in one cloud
`mediaflow_states.state_data` snapshot, sometimes gzip-compressed. Blindly
editing the blob risks overwriting other device changes and corrupting
XP/history/progress. Enabling a real submit requires an atomic, account-scoped
transaction and website-compatible logging side effects, verified in staging.
The Supabase connector was unavailable for live schema verification in this
session. Do not bypass this safeguard by enabling client `upsert`.

## Build
```sh
flutter create --project-name mediaflow_app --org com.alexgodly --platforms=android,windows,ios .
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

When build defines are omitted, the app uses the **existing personal MediaFlow
public Supabase endpoint and publishable key** from the prior authorized native
app. Those values are public-client configuration, *never* service-role credentials.

GitHub Actions creates Android, Windows and unsigned iOS artifacts. Unsigned
iOS is a development archive, not directly installable on standard iPhones.
