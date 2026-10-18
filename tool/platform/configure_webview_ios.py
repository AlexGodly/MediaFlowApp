#!/usr/bin/env python3
"""Set platform minimum required by Flutter InAppWebView Forge on iOS."""
from pathlib import Path
import re

podfile = Path('ios/Podfile')
if not podfile.exists():
    raise SystemExit('Generate iOS platform with flutter create first')
data = podfile.read_text(encoding='utf-8')
line = "platform :ios, '15.0'"
data, found = re.subn(
    r"(?m)^\s*#?\s*platform :ios, ['\"][0-9.]+['\"]\s*$",
    line, data)
if not found:
    data = line + '\n' + data
podfile.write_text(data, encoding='utf-8')

project = Path('ios/Runner.xcodeproj/project.pbxproj')
if project.exists():
    data = project.read_text(encoding='utf-8')
    data = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;',
                  'IPHONEOS_DEPLOYMENT_TARGET = 15.0;', data)
    project.write_text(data, encoding='utf-8')

framework = Path('ios/Flutter/AppFrameworkInfo.plist')
if framework.exists():
    data = framework.read_text(encoding='utf-8')
    data = re.sub(r'(<key>MinimumOSVersion</key>\s*<string>)[0-9.]+(</string>)',
                  r'\g<1>15.0\g<2>', data)
    framework.write_text(data, encoding='utf-8')
print('MediaFlow WebView iOS minimum deployment target 15.0 verified')
