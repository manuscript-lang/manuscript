#!/usr/bin/env python3
"""Differential gate: compares `ms-check-dev --json` with the Go `ms check --json`.

usage: diff_check.py [--workers N] [--show K] [FILES...]
Defaults to every tracked .ms file outside toolchain/ and vendor/.
Run from the repository root with both binaries built (./ms and
target/debug/ms-check-dev).
"""
import concurrent.futures as cf
import json
import subprocess
import sys

ROOT = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
GO = f"{ROOT}/ms"
RS = f"{ROOT}/target/debug/ms-check-dev"


def run(cmd, path):
    try:
        p = subprocess.run(cmd + [path, "--json"], capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return {"error": "timeout"}
    try:
        return json.loads(p.stdout)
    except Exception:
        return {"error": (p.stdout + p.stderr)[:400]}


def compare(path):
    go, rs = run([GO, "check"], path), run([RS], path)
    if "error" in rs or "error" in go:
        return path, go, rs, False
    return path, go, rs, go.get("diagnostics", []) == rs.get("diagnostics", [])


def main():
    args = sys.argv[1:]
    workers, show = 2, 10
    files = []
    i = 0
    while i < len(args):
        if args[i] == "--workers":
            workers = int(args[i + 1]); i += 2
        elif args[i] == "--show":
            show = int(args[i + 1]); i += 2
        else:
            files.append(args[i]); i += 1
    if not files:
        out = subprocess.check_output(["git", "ls-files", "*.ms"], cwd=ROOT, text=True).split()
        files = [f"{ROOT}/{f}" for f in out if not f.startswith(("toolchain/", "vendor/"))]
    bad = []
    with cf.ThreadPoolExecutor(workers) as pool:
        for path, go, rs, ok in pool.map(compare, files):
            if not ok:
                bad.append((path, go, rs))
    print(f"{len(files) - len(bad)}/{len(files)} match")
    for path, go, rs in bad[:show]:
        print("---", path.replace(ROOT + "/", ""))
        g = go.get("diagnostics", go.get("error"))
        r = rs.get("diagnostics", rs.get("error"))
        print("  go:", json.dumps(g)[:600])
        print("  rs:", json.dumps(r)[:600])
    if bad:
        with open("/tmp/diff_check_failures.txt", "w") as f:
            f.write("\n".join(p for p, _, _ in bad))
    return 1 if bad else 0


sys.exit(main())
