#!/usr/bin/env python3
"""Turn `flutter analyze` / `flutter test` / build output into GitHub annotations.

Usage: python tool/ci_annotate.py analyze|test|build <logfile>
Annotations are readable through the GitHub API even where raw job logs are not.
"""
import re
import sys


def esc(s):
    return s.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def main():
    kind, path = sys.argv[1], sys.argv[2]
    text = open(path, encoding="utf-8", errors="replace").read()
    lines = text.splitlines()
    if kind == "analyze":
        issues = []
        for line in lines:
            m = re.match(r"\s*(error|warning|info)\s+•\s+(.*?)\s+•\s+(\S+?):(\d+):(\d+)\s+•\s+(\S+)", line)
            if m and m.group(1) in ("error", "warning"):
                sev, msg, f, ln, col, code = m.groups()
                issues.append((sev, f, ln, col, f"{msg} ({code})"))
        for sev, f, ln, col, msg in issues[:8]:
            print(f"::{'error' if sev == 'error' else 'warning'} file={f},line={ln},col={col}::{esc(msg)}")
        if issues:
            summary = "\n".join(f"{s} {f}:{l}:{c} {m}" for s, f, l, c, m in issues[:120])
            print(f"::error title=All analyzer issues ({len(issues)})::{esc(summary)}")
    elif kind == "test":
        blocks, keep = [], 0
        for i, line in enumerate(lines):
            if "[E]" in line or "EXCEPTION CAUGHT" in line or line.lstrip().startswith(("Expected:", "Actual:", "Error:")) \
                    or "Error: " in line or "error:" in line.lower() and ".dart:" in line:
                keep = 14
                blocks.append(f"--- line {i + 1}")
            if keep > 0:
                blocks.append(line[:400])
                keep -= 1
        failing = []
        for line in lines:
            if "[E]" in line and line.strip() not in failing:
                failing.append(line.strip())
        summary = [l.strip() for l in lines if re.search(r"(All tests passed|Some tests failed)", l)]
        if failing or summary:
            print(f"::error title=Failing tests ({len(failing)})::{esc(chr(10).join((failing + summary[-1:])[:200]))}")
        if blocks:
            print(f"::error title=Test failures::{esc(chr(10).join(blocks[:400]))}")
    else:
        hits = [l for l in lines if re.search(r"(error|Error|ERROR|FAILURE|failed)", l)]
        if hits:
            print(f"::error title=Build errors::{esc(chr(10).join(h[:400] for h in hits[:150]))}")


if __name__ == "__main__":
    main()
