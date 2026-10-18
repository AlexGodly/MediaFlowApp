#!/usr/bin/env python3
"""Compatibility fix for flutter_inappwebview_forge_windows 1.x CMake target.

The released CMakeLists.txt defines a Windows plugin target without the
"_forge_" infix, while recent generated Flutter plugin registrants refer to
the Dart package's flutter_inappwebview_forge_windows_plugin target.
Adjust only this known mismatch; fail closed for unfamiliar plugin versions.
Must run after flutter pub get creates Windows plugin symlinks.
"""
from pathlib import Path

cmake = Path(
    "windows/flutter/ephemeral/.plugin_symlinks/"
    "flutter_inappwebview_forge_windows/windows/CMakeLists.txt"
)
if not cmake.is_file():
    raise SystemExit("Forge Windows plugin missing; run flutter pub get first")
source = cmake.read_text(encoding="utf-8")
old = 'set(PLUGIN_NAME "flutter_inappwebview_windows_plugin")'
new = 'set(PLUGIN_NAME "flutter_inappwebview_forge_windows_plugin")'
if old in source:
    source = source.replace(old, new, 1)
elif new not in source:
    raise SystemExit("Unexpected Forge Windows plugin target; no patch applied")
# Current CMake's add_custom_command(TARGET) no longer accepts DEPENDS.
source = source.replace("  DEPENDS ${NUGET}\n", "")
cmake.write_text(source, encoding="utf-8")
print("Verified Forge Windows CMake target compatibility")
