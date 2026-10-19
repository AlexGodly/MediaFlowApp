"""Android releases must never silently reuse a tag or drop an APK."""
from pathlib import Path
import re
src = Path("app/build.gradle.kts").read_text()
pipeline = Path(".github/workflows/android-webview-release.yml").read_text()
notes = Path("docs/releases/android-webview-v1.0.0-beta.3.md")
assert 'versionCode = 3' in src
assert 'versionName = "1.0.0-beta.3"' in src
assert "TAG=android-webview-v1.0.0-beta.3" in pipeline
assert "MediaFlow-v507-Android-WebView-beta3.apk" in pipeline
assert notes.is_file()
assert "dist/MediaFlow-v507-Android-WebView-beta3.apk" in pipeline
assert "gh release create" in pipeline
print("Beta 3 tag, Android version, release assets and notes verified")
