#!/usr/bin/env python3
"""Read-only checks for the archived rollback evidence. No benchmark execution."""
import csv
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
manifest = json.loads((ROOT / "manifest.json").read_text())
for name, expected in manifest["files_sha256"].items():
    assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected, name
actual = {str(p.relative_to(ROOT)) for p in ROOT.rglob("*") if p.is_file()}
assert actual == set(manifest["files_sha256"]) | {"manifest.json"}

def function(data):
    start = data.index(b"unsafe fn normalize_kind(")
    return data[start:data.index(b"\n}\n", start) + 3]

baseline = (ROOT / "source-states/baseline.rs.txt").read_bytes()
before = (ROOT / "full-rollback/source-states/before.rs.txt").read_bytes()
after = (ROOT / "full-rollback/source-states/after.rs.txt").read_bytes()
assert function(baseline) == function(after)
assert before.replace(function(before), b"FUNCTION") == after.replace(function(after), b"FUNCTION")
identities = json.loads((ROOT / "inputs/normalize-full-identities.json").read_text())
seen = set()
rows = list(csv.DictReader((ROOT / "full-rollback/performance/samples.csv").open()))
for row in rows:
    key = (row["case"], row["variant"], int(row["pair"]))
    assert key not in seen
    seen.add(key)
    assert [int(row[k]) for k in ("input_bytes", "iterations", "checksum")] == identities[row["case"]]
    assert int(row["elapsed_ns"]) > 0
expected = {(name, variant, pair) for name in identities for variant in ("before", "after") for pair in range(7)}
assert seen == expected
assert not list(ROOT.rglob("*.rs")), "Rust snapshots must be archived as .rs.txt"
print(f"Verified {len(manifest['files_sha256'])} artifact hashes, exact function restoration and {len(rows)} complete raw samples.")
