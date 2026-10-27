"""Require a unique Android version, the pinned MediaFlow source and release assets."""
from pathlib import Path
import re

gradle = Path("app/build.gradle.kts").read_text(encoding="utf-8")
workflow = Path(".github/workflows/android-webview-release.yml").read_text(encoding="utf-8")
package_source = Path("tool/package_mediaflow.py").read_text(encoding="utf-8")

match = re.search(r'versionName *= *"1[.]0[.]0-beta[.]([0-9]+)"', gradle)
assert match, "Missing Android beta version"
version = int(match.group(1))
assert f"versionCode = {version}" in gradle, "Android versionCode/versionName mismatch"

source_match = re.search(r'^VERSION = "([0-9]+)"', package_source, re.MULTILINE)
assert source_match, "Missing pinned MediaFlow source version"
source_version = source_match.group(1)
assert source_version == "553", f"Android release must be based on MediaFlow v553, got v{source_version}"

tag = f"android-webview-v1.0.0-beta.{version}"
artifact = f"MediaFlow-v{source_version}-Android-WebView-beta{version}.apk"
source_zip = f"MediaFlow-v{source_version}-Android-source-beta{version}.zip"
notes = Path(f"docs/releases/{tag}.md")
archive = Path("legacy/v") / tag

assert notes.is_file(), f"Missing release notes: {notes}"
assert archive.is_dir(), f"Release source archive missing: {archive}"
assert (archive / "ARCHIVE_METADATA.md").is_file(), "Archive metadata missing"
for required in (
    "app/build.gradle.kts", "README.md", "tool/package_mediaflow.py",
    "tool/android_assets/companion-mode.js", "tool/android_assets/companion-mode.css",
    "tool/android_assets/cloud-state-cas.js", "tool/android_assets/backup-bridge.js",
    "tests/cloud-state-cas.test.cjs", "tests/test_package.py", "tests/release_guard.py",
    ".github/workflows/android-webview-release.yml",
):
    assert (archive / required).is_file(), f"Missing archived file: {required}"
for token in (
    f"TAG={tag}", artifact, source_zip, "gh release create",
    "python tool/verify_release_archive.py",
    "node --check tool/android_assets/companion-mode.js",
    "node tests/cloud-state-cas.test.cjs",
    f"dist/{artifact}", f"dist/{source_zip}",
):
    assert token in workflow, f"Release workflow missing {token!r}"

print(f"Release contract verified: {tag} / v{source_version} source / source archive / APK / source ZIP")
