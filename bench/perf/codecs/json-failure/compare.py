#!/usr/bin/env python3
"""Compare existing Release programs; reject incomplete or failed evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess

parser = argparse.ArgumentParser(__doc__)
parser.add_argument("before", type=Path)
parser.add_argument("after", type=Path)
parser.add_argument("output", type=Path)
parser.add_argument("--pairs", type=int, default=9)
args = parser.parse_args()
if args.pairs < 2:
    parser.error("at least two paired trials are required")
programs = {"before": args.before.resolve(), "after": args.after.resolve()}
cases = [
    (size, 300000 if size <= 16 else 20000 if size == 1024 else 1000 if size == 65536 else 500, shape)
    for shape in ["plain", "escaped", "typed-plain", "typed-escaped"]
    for size in [0, 16, 1024, 65536, 1048576]
]
cases += [(size, 100000 if size <= 16 else 10000, shape)
          for shape in ["valid", "typed-valid"] for size in [0, 16, 1024]]
args.output.mkdir(parents=True, exist_ok=False)
manifest = {"complete": False, "pairs": args.pairs, "cases": cases,
            "binaries": {name: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                         for name, path in programs.items()}}
manifest_path = args.output / "manifest.json"
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
summary = []
with (args.output / "samples.jsonl").open("w") as output:
    for size, rounds, shape in cases:
        selected = []
        for repeat in range(-1, args.pairs):
            order = ["before", "after"] if repeat % 2 == 0 else ["after", "before"]
            for label in order:
                result = subprocess.run([str(programs[label]), str(size), str(rounds), shape],
                                        text=True, capture_output=True, check=True)
                fields = result.stdout.split()
                if (len(fields) != 6 or fields[:4] != [str(size), str(rounds), shape, str(rounds)]
                        or int(fields[4]) <= 0 or int(fields[5]) <= 0):
                    raise RuntimeError(f"invalid identity/checksum/timer: {label}: {result.stdout!r}")
                row = dict(size=size, rounds=rounds, shape=shape, repeat=repeat, label=label,
                           checksum=int(fields[3]), wall_ns=int(fields[4]) / rounds,
                           cpu_ns=int(fields[5]) / rounds)
                selected.append(row)
                output.write(json.dumps(row, separators=(",", ":")) + "\n")
                output.flush()
        for clock in ["wall_ns", "cpu_ns"]:
            b = [r[clock] for r in selected if r["repeat"] >= 0 and r["label"] == "before"]
            a = [r[clock] for r in selected if r["repeat"] >= 0 and r["label"] == "after"]
            summary.append(f"{shape} {size} {clock}: before {statistics.median(b):.3f} "
                           f"[{min(b):.3f},{max(b):.3f}] after {statistics.median(a):.3f} "
                           f"[{min(a):.3f},{max(a):.3f}]")
manifest["complete"] = True
manifest["producer_executions"] = len(cases) * 2 * (args.pairs + 1)
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
print("\n".join(summary))
