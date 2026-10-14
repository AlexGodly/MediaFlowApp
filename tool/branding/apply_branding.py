#!/usr/bin/env python3
"""Deterministic MediaFlow native branding for Flutter-generated platform templates.

Source logos are original MediaFlow assets checked into the separate native
repository as base64. No runtime network, original repo edit, or user data access.
Run AFTER flutter create and BEFORE compiling. Requires Pillow for icon sizes.
"""
import argparse
import base64
import json
from pathlib import Path
import re
import shutil
from io import BytesIO

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PACKAGE_ID = "com.alexgodly.mediaflow"
DISPLAY_NAME = "MediaFlow"

def original(filename):
    raw = (ROOT / "tool" / "branding" / (filename + ".base64")).read_text(encoding="ascii").strip()
    return base64.b64decode(raw, validate=True)

def replace_required(path, before, after):
    text = path.read_text(encoding="utf-8")
    if before not in text:
        if after in text:
            return
        raise RuntimeError(f"Expected branding target missing in {path}: {before}")
    path.write_text(text.replace(before, after), encoding="utf-8")

def android(icon, mask):
    root = ROOT / "android" / "app"
    manifest = root / "src/main/AndroidManifest.xml"
    if not manifest.is_file():
        raise RuntimeError("Generate Android Flutter platform before branding")
    text = manifest.read_text(encoding="utf-8")
    text = re.sub(r'android:label="[^"]*"', 'android:label="MediaFlow"', text, count=1)
    text = text.replace('android:icon="@mipmap/ic_launcher"', 'android:icon="@mipmap/ic_launcher"')
    manifest.write_text(text, encoding="utf-8")
    for candidate in [root / "build.gradle.kts", root / "build.gradle"]:
        if not candidate.is_file():
            continue
        contents = candidate.read_text(encoding="utf-8")
        contents, n = re.subn(
            r'(?m)^(\s*(?:namespace|applicationId)\s*=?\s*)["\'][^"\']+["\']',
            lambda m: m.group(1) + '"' + PACKAGE_ID + '"', contents)
        if n < 2:
            raise RuntimeError(f"Could not set Android namespace/applicationId: {candidate}")
        candidate.write_text(contents, encoding="utf-8")
        break
    else:
        raise RuntimeError("Android app Gradle definition not found")
    for src in root.glob("src/main/kotlin/**/MainActivity.kt"):
        kotlin = src.read_text(encoding="utf-8")
        kotlin = re.sub(r'(?m)^package\s+[\w.]+', 'package ' + PACKAGE_ID, kotlin)
        dest = root / "src/main/kotlin/com/alexgodly/mediaflow/MainActivity.kt"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(kotlin, encoding="utf-8")
        if dest != src:
            src.unlink()
    for source_dir in (root / "src/main/java",):
        for src in source_dir.glob("**/MainActivity.java"):
            text = src.read_text(encoding="utf-8")
            text = re.sub(r'(?m)^package\s+[\w.]+;', 'package ' + PACKAGE_ID + ';', text)
            dest = source_dir / "com/alexgodly/mediaflow/MainActivity.java"
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(text, encoding="utf-8")
            if src != dest:
                src.unlink()
    densities = {"mdpi":48, "hdpi":72, "xhdpi":96, "xxhdpi":144, "xxxhdpi":192}
    for density, size in densities.items():
        folder = root / "src/main/res" / ("mipmap-" + density)
        folder.mkdir(parents=True, exist_ok=True)
        icon.resize((size, size), Image.Resampling.LANCZOS).save(folder / "ic_launcher.png")
    # Android 8 adaptive icon foreground is safe within maskable icon's center.
    for density, size in densities.items():
        folder = root / "src/main/res" / ("drawable-" + density)
        folder.mkdir(parents=True, exist_ok=True)
        mask.resize((size * 3, size * 3), Image.Resampling.LANCZOS).save(
            folder / "mediaflow_foreground.png"
        )
    # Use default PNG launcher resource on every Android version; no adaptive XML required.
    print("ANDROID package=" + PACKAGE_ID + " label=" + DISPLAY_NAME + " original-logo=yes")

