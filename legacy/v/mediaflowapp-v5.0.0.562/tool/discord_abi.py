#!/usr/bin/env python3
"""Check the app's Discord bindings against the SDK's C header (CI only).

lib/src/platform/discord_ffi.dart looks up C functions by name and declares
their parameters by hand; a wrong parameter type would crash at runtime. Each
function below lists the parameter types the Dart side passes. When the header
from the SDK download is present (.discord-sdk/cdiscord.h), every function must
exist with exactly these parameters; otherwise the build fails and prints the
real declaration. Without the header (no SDK token) there is nothing to check.

  python tool/discord_abi.py
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HEADER = ROOT / ".discord-sdk/cdiscord.h"

# name -> parameter types after `self` (as written in cdiscord.h, spaces ignored)
EXPECTED = {
    "Discord_Activity_SetName": ["Discord_String"],
    "Discord_Activity_SetType": ["Discord_ActivityTypes"],
    "Discord_Activity_SetStatusDisplayType": ["Discord_StatusDisplayTypes*"],
    "Discord_Activity_SetState": ["Discord_String*"],
    "Discord_Activity_SetDetails": ["Discord_String*"],
    "Discord_Activity_SetAssets": ["Discord_ActivityAssets*"],
    "Discord_Activity_SetTimestamps": ["Discord_ActivityTimestamps*"],
    "Discord_ActivityAssets_SetLargeImage": ["Discord_String*"],
    "Discord_ActivityAssets_SetLargeText": ["Discord_String*"],
    "Discord_ActivityAssets_SetSmallImage": ["Discord_String*"],
    "Discord_ActivityAssets_SetSmallText": ["Discord_String*"],
    "Discord_ActivityTimestamps_SetStart": ["uint64_t"],
    # Custom Status (5.0.0)
    "Discord_ActivityTimestamps_SetEnd": ["uint64_t"],
    "Discord_Activity_SetParty": ["Discord_ActivityParty*"],
    "Discord_ActivityParty_Init": [],
    "Discord_ActivityParty_Drop": [],
    "Discord_ActivityParty_SetId": ["Discord_String"],
    "Discord_ActivityParty_SetCurrentSize": ["int32_t"],
    "Discord_ActivityParty_SetMaxSize": ["int32_t"],
    "Discord_ActivityButton_Init": [],
    "Discord_ActivityButton_Drop": [],
    "Discord_ActivityButton_SetLabel": ["Discord_String"],
    "Discord_ActivityButton_SetUrl": ["Discord_String"],
    "Discord_Activity_AddButton": ["Discord_ActivityButton*"],
    "Discord_Activity_SetDetailsUrl": ["Discord_String*"],
    "Discord_Activity_SetStateUrl": ["Discord_String*"],
    "Discord_ActivityAssets_SetLargeUrl": ["Discord_String*"],
    "Discord_ActivityAssets_SetSmallUrl": ["Discord_String*"],
}

# Optional: the app hides the option when the SDK lacks the function.
OPTIONAL = {
    "Discord_ActivityTimestamps_SetEnd", "Discord_Activity_SetParty", "Discord_ActivityParty_Init",
    "Discord_ActivityParty_Drop", "Discord_ActivityParty_SetId", "Discord_ActivityParty_SetCurrentSize",
    "Discord_ActivityParty_SetMaxSize", "Discord_ActivityButton_Init", "Discord_ActivityButton_Drop",
    "Discord_ActivityButton_SetLabel", "Discord_ActivityButton_SetUrl", "Discord_Activity_AddButton",
    "Discord_Activity_SetDetailsUrl", "Discord_Activity_SetStateUrl",
    "Discord_ActivityAssets_SetLargeUrl", "Discord_ActivityAssets_SetSmallUrl",
}


def main():
    if not HEADER.exists():
        print("discord_abi: no SDK header (build without the Discord SDK): skipped")
        return
    text = HEADER.read_text(encoding="utf-8", errors="replace")
    failed = []
    for name, params in EXPECTED.items():
        # The declaration (ends with ';'), not a mention in a comment.
        m = re.search(r"\b" + re.escape(name) + r"\s*\(([^)]*)\)\s*;", text)
        if not m:
            if name in OPTIONAL:
                print(f"discord_abi: {name} not in this SDK (option hidden)")
                continue
            failed.append(f"{name}: missing")
            continue
        raw = [p.strip() for p in m.group(1).split(",") if p.strip()]
        # Drop parameter names, keep types; drop the leading `self`.
        types = [re.sub(r"\s+", "", re.sub(r"\b\w+$", "", p).strip() or p) for p in raw]
        types = [t.replace("const", "") for t in types][1:]
        if types != params:
            failed.append(f"{name}: header has ({m.group(1).strip()}), app passes {params}")
    if failed:
        print("::error::Discord bindings don't match cdiscord.h:\n  " + "\n  ".join(failed))
        sys.exit(1)
    print(f"discord_abi: {len(EXPECTED)} bindings match cdiscord.h")


if __name__ == "__main__":
    main()
