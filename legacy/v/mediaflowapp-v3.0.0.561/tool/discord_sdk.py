#!/usr/bin/env python3
"""Fetch the Discord Social SDK for a CI build (Discord Rich Presence).

The SDK is Discord's licensed binary, so it is not part of this public
repository: CI downloads it from the owner's private release
(AlexGodly/discord-social-sdk) with the read-only DISCORD_SDK_TOKEN secret and
keeps only the part one platform needs, under .discord-sdk/out/<platform>/:

  android  discord_partner_sdk.aar
  windows  discord_partner_sdk.dll
  ios      discord_partner_sdk.xcframework/

tool/prepare_platforms.py then wires it into the generated project. Without
the token (forks, local builds) nothing is fetched and the app is built
without Rich Presence (Settings says it is not available in that build).

  python tool/discord_sdk.py <android|windows|ios>
"""
import os
import pathlib
import shutil
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = "1.10.19337"
REPO = "AlexGodly/discord-social-sdk"
ZIP = f"DiscordSocialSdk-{VERSION}.zip"
BASE = ROOT / ".discord-sdk"
PARTS = {
    "android": ["discord_social_sdk/lib/release/discord_partner_sdk.aar"],
    "windows": ["discord_social_sdk/bin/release/discord_partner_sdk.dll"],
    "ios": ["discord_social_sdk/lib/release/discord_partner_sdk.xcframework/"],
}


def main():
    platform = sys.argv[1] if len(sys.argv) > 1 else ""
    if platform not in PARTS:
        sys.exit("usage: discord_sdk.py <android|windows|ios>")
    out = BASE / "out" / platform
    if out.exists() and any(out.iterdir()):
        print(f"Discord Social SDK {VERSION} for {platform}: cached")
        return
    if not os.environ.get("GH_TOKEN"):
        print("::warning title=Discord Rich Presence::DISCORD_SDK_TOKEN is not set; building without the Discord Social SDK")
        return
    BASE.mkdir(exist_ok=True)
    zpath = BASE / ZIP
    if not zpath.exists():
        subprocess.run(["gh", "release", "download", VERSION, "-R", REPO, "-p", ZIP, "-D", str(BASE), "--clobber"], check=True)
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zpath) as z:
        names = z.namelist()
        for part in PARTS[platform]:
            prefix = part.rstrip("/")
            members = [n for n in names if n == prefix or n.startswith(prefix + "/")]
            if not members:
                sys.exit(f"{part} is missing from {ZIP}")
            strip = prefix.rsplit("/", 1)[0] + "/"
            for n in members:
                if n.endswith("/"):
                    continue
                dest = out / n[len(strip):]
                dest.parent.mkdir(parents=True, exist_ok=True)
                with z.open(n) as src, open(dest, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                info = z.getinfo(n)
                mode = (info.external_attr >> 16) & 0o777
                if mode:
                    os.chmod(dest, mode)
    # Framework symlinks inside the xcframework are stored as small files; the
    # iOS slices used here have none, so nothing else to restore.
    zpath.unlink()
    print(f"Discord Social SDK {VERSION} for {platform}: {', '.join(p.name for p in out.iterdir())}")


if __name__ == "__main__":
    main()
