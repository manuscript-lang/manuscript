#!/usr/bin/env python3
"""Regenerates SYMBOLS.md from the exported items of ms-rt (run from the repository root)."""
import glob
import re

out = ["# ms-rt symbol catalogue", "",
       "Generated from the `#[unsafe(no_mangle)]` items in `crates/ms-rt/src` and `crates/ms-std-*/src` by `crates/ms-rt/gen-symbols.py`; do not edit.",
       "", "```text"]
for f in sorted(glob.glob("crates/ms-rt/src/*.rs") + glob.glob("crates/ms-std-*/src/**/*.rs", recursive=True)):
    s = open(f).read()
    for m in re.finditer(r'#\[unsafe\(no_mangle\)\]\s*pub (?:unsafe )?(?:extern "[^"]+" )?(fn|static)(?: mut)? (\w+)(.*?)(?:\{|=)', s, re.S):
        sig = " ".join(m.group(3).split())
        out.append(f"{m.group(2)}{sig}" if m.group(1) == "fn" else f"{m.group(2)} (data)")
    # Symbols declared through the table macros of the ms-std crates (`name => path` / `name: type = value`).
    for m in re.finditer(r'^\s+(msstd_\w+)\s*(=>[^,\n]*|:\s*(\w+)\s*=)', s, re.M):
        out.append(f"{m.group(1)}(value: f64) -> f64" if m.group(3) is None else f"{m.group(1)}() -> {m.group(3)}")
out.append("```")
open("crates/ms-rt/SYMBOLS.md", "w").write("\n".join(out) + "\n")
