#!/usr/bin/env python3
"""Brand the platform folders that `flutter create` generates in CI.

Run after:  flutter create --platforms=android,ios,windows --org com.alexgodly --project-name mediaflow .
Sets the app name to "MediaFlow", adds Android's INTERNET permission (the
release template omits it), and installs the MediaFlow icon everywhere.
Idempotent; fails loudly if a template file it expects has changed shape.
"""
import pathlib
import re
import shutil
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


NOTIFICATION_RECEIVERS = """
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""


def android_manifest(text):
    for perm in ("INTERNET", "POST_NOTIFICATIONS", "RECEIVE_BOOT_COMPLETED"):
        if f"android.permission.{perm}" not in text:
            text = re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="android.permission.{perm}"/>', text, count=1)
    # The daily streak reminder (flutter_local_notifications) needs its receivers.
    if "ScheduledNotificationReceiver" not in text:
        text, n = re.subn(r"(<application[^>]*>)", lambda m: m.group(1) + NOTIFICATION_RECEIVERS, text, count=1)
        if n != 1:
            sys.exit("AndroidManifest.xml has no <application> element")
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


def android_desugaring(text):
    """flutter_local_notifications (the streak reminder) needs core library
    desugaring."""
    if "isCoreLibraryDesugaringEnabled" not in text:
        text, n = re.subn(r"(compileOptions\s*\{)", r"\1\n        isCoreLibraryDesugaringEnabled = true", text, count=1)
        if n != 1:
            sys.exit("android/app/build.gradle.kts has no compileOptions block")
    if "desugar_jdk_libs" not in text:
        text = text.rstrip() + '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    return text


def android_gradle(text):
    """Release builds use the permanent MediaFlow key when CI provides
    android/key.properties (from the repository secrets); otherwise Flutter's
    debug key, as before. A stable key lets each release install over the last."""
    text = android_desugaring(text)
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


# ---- Discord Rich Presence (when CI fetched the Social SDK, tool/discord_sdk.py) ----

DISCORD_APP_ID = "1554979701787992225"
DISCORD_OUT = ROOT / ".discord-sdk" / "out"


def discord_sdk(platform):
    p = DISCORD_OUT / platform
    return p if p.exists() and any(p.iterdir()) else None


DISCORD_AUTH_ACTIVITY = f"""
        <!-- Discord account linking (Discord Social SDK) -->
        <activity android:name="com.discord.socialsdk.AuthenticationActivity"
                  android:theme="@android:style/Theme.Translucent.NoTitleBar"
                  android:launchMode="singleTask"
                  android:exported="true"
                  tools:replace="android:theme,android:launchMode,android:exported">
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="discord-{DISCORD_APP_ID}" />
            </intent-filter>
        </activity>
        <!-- Voice chat is not used: drop the SDK's call service. -->
        <service android:name="com.discord.socialsdk.ForegroundService" tools:node="remove" />
