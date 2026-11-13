#!/usr/bin/env python3
"""Generate launcher icons for Android, Windows and iOS from the preserved original artwork."""
import json
from pathlib import Path

from PIL import Image

logo = Path("legacy/flutter-beta7/assets/branding/mediaflow-launcher-512.png")
if not logo.is_file():
    raise SystemExit("Original MediaFlow launcher image missing from legacy archive")
image = Image.open(logo).convert("RGBA")


def resized(size):
    return image.resize((size, size), Image.Resampling.LANCZOS)


# Android
for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    output = Path(f"app/src/main/res/mipmap-{density}/ic_launcher.png")
    output.parent.mkdir(parents=True, exist_ok=True)
    resized(size).save(output)

# Windows (electron-builder reads desktop/build/icon.ico and icon.png)
desktop = Path("desktop/build")
desktop.mkdir(parents=True, exist_ok=True)
resized(512).save(desktop / "icon.png")
resized(256).save(desktop / "icon.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

# iOS: single-size 1024 marketing icon (must be opaque).
appicon = Path("ios/MediaFlow/Assets.xcassets/AppIcon.appiconset")
appicon.mkdir(parents=True, exist_ok=True)
resized(1024).convert("RGB").save(appicon / "AppIcon-1024.png")
(appicon / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1},
}, indent=2) + "\n")
(appicon.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

print("MediaFlow launcher icons generated for Android, Windows and iOS")
