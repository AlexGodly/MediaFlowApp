"""Require a unique version, a real APK publishing step, and an archived source tree."""
from pathlib import Path
import re

gradle = Path("app/build.gradle.kts").read_text(encoding="utf-8")
workflow = Path(".github/workflows/android-webview-release.yml").read_text(encoding="utf-8")
match = re.search(r'versionName\s*=\s*"1\.0\.0-beta\.(\d+)"', gradle)
assert match, "Missing Android beta version"
version = int(match.group(1))
assert f"versionCode = {version}" in gradle, "Android versionCode/versionName mismatch"
tag = f"android-webview-v1.0.0-beta.{version}"
artifact = f"MediaFlow-v507-Android-WebView-beta{version}.apk"
source_zip = f"MediaFlow-v507-Android-source-beta{version}.zip"
notes = Path(f"docs/releases/{tag}.md")
archive = Path("legacy/v") / tag

assert notes.is_file(), f"Missing release notes: {notes}"
assert archive.is_dir(), f"Release source archive missing: {archive}"
assert (archive / "ARCHIVE_METADATA.md").is_file(), "Archive metadata missing"
for required in ("app/build.gradle.kts", "README.md", "tool/package_mediaflow.py",
                 "tool/android_assets/companion-mode.js", "tool/android_assets/companion-mode.css",
                 "tests/test_package.py", "tests/release_guard.py",
                 ".github/workflows/android-webview-release.yml"):
    assert (archive / required).is_file(), f"Missing archived file: {required}"
for token in (f"TAG={tag}", artifact, source_zip, "gh release create",
              "python tool/verify_release_archive.py",
              "node --check tool/android_assets/companion-mode.js",
              f"dist/{artifact}", f"dist/{source_zip}"):
    assert token in workflow, f"Release workflow missing {token!r}"

print(f"Release contract verified: {tag} / source archive / Android APK / source ZIP")
