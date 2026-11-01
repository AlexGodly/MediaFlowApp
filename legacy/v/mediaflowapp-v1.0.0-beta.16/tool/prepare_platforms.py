#!/usr/bin/env python3
"""Brand the platform folders that `flutter create` generates in CI.

Run after:  flutter create --platforms=android,ios,windows --org com.alexgodly --project-name mediaflow .
Sets the app name to "MediaFlow", adds Android's INTERNET permission (the
release template omits it), and installs the MediaFlow icon everywhere.
Idempotent; fails loudly if a template file it expects has changed shape.
"""
import pathlib
import re
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOGO = ROOT / "assets/branding/mediaflow-launcher-512.png"
NAME = "MediaFlow"


def edit(path, fn, required=True):
    p = ROOT / path
    if not p.exists():
        if required:
            sys.exit(f"Missing generated file: {path}")
        return
    before = p.read_text(encoding="utf-8")
    after = fn(before)
    if after != before:
        p.write_text(after, encoding="utf-8")


def android_manifest(text):
    if "android.permission.INTERNET" not in text:
        text = re.sub(r"(<manifest[^>]*>)", r'\1\n    <uses-permission android:name="android.permission.INTERNET"/>', text, count=1)
    text, n = re.subn(r'android:label="[^"]*"', f'android:label="{NAME}"', text, count=1)
    if n != 1:
        sys.exit("AndroidManifest.xml has no android:label to set")
    return text


SIGNING_PROPS = """
val mediaflowKeystoreProperties = Properties()
val mediaflowKeystoreFile = rootProject.file("key.properties")
if (mediaflowKeystoreFile.exists()) {
    FileInputStream(mediaflowKeystoreFile).use { mediaflowKeystoreProperties.load(it) }
}
"""

SIGNING_CONFIG = """
    signingConfigs {
        create("mediaflowRelease") {
            if (mediaflowKeystoreFile.exists()) {
                keyAlias = mediaflowKeystoreProperties.getProperty("keyAlias")
                keyPassword = mediaflowKeystoreProperties.getProperty("keyPassword")
                storeFile = file(mediaflowKeystoreProperties.getProperty("storeFile"))
                storePassword = mediaflowKeystoreProperties.getProperty("storePassword")
            }
        }
    }
"""


def android_gradle(text):
    """Release builds use the permanent MediaFlow key when CI provides
    android/key.properties (from the repository secrets); otherwise Flutter's
    debug key, as before. A stable key lets each beta install over the last."""
    if "mediaflowRelease" in text:
        return text
    m = re.search(r"^plugins\s*\{.*?^\}\s*$", text, re.S | re.M)
    if not m:
        sys.exit("android/app/build.gradle.kts has no plugins block")
    text = text[:m.end()] + "\n" + SIGNING_PROPS + text[m.end():]
    # In the Kotlin DSL `java.` means the java extension, so import the classes.
    text = "import java.io.FileInputStream\nimport java.util.Properties\n\n" + text
    text, n = re.subn(r"^android\s*\{\s*$", "android {" + SIGNING_CONFIG.rstrip("\n"), text, count=1, flags=re.M)
    if n != 1:
        sys.exit("android/app/build.gradle.kts has no android block")
    text, n = re.subn(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = if (mediaflowKeystoreFile.exists()) signingConfigs.getByName("mediaflowRelease") '
        'else signingConfigs.getByName("debug")',
        text, count=1)
    if n != 1:
        sys.exit("android/app/build.gradle.kts release buildType has no debug signingConfig to replace")
    return text


def ios_plist(text):
    for key in ("CFBundleDisplayName", "CFBundleName"):
        text, n = re.subn(rf"(<key>{key}</key>\s*<string>)[^<]*(</string>)", rf"\g<1>{NAME}\g<2>", text, count=1)
        if n != 1:
            sys.exit(f"Info.plist has no {key}")
    return text


def windows_cmake(text):
    text, n = re.subn(r'set\(BINARY_NAME "[^"]*"\)', f'set(BINARY_NAME "{NAME}")', text, count=1)
    if n != 1:
        sys.exit("windows/CMakeLists.txt has no BINARY_NAME")
    return text


def windows_main(text):
    text, n = re.subn(r'window\.Create\(L"[^"]*"', f'window.Create(L"{NAME}"', text, count=1)
    if n != 1:
        sys.exit("windows/runner/main.cpp has no window title")
    return text


def windows_rc(text):
    for field in ("FileDescription", "InternalName", "ProductName"):
        text = re.sub(rf'(VALUE "{field}", )"[^"]*"', rf'\1"{NAME}"', text)
    text = re.sub(r'(VALUE "OriginalFilename", )"[^"]*"', rf'\1"{NAME}.exe"', text)
    text = re.sub(r'(VALUE "CompanyName", )"[^"]*"', r'\1"Alex Godly"', text)
    return text


def icons():
    logo = Image.open(LOGO).convert("RGBA")
    # Android launcher icons
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        out = ROOT / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        if out.parent.exists():
            logo.resize((size, size), Image.Resampling.LANCZOS).save(out)
    # iOS: replace every template icon with the logo at the same pixel size (opaque).
    appicon = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    if appicon.exists():
        for png in appicon.glob("*.png"):
            w, h = Image.open(png).size
            logo.resize((w, h), Image.Resampling.LANCZOS).convert("RGB").save(png)
    # Windows
    ico = ROOT / "windows/runner/resources/app_icon.ico"
    if ico.parent.exists():
        logo.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


def main():
    platforms = set(sys.argv[1:]) or {"android", "ios", "windows"}
    if "android" in platforms:
        edit("android/app/src/main/AndroidManifest.xml", android_manifest)
        edit("android/app/build.gradle.kts", android_gradle)
    if "ios" in platforms:
        edit("ios/Runner/Info.plist", ios_plist)
    if "windows" in platforms:
        edit("windows/CMakeLists.txt", windows_cmake)
        edit("windows/runner/main.cpp", windows_main)
        edit("windows/runner/Runner.rc", windows_rc, required=False)
    icons()
    print("Platform folders branded as", NAME, "for", ", ".join(sorted(platforms)))


if __name__ == "__main__":
    main()
