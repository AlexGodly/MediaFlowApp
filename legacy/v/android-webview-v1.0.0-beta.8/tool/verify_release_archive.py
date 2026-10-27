#!/usr/bin/env python3
"""Fail GitHub releases unless legacy/v/<tag> exactly mirrors tracked release source.

Avoids recursive nesting by deliberately excluding the shared legacy/ directory,
and permits exactly one extra generated ARCHIVE_METADATA.md file inside the archive.
"""
import argparse
import hashlib
import pathlib
import subprocess
import sys

def tracked_sources():
    proc = subprocess.run(["git", "ls-files", "-z"], capture_output=True, check=True)
    files = [pathlib.Path(raw.decode("utf-8")) for raw in proc.stdout.split(b"\0") if raw]
    return sorted((p for p in files if p.parts[0] != "legacy"), key=str)

def sha256(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(data)
    return hasher.hexdigest()

def verify(tag):
    if not tag.startswith("android-webview-v1.0.0-beta."):
        raise ValueError("Unsupported archive tag")
    root = pathlib.Path("legacy") / "v" / tag
    if not (root / "ARCHIVE_METADATA.md").is_file():
        raise ValueError(f"Archive manifest missing: {root}")
    files = tracked_sources()
    expected = set(files)
    actual = set(p.relative_to(root) for p in root.rglob("*")
                 if p.is_file() and p.name != "ARCHIVE_METADATA.md")
    missing = expected - actual
    extras = actual - expected
    changed = [str(p) for p in files if p in actual and sha256(p) != sha256(root / p)]
    if missing or extras or changed:
        raise ValueError("Archive does not match the release source: "
            f"missing={list(map(str, sorted(missing, key=str)))[:8]}, "
            f"extra={list(map(str, sorted(extras, key=str)))[:8]}, "
            f"modified={changed[:8]}")
    print(f"Source archive matches {len(files)} tracked files: {tag}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    try:
        verify(args.tag)
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