def ios(icon):
    root = ROOT / "ios" / "Runner"
    pbx = ROOT / "ios" / "Runner.xcodeproj/project.pbxproj"
    if not pbx.is_file():
        raise RuntimeError("Generate iOS Flutter platform before branding")
    contents = pbx.read_text(encoding="utf-8")
    count = len(re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*[^;]+;', contents))
    if count == 0:
        raise RuntimeError("Xcode bundle ID not found")
    contents = re.sub(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*[^;]+;',
                      'PRODUCT_BUNDLE_IDENTIFIER = ' + PACKAGE_ID + ';', contents)
    pbx.write_text(contents, encoding="utf-8")
    info = root / "Info.plist"
    contents = info.read_text(encoding="utf-8")
    contents = re.sub(
        r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
        lambda m: m.group(1) + DISPLAY_NAME + m.group(2), contents,
    )
    contents = re.sub(
        r'(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)',
        lambda m: m.group(1) + DISPLAY_NAME + m.group(2), contents,
    )
    info.write_text(contents, encoding="utf-8")
    icon_dir = root / "Assets.xcassets/AppIcon.appiconset"
    contents_file = icon_dir / "Contents.json"
    values = json.loads(contents_file.read_text(encoding="utf-8"))
    generated = 0
    for entry in values.get("images", []):
        filename = entry.get("filename")
        if not filename:
            continue
        sizes = str(entry["size"]).split("x")
        pixels = round(float(sizes[0]) * int(str(entry["scale"]).rstrip("x")))
        icon.resize((pixels, pixels), Image.Resampling.LANCZOS).convert("RGB").save(
            icon_dir / filename, "PNG"
        )
        generated += 1
    if generated < 10:
        raise RuntimeError("Incomplete iOS AppIcon catalog")
    print("IOS bundle=" + PACKAGE_ID + " label=" + DISPLAY_NAME + " logo-slots=" + str(generated))

def windows():
    root = ROOT / "windows"
    cmake = root / "CMakeLists.txt"
    if not cmake.is_file():
        raise RuntimeError("Generate Windows Flutter platform before branding")
    contents = cmake.read_text(encoding="utf-8")
    contents, edits = re.subn(
        r'set\(BINARY_NAME\s+"[^"]+"\)',
        'set(BINARY_NAME "MediaFlow")', contents,
    )
    if edits != 1:
        raise RuntimeError("Windows executable name target missing")
    cmake.write_text(contents, encoding="utf-8")
    ico = root / "runner/resources/app_icon.ico"
    ico.parent.mkdir(parents=True, exist_ok=True)
    ico.write_bytes(original("mediaflow.ico"))
    runner = root / "runner/Runner.rc"
    if runner.is_file():
        contents = runner.read_text(encoding="utf-8")
        contents = re.sub(r'VALUE "FileDescription",\s*"[^"]*"', 'VALUE "FileDescription", "MediaFlow"', contents)
        contents = re.sub(r'VALUE "ProductName",\s*"[^"]*"', 'VALUE "ProductName", "MediaFlow"', contents)
        runner.write_text(contents, encoding="utf-8")
    print("WINDOWS executable=MediaFlow.exe logo=original-MediaFlow.ico")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--platforms", required=True)
    args = parser.parse_args()
    raw = original("mediaflow-launcher-512.png")
    mask = original("mediaflow-maskable-512.png")
    icon = Image.open(BytesIO(raw)).convert("RGBA")
    foreground = Image.open(BytesIO(mask)).convert("RGBA")
    if icon.size != (512,512) or foreground.size != (512,512):
        raise RuntimeError("Untrusted logo dimensions")
    for platform in args.platforms.split(","):
        name = platform.strip().lower()
        if name == "android": android(icon, foreground)
        elif name == "ios": ios(icon)
        elif name == "windows": windows()
        else: raise RuntimeError("Unknown platform: " + name)

if __name__ == "__main__":
    main()
