#!/usr/bin/env python3
"""Mirror every tracked file outside legacy/ into legacy/v/<tag>/ (byte-identical),
plus ARCHIVE_METADATA.md. Run as the LAST step before committing a release, after
`git add`, then `git add legacy/v/<tag>`. verify_release_archive.py checks it in CI."""
import argparse
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--summary", default="")
    args = ap.parse_args()
    dest = ROOT / "legacy" / "v" / args.tag
    if dest.exists():
        shutil.rmtree(dest)
    files = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout.split(b"\0")
    count = 0
    for raw in files:
        if not raw:
            continue
        rel = pathlib.Path(raw.decode("utf-8"))
        if rel.parts[0] == "legacy" or not (ROOT / rel).is_file():
            continue
        target = dest / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / rel, target)
        count += 1
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    version = args.tag.split("-v", 1)[-1]
    (dest / "ARCHIVE_METADATA.md").write_text(
        f"# MediaFlowApp {version} source archive\n\n"
        f"Every tracked source file outside the shared `legacy/` directory, as released in `{args.tag}`.\n\n"
        f"- App: native Flutter (Android `com.alexgodly.mediaflow`, Windows, iOS)\n"
        f"- Parent commit: `{head}`\n"
        + (f"- {args.summary}\n" if args.summary else "")
        + "\nCI verifies every mirrored file byte-for-byte; this metadata file is the only extra file.\n",
        encoding="utf-8",
    )
    print(f"Archived {count} files to {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
