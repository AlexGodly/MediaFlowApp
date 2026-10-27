#!/usr/bin/env python3
from pathlib import Path
from PIL import Image

logo = Path("legacy/flutter-beta7/assets/branding/mediaflow-launcher-512.png")
if not logo.is_file():
    raise SystemExit("Original MediaFlow launcher image missing from legacy archive")
image = Image.open(logo).convert("RGBA")
for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    output = Path(f"app/src/main/res/mipmap-{density}/ic_launcher.png")
    output.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(output)
print("MediaFlow launcher mipmaps generated")
