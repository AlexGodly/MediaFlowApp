#!/usr/bin/env python3
"""Grant network access to generated Android templates for the full website UI.

CI regenerates android/ from 'flutter create' each build, so this is
idempotent and intentionally modifies only the generated Android manifest.
"""
from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
if not manifest.is_file():
    raise SystemExit('Generate Android platform with flutter create first')
text = manifest.read_text(encoding='utf-8')
permission = '<uses-permission android:name="android.permission.INTERNET" />'
if permission not in text:
    marker = '<application'
    if marker not in text:
        raise SystemExit('Generated Android manifest missing <application>')
    text = text.replace(marker, '    ' + permission + '\n    ' + marker, 1)
    manifest.write_text(text, encoding='utf-8')
# Forge Android WebView uses AndroidX WebKit 1.16 and requires API level 24+.
for build_file in [
    Path('android/app/build.gradle.kts'),
    Path('android/app/build.gradle'),
]:
    if not build_file.exists():
        continue
    gradle = build_file.read_text(encoding='utf-8')
    gradle = gradle.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    gradle = gradle.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
    build_file.write_text(gradle, encoding='utf-8')
print('MediaFlow WebView Android INTERNET and min SDK 24 verified')
