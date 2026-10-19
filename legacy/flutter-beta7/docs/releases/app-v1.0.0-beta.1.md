# MediaFlowApp v1.0.0 Beta — Logging + MediaFlow Recommends

**Reference:** personal MediaFlow **v478 Stable** (native feature subset, not complete parity).

## Added
- MediaFlow Recommends appears **inside Native Logging**, above the Library search and filters.
- Saved current task recommendation uses **exact Library ID** and has priority over queue-only previews.
- Category switcher with status, priority, progress and cover preview.
- **Use recommended title** adds the existing title directly to the local Logging selection and opens its draft/review actions. Reusing an already selected recommendation does not duplicate it or clear other selections.
- Where no saved task is available, the Personal Order first eligible recommendation is shown **only when prioritization is enabled**, clearly labeled **queue preview**, not a confirmed website recommendation.
- Missing/duplicate title IDs, ambiguous saved tasks, disabled/unknown queue-policy and unknown recommendations fail safely.
- Android phone/Windows responsive card and automated widget/source safety tests.

## Platform packages
- **MediaFlowApp-Android-debug.apk** — Android development build (debug-signed, installable at the user's own discretion; not a Play Store release).
- **MediaFlowApp-Windows-x64.zip** — Windows x64 release-mode application directory (extract the **entire** ZIP before launching MediaFlow.exe; installer/signature not included).
- **MediaFlowApp-iOS-unsigned.ipa** — unsigned iOS device application build archive for developer signing **only**. It is **not installable on a normal iPhone** without valid Apple signing/provisioning and device distribution. A signed IPA/TestFlight build requires Apple Developer account credentials and provisioning, which are not configured here.

## Important limitations
- Local Logging selections and drafts are still preview-only, not durable production logging. **Supabase, History, XP, task completion, website recommendation rerolls and cloud writes remain disabled.**
- The recommendation picker is a verified **subset** of v478. The current saved task is authoritative when its ID is unique; queue-only preview cannot reproduce the website's full fallback and smart engine rules.
- Existing MediaFlow website, MediaFlow Plus, and production data remain unchanged.
- No full MediaFlowApp feature-parity or production readiness claim. This is a **beta/developer preview**.
