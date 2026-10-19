#!/usr/bin/env python3
"""Pin and package the exact MediaFlow v507 release frontend into Android assets.

No Supabase schema/keys/state are modified. Any downloaded CDN JavaScript becomes
a local app asset (so weak mobile connections do not block the UI shell startup).
"""
import argparse
import hashlib
import json
import re
import shutil
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

VERSION = "507"
ARCHIVE_SHA256 = "12ea38109649b4467ba069e00ab2b1d9a1daab3c4f9af4f9d0013de693c8414a"
ARCHIVE_URL = "https://github.com/AlexGodly/MediaFlow/releases/download/507/MediaFlow_v507_Stable.zip"
CDN = {
    "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2": "assets/vendor/supabase-js-v2.js",
    "https://cdn.jsdelivr.net/npm/react@18.3.1/umd/react.production.min.js": "assets/vendor/react-18.3.1.js",
    "https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/react-dom.production.min.js": "assets/vendor/react-dom-18.3.1.js",
}
EXACT = {"index.html", "manifest.json", "version.json", "sw.js", "favicon.ico", "icon.svg"}
MAX_FILE_BYTES = 80_000_000


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def package(archive, output, skip_vendor=False, verify=True):
    archive, output = Path(archive), Path(output)
    if verify and sha256(archive) != ARCHIVE_SHA256:
        raise ValueError("MediaFlow v507 release archive SHA-256 mismatch")
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        files = [n for n in z.namelist() if not n.endswith("/")]
        index_candidates = []
        for name in files:
            path = PurePosixPath(name)
            if path.name != "index.html" or any(v in path.parts for v in ("legacy", "node_modules")):
                continue
            root = str(path.parent)
            base = "" if root == "." else root + "/"
            if base + "assets/js/mediaflow-v507.bundle.js" in files:
                index_candidates.append(base)
        if not index_candidates:
            raise ValueError("No MediaFlow v507 index + matching compiled bundle found")
        base = min(index_candidates, key=lambda p: (len(PurePosixPath(p).parts), len(p)))
        copied = []
        for member in z.infolist():
            path = PurePosixPath(member.filename)
            if member.is_dir() or not member.filename.startswith(base):
                continue
            rel = str(path)[len(base):]
            clean = PurePosixPath(rel)
            if not rel or clean.is_absolute() or ".." in clean.parts:
                continue
            if not (rel in EXACT or rel.startswith("assets/")):
                continue
            if member.file_size > MAX_FILE_BYTES:
                raise ValueError(f"Oversized asset: {rel}")
            dest = output.joinpath(*clean.parts)
            dest.parent.mkdir(parents=True, exist_ok=True)
            with z.open(member) as source, dest.open("wb") as target:
                shutil.copyfileobj(source, target)
            copied.append(rel)

    index = output / "index.html"
    html = index.read_text("utf-8")
    if not re.search(r'<meta name="mediaflow-version" content="507">', html):
        raise ValueError("Bundled index.html is not v507")
    for source, target in CDN.items():
        if source not in html:
            raise ValueError(f"Expected upstream runtime library absent: {source}")
        html = html.replace(source, target)
    index.write_text(html, "utf-8")
    for local in re.findall(r'(?:src|href)="(assets/[^"]+)"', html):
        if not (output / local.split("?")[0]).exists() and local not in CDN.values():
            raise ValueError(f"Referenced local asset missing: {local}")
    if not skip_vendor:
        for source, target in CDN.items():
            dest = output / target
            dest.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(urllib.request.Request(source, headers={"User-Agent": "MediaFlowApp-Android/1.0"}), timeout=90) as response:
                data = response.read(18_000_000)
            if len(data) < 10_000 or not (b"function" in data or b"supabase" in data.lower()):
                raise ValueError(f"Unexpected CDN JavaScript for {source}")
            dest.write_bytes(data)

    missing = [p for p in CDN.values() if not (output / p).is_file()]
    if missing:
        raise ValueError(f"Missing bundled runtime dependencies: {missing}")
    manifest = {
        "basedOnMediaFlow": VERSION,
        "sourceRelease": ARCHIVE_URL,
        "sourceSha256": ARCHIVE_SHA256 if verify else sha256(archive),
        "assets": len(copied),
        "bundleSha256": sha256(output / "assets/js/mediaflow-v507.bundle.js"),
        "vendoredDependencies": {name: sha256(output / path) for name, path in CDN.items()},
    }
    (output / "mediaflow-android-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", default=".downloads/MediaFlow_v507_Stable.zip")
    parser.add_argument("--output", default="app/src/main/assets/www")
    parser.add_argument("--skip-vendor", action="store_true")
    parser.add_argument("--skip-hash", action="store_true")
    args = parser.parse_args()
    package(args.archive, args.output, skip_vendor=args.skip_vendor, verify=not args.skip_hash)