"""
# The SDK also does voice chat; MediaFlow only sets a status, so its
# microphone / foreground-service / Bluetooth permissions are removed.
DISCORD_UNUSED_PERMISSIONS = [
    "RECORD_AUDIO", "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_MICROPHONE", "FOREGROUND_SERVICE_MEDIA_PLAYBACK",
    "MODIFY_AUDIO_SETTINGS", "BLUETOOTH", "BLUETOOTH_CONNECT",
]


def android_discord_manifest(text):
    if "com.discord.socialsdk.AuthenticationActivity" in text:
        return text
    if "xmlns:tools" not in text:
        text = re.sub(r"<manifest", '<manifest xmlns:tools="http://schemas.android.com/tools"', text, count=1)
    removes = "".join(
        f'\n    <uses-permission android:name="android.permission.{p}" tools:node="remove"/>' for p in DISCORD_UNUSED_PERMISSIONS
    )
    text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + removes, text, count=1)
    text, n = re.subn(r"(<application[^>]*>)", lambda m: m.group(1) + DISCORD_AUTH_ACTIVITY, text, count=1)
    if n != 1:
        sys.exit("AndroidManifest.xml has no <application> element")
    return text


def android_discord_gradle(text):
    if "discord_partner_sdk.aar" in text:
        return text
    deps = (
        '\ndependencies {\n'
        '    implementation(files("libs/discord_partner_sdk.aar"))\n'
        '    implementation("androidx.browser:browser:1.8.0")\n'
        '}\n'
    )
    text = text.rstrip() + "\n" + deps
    # Phones and the emulator only: no 32-bit x86 copy of the SDK in the APK.
    text, n = re.subn(r"^android\s*\{", 'android {\n    packaging { jniLibs { excludes += "lib/x86/**" } }', text, count=1, flags=re.M)
    if n != 1:
        sys.exit("android/app/build.gradle.kts has no android block")
    return text


def android_discord_activity():
    """`DiscordSocialSdkInit.setEngineActivity(this)` in MainActivity.onCreate (Discord's Android setup)."""
    acts = list((ROOT / "android/app/src/main/kotlin").rglob("MainActivity.kt"))
    if len(acts) != 1:
        sys.exit("Expected exactly one MainActivity.kt")
    text = acts[0].read_text(encoding="utf-8")
    if "DiscordSocialSdkInit" in text:
        return
    m = re.search(r"class MainActivity\s*:\s*FlutterActivity\(\)\s*(\{\s*\})?", text)
    if not m:
        sys.exit("MainActivity.kt has an unexpected shape")
    body = """class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Discord Rich Presence: the Social SDK needs the activity for account linking.
        com.discord.socialsdk.DiscordSocialSdkInit.setEngineActivity(this)
    }
}
"""
    text = text[:m.start()] + body + text[m.end():]
    acts[0].write_text(text, encoding="utf-8")


def android_discord():
    sdk = discord_sdk("android")
    if not sdk:
        return
    libs = ROOT / "android/app/libs"
    libs.mkdir(parents=True, exist_ok=True)
    shutil.copy2(sdk / "discord_partner_sdk.aar", libs / "discord_partner_sdk.aar")
    edit("android/app/src/main/AndroidManifest.xml", android_discord_manifest)
    edit("android/app/build.gradle.kts", android_discord_gradle)
    android_discord_activity()
    print("Discord Social SDK added (Android)")


def windows_discord_cmake(text):
    if "discord_partner_sdk.dll" in text:
        return text
    rule = (
        '\n# Discord Rich Presence: the Social SDK next to MediaFlow.exe (fetched by CI).\n'
        'install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../.discord-sdk/out/windows/discord_partner_sdk.dll"\n'
        '  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)\n'
    )
    return text.rstrip() + "\n" + rule


def windows_discord():
    if discord_sdk("windows"):
        edit("windows/CMakeLists.txt", windows_discord_cmake)
        print("Discord Social SDK added (Windows)")


DISCORD_PODSPEC = """Pod::Spec.new do |s|
  s.name = 'DiscordPartnerSdk'
  s.version = '1.10.19337'
  s.summary = 'Discord Social SDK (Rich Presence for MediaFlow)'
  s.homepage = 'https://discord.com/developers/docs/discord-social-sdk/overview'
  s.license = { :type => 'Proprietary', :text => 'Discord Social SDK. See Discord Developer Terms.' }
  s.author = 'Discord'
  s.source = { :path => '.' }
  s.platform = :ios, '15.1'
  s.vendored_frameworks = 'discord_partner_sdk.xcframework'
end
"""


def ios_discord_plist(text):
    if f"discord-{DISCORD_APP_ID}" in text:
        return text
    entries = f"""
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>discord</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>discord-{DISCORD_APP_ID}</string>
			</array>
		</dict>
	</array>
	<key>LSApplicationQueriesSchemes</key>
	<array>
		<string>discord</string>
	</array>"""
    text, n = re.subn(r"(<dict>)", lambda m: m.group(1) + entries, text, count=1)
    if n != 1:
        sys.exit("Info.plist has no top-level dict")
    return text


def ios_discord_podfile(text):
    if "DiscordPartnerSdk" in text:
        return text
    text = re.sub(r"^#?\s*platform :ios, '[0-9.]+'", "platform :ios, '15.1'", text, count=1, flags=re.M)
    if "platform :ios, '15.1'" not in text:
        text = "platform :ios, '15.1'\n" + text
    text, n = re.subn(r"(target 'Runner' do\n)", r"\1  pod 'DiscordPartnerSdk', :path => 'DiscordPartnerSdk'\n", text, count=1)
    if n != 1:
        sys.exit("ios/Podfile has no Runner target")
    return text


def ios_discord(podfile_only=False):
    sdk = discord_sdk("ios")
    if not sdk:
        return
    if not podfile_only:
        dest = ROOT / "ios/DiscordPartnerSdk"
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir(parents=True)
        shutil.copytree(sdk / "discord_partner_sdk.xcframework", dest / "discord_partner_sdk.xcframework", symlinks=True)
        (dest / "DiscordPartnerSdk.podspec").write_text(DISCORD_PODSPEC, encoding="utf-8")
        edit("ios/Runner/Info.plist", ios_discord_plist)
        pbx = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
        if pbx.exists():
            t = pbx.read_text(encoding="utf-8")
            t2 = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 15.1;", t)
            if t2 != t:
                pbx.write_text(t2, encoding="utf-8")
    if (ROOT / "ios/Podfile").exists():
        edit("ios/Podfile", ios_discord_podfile)
        print("Discord Social SDK added (iOS Podfile)")


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
    # flutter_local_notifications_windows still includes <experimental/coroutine>,
    # which newer Visual Studio refuses unless this is defined (for every plugin).
    flag = "add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)"
    if flag not in text:
        text, n = re.subn(r'(add_definitions\(-DUNICODE -D_UNICODE\))', r'\1\n' + flag, text, count=1)
        if n != 1:
            text, n = re.subn(r'(project\([^)]*\)\n)', r'\1' + flag + '\n', text, count=1)
        if n != 1:
            sys.exit("windows/CMakeLists.txt: no place for the coroutine flag")
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
    if sys.argv[1:] == ["ios-podfile"]:
        # After `flutter build ios --config-only` has generated ios/Podfile.
        ios_discord(podfile_only=True)
        return
    platforms = set(sys.argv[1:]) or {"android", "ios", "windows"}
    if "android" in platforms:
        edit("android/app/src/main/AndroidManifest.xml", android_manifest)
        edit("android/app/build.gradle.kts", android_gradle)
        android_discord()
    if "ios" in platforms:
        edit("ios/Runner/Info.plist", ios_plist)
        ios_discord()
    if "windows" in platforms:
        edit("windows/CMakeLists.txt", windows_cmake)
        edit("windows/runner/main.cpp", windows_main)
        edit("windows/runner/Runner.rc", windows_rc, required=False)
        windows_discord()
    icons()
    print("Platform folders branded as", NAME, "for", ", ".join(sorted(platforms)))


if __name__ == "__main__":
    main()
