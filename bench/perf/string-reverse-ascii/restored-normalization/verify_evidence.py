#!/usr/bin/env python3
"""Verify archived evidence without builds, native programs, timing or reruns."""
import csv
import hashlib
import json
from pathlib import Path
import statistics

root = Path(__file__).resolve().parent
manifest = json.loads((root / "manifest.json").read_text())
actual = {str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()}
assert actual == set(manifest["files_sha256"]) | {"manifest.json"}
for name, expected in manifest["files_sha256"].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, name
proof = json.loads((root / "source-proof.json").read_text())

def function(data, name):
    start = data.index(name)
    return data[start:data.index(b"\n}\n", start) + 3]

for state in ("before", "after"):
    data = (root / "source-states" / (state + ".rs.txt")).read_bytes()
    assert hashlib.sha256(data).hexdigest() == proof["source_" + state + "_sha256"]
    normalized = function(data, b"unsafe fn normalize_kind(")
    assert hashlib.sha256(normalized).hexdigest() == proof["normalize_kind_sha256"]
after = (root / "source-states/after.rs.txt").read_bytes()
assert hashlib.sha256(function(after, b"unsafe fn msrt_string_reverse_val(")).hexdigest() == proof["reverse_function_sha256"]
raw_count = 0
for phase, metadata in manifest["completed_phases"].items():
    directory = root / phase
    identities = json.loads((directory / "identities.json").read_text())
    for program in metadata["programs"].values():
        assert hashlib.sha256((directory / "source.ms.txt").read_bytes()).hexdigest() == program["source_sha256"]
        assert hashlib.sha256((directory / "identities.json").read_bytes()).hexdigest() == program["identities_sha256"]
    seen = set()
    values = {}
    samples = list(csv.DictReader((directory / "samples.csv").open()))
    for row in samples:
        key = row["case"], row["variant"], int(row["pair"])
        assert key not in seen
        seen.add(key)
        assert [int(row[k]) for k in ("input_bytes", "iterations", "checksum")] == identities[row["case"]]
        assert int(row["elapsed_ns"]) > 0
        values.setdefault(row["case"], {}).setdefault(row["variant"], []).append(int(row["elapsed_ns"]) / int(row["iterations"]))
    expected = {(name, variant, pair) for name in identities for variant in ("before", "after") for pair in range(metadata["pairs"])}
    assert seen == expected
    adverse = {name for name, variants in values.items() if statistics.median(variants["after"]) > statistics.median(variants["before"])}
    retained = {r["case"] for r in csv.DictReader((directory / "unfavorable-medians.csv").open())}
    assert adverse == retained and len(adverse) == metadata["unfavorable_medians"]
    raw_count += len(samples)
assert not any(p.suffix in (".rs", ".a", ".ll") or p.name == "program" for p in root.rglob("*") if p.is_file())
record = json.loads((root / "record.json").read_text())
assert record["finished_unix"] and len(record["checks"]) == 30
assert all(step["exit_code"] == 0 for step in record["checks"].values())
conformance = json.loads((root / "checks/conform-report.json").read_text())
summary = conformance["summary"]
assert summary["pass"] == summary["total"] == 2394
assert all(summary[k] == 0 for k in ("fail", "expected_fail", "unexpected_pass", "unrecorded"))
assert sum(phase["total"] for phase in conformance["by_phase"].values()) == summary["total"]
integrity = json.loads((root / "checks/conform-input-integrity.json").read_text())
assert integrity["exit_code"] == 0 and integrity["hashes_match"]
assert integrity["before"] == integrity["after"] and integrity["directory_mode"] == "0o555"
for name, expected in record["input_hashes"].items():
    assert integrity["before"][name]["sha256"] == expected
launch = json.loads((root / "launch-record.json").read_text())
assert launch["actual_exit_code"] == 0 and launch["root_tool_cell"] == 82826
print(f"Verified {len(manifest['files_sha256'])} artifact hashes, {raw_count} raw samples across four separate phases, every unfavorable median, and 2394/2394 conformance with unchanged inputs.")
