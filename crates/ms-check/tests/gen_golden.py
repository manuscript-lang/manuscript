#!/usr/bin/env python3
"""Regenerates tests/golden.txt from the Go oracle.

usage: gen_golden.py SOURCES.json

SOURCES.json is the list of Manuscript sources found in the Go tests' string
literals (see extract_sources.go.txt: copy it to a scratch directory as
main.go, add a go.mod, and run `go run . <repo root> > sources.json`). Each
source is checked with `./ms check --json`; sources that need other files are
skipped. Run from the repository root with ./ms built.

Format: records separated by \x1e; a record is the source, \x1f, then one
diagnostic per line: phase TAB line TAB column TAB offset TAB message (with
newlines in the message written \\n).
"""
import json
import os
import subprocess
import sys
import tempfile

sources = json.load(open(sys.argv[1]))
root = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
out = []
with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "t.ms")
    for s in sources:
        if "\x1e" in s or "\x1f" in s or "\r" in s:
            continue
        open(path, "w", newline="").write(s)
        p = subprocess.run([f"{root}/ms", "check", path, "--json"], capture_output=True, text=True)
        diags = json.loads(p.stdout)["diagnostics"]
        if any("cannot find module" in x["message"] or "alias" in x["message"] for x in diags):
            continue
        lines = []
        for x in diags:
            pos = x["position"]
            msg = x["message"].replace("\\", "\\\\").replace("\n", "\\n")
            lines.append("\t".join([x["phase"], str(pos["line"]), str(pos["column"]), str(pos["offset"]), msg]))
        out.append(s + "\x1f" + "\n".join(lines))
open(f"{root}/crates/ms-check/tests/golden.txt", "w", newline="").write("\x1e".join(out))
print(len(out), "records")
