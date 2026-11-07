"""One consistent version across pubspec, the in-app label, the release workflow,
release notes and the source archive.

Versions are MAJOR.FEATURE.FIX.WEBSITE (from 2.0.0.560; 1.0.0 to 1.2.0 used
X.Y.Z): pubspec `version: MAJOR.FEATURE.FIX+N` (stores take three numbers), the
in-app label, workflow APP_VERSION and tag 'mediaflowapp-v<label>' carry all
four, published as a normal (latest) GitHub release, never a pre-release. The
build number N keeps counting up so every release installs over the previous one."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
config = (ROOT / "lib/src/config.dart").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")
build = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")

m = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec, re.MULTILINE)
if not m:
    sys.exit("pubspec.yaml version must be X.Y.Z+<build number>")
app_version, build_number = m.group(1), int(m.group(2))
if build_number <= 16:
    sys.exit("Stable releases start at build 17 (Beta 16 was the last pre-release)")
label_m = re.search(r"kAppVersionLabel = '([^']+)'", config)
label = label_m.group(1) if label_m else ""
four = re.fullmatch(r"(\d+\.\d+\.\d+)\.(\d+)", label)
if four:
    if four.group(1) != app_version:
        sys.exit(f"In-app label {label} must start with the pubspec version {app_version}")
    app_version = label
tag = f"mediaflowapp-v{app_version}"

checks = {
    "in-app label": f"kAppVersionLabel = '{app_version}'" in config,
    "workflow APP_VERSION": f"APP_VERSION: {app_version}\n" in workflow,
    "workflow TAG": f"TAG: {tag}\n" in workflow,
    "workflow build input": f"app_version: {app_version}\n" in workflow,
    "stable release (not a pre-release)": "--prerelease" not in workflow and "--latest" in workflow,
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
print(f"Release contract verified: {tag} (stable; Android, Windows, iOS)")
