"""One consistent version across pubspec, the in-app label, the release workflow,
release notes and the source archive."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
config = (ROOT / "lib/src/config.dart").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
build = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")

m = re.search(r"^version:\s*1\.0\.0\+(\d+)\s*$", pubspec, re.MULTILINE)
if not m:
    sys.exit("pubspec.yaml version must be 1.0.0+<beta number>")
beta = int(m.group(1))
app_version = f"1.0.0-beta.{beta}"
tag = f"mediaflowapp-v{app_version}"

checks = {
    "in-app label": f"kAppVersionLabel = '1.0.0 Beta {beta}'" in config,
    "workflow APP_VERSION": f"APP_VERSION: {app_version}" in workflow,
    "workflow TAG": f"TAG: {tag}" in workflow,
    "workflow build input": f"app_version: {app_version}" in workflow,
    "release notes": (ROOT / f"docs/releases/{tag}.md").is_file(),
    "source archive": (ROOT / "legacy/v" / tag / "ARCHIVE_METADATA.md").is_file(),
    "Android build": "flutter build apk --release" in build,
    "Windows build": "flutter build windows --release" in build,
    "iOS build": "flutter build ios --release --no-codesign" in build,
}
for name in ("-Android.apk", "-Windows-x64-Setup.exe", "-Windows-x64-portable.zip", "-iOS-unsigned.ipa", "gh release create"):
    checks[f"release asset {name}"] = name in workflow
failed = [k for k, ok in checks.items() if not ok]
if failed:
    sys.exit("Release contract failed: " + ", ".join(failed))
print(f"Release contract verified: {tag} (Android, Windows, iOS)")
