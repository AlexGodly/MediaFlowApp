# MediaFlowApp

Native Flutter application for Android, iOS, and Windows, based on MediaFlow web v410.

## Goals
- Reimplement the MediaFlow v410 interface and functionality in native Flutter (not WebView).
- Keep the original website and repository unchanged.
- Reuse existing Supabase accounts and user data without duplicating libraries.
- Preserve offline support, themes, import/export, logging, collections, statistics, and settings.
- Validate functionality against an explicit v410 parity inventory before production releases.

## Release policy
- Public tags and release names: `v410`, `v411`, etc.
- Each release includes changelogs and verified platform build artifacts.
- Android APK and Windows packages are distributed through GitHub Releases.
- iOS IPA requires macOS/Xcode and valid Apple signing/provisioning; installation/distribution depends on Apple rules.
- Do not publish a production release until required build and parity checks pass.

## Status
Planning and source audit. No native build is claimed yet.

Source: https://github.com/AlexGodly/MediaFlow (VERSION 410 verified on 2026-10-13).
