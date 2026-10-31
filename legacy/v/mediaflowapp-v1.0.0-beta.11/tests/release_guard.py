"""Require one consistent version across Android, Windows, iOS, the release workflow,
the pinned MediaFlow website source, release notes and the source archive."""
from pathlib import Path
import json
import re

gradle = Path("app/build.gradle.kts").read_text(encoding="utf-8")
workflow = Path(".github/workflows/release.yml").read_text(encoding="utf-8")
package_source = Path("tool/package_mediaflow.py").read_text(encoding="utf-8")
desktop = json.loads(Path("desktop/package.json").read_text(encoding="utf-8"))
ios = Path("ios/project.yml").read_text(encoding="utf-8")

match = re.search(r'versionName *= *"1[.]0[.]0-beta[.]([0-9]+)"', gradle)
assert match, "Missing Android beta version"
beta = int(match.group(1))
assert f"versionCode = {beta}" in gradle, "Android versionCode/versionName mismatch"
app_version = f"1.0.0-beta.{beta}"
tag = f"mediaflowapp-v{app_version}"

assert desktop["version"] == app_version, f"Windows app version {desktop['version']} != {app_version}"
assert f'CURRENT_PROJECT_VERSION: "{beta}"' in ios, "iOS build number must equal the beta number"
assert 'MARKETING_VERSION: "1.0.0"' in ios, "iOS marketing version must be 1.0.0"

source_match = re.search(r'^VERSION = "([0-9]+)"', package_source, re.MULTILINE)
assert source_match, "Missing pinned MediaFlow source version"
source_version = source_match.group(1)
assert int(source_version) >= 554, f"App must bundle MediaFlow v554 or newer, got v{source_version}"

notes = Path(f"docs/releases/{tag}.md")
archive = Path("legacy/v") / tag
assert notes.is_file(), f"Missing release notes: {notes}"
assert archive.is_dir(), f"Release source archive missing: {archive}"
assert (archive / "ARCHIVE_METADATA.md").is_file(), "Archive metadata missing"
for required in (
    "app/build.gradle.kts", "README.md", "CLAUDE.md", "tool/package_mediaflow.py",
    "tool/android_assets/companion-mode.js", "tool/android_assets/companion-mode.css",
    "tool/android_assets/cloud-state-cas.js", "tool/android_assets/backup-bridge.js",
    "desktop/main.js", "desktop/package.json", "ios/project.yml",
    "ios/MediaFlow/MediaFlowViewController.swift", "tests/e2e/smoke.py",
    "tests/cloud-state-cas.test.cjs", "tests/test_package.py", "tests/release_guard.py",
    ".github/workflows/release.yml", ".github/workflows/pr-validation.yml",
):
    assert (archive / required).is_file(), f"Missing archived file: {required}"

for token in (
    f"APP_VERSION: {app_version}", f"TAG: {tag}", f"MEDIAFLOW_VERSION: '{source_version}'",
    "gh release create", "python tool/verify_release_archive.py",
    "python tests/e2e/smoke.py", "-Android.apk", "-Windows-x64-Setup.exe",
    "-Windows-x64-portable.exe", "-iOS-unsigned.ipa", "SHA256SUMS.txt",
):
    assert token in workflow, f"Release workflow missing {token!r}"

print(f"Release contract verified: {tag} / MediaFlow v{source_version} / Android + Windows + iOS")
