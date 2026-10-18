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
print('MediaFlow production website Android INTERNET permission verified')
