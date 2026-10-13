#!/usr/bin/env python3
"""Compare cached native execution of issue 148's original contention test."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--before", required=True, type=Path)
parser.add_argument("--after", required=True, type=Path)
parser.add_argument("--source", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--runs", default=5, type=int)
args = parser.parse_args()
if args.runs < 1:
    parser.error("--runs must be positive")
source = args.source.resolve()
clis = {"unoptimized": args.before.resolve(), "candidate": args.after.resolve()}
samples = {label: [] for label in clis}
outputs = {label: [] for label in clis}

def run(label):
    result = subprocess.run([str(clis[label]), "test", str(source), "--filter",
                             "parent holds lock while a running child waits for it",
                             "--timeout", "3s"], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=10, check=True)
    if "1 tests, 0 failed" not in result.stdout:
        raise RuntimeError("the original contention test was not executed: " + result.stdout)
    return result.stdout

# Compilation/cache preparation and one correctness warm-up are excluded.
for label in clis:
    run(label)
for iteration in range(args.runs):
    order = list(clis) if iteration % 2 == 0 else list(clis)[::-1]
    for label in order:
        start = time.perf_counter()
        stdout = run(label)
        elapsed = time.perf_counter() - start
        samples[label].append(elapsed)
        outputs[label].append(stdout)
        print(f"{label} round {iteration + 1}: {elapsed:.6f}s", flush=True)
report = {"source": str(source), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
          "clis": {label: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                   for label, path in clis.items()},
          "seconds": samples, "median_seconds": {label: statistics.median(values) for label, values in samples.items()},
          "outputs": outputs, "includes": "CLI startup, cached native lookup and original 20 ms/100 ms program",
          "cpu_affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None}
args.output.write_text(json.dumps(report, indent=2) + "\n")
