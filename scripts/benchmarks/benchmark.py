#!/usr/bin/env python3
"""Build checked native workloads and compare two Manuscript CLIs."""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--before", required=True, type=Path)
parser.add_argument("--after", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--runs", default=3, type=int)
parser.add_argument("--cpu", type=int, help="pin executions to one CPU (Linux)")
args = parser.parse_args()
if args.runs < 1:
    parser.error("--runs must be positive")
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
workloads = ("numeric", "calls", "list", "life")
clis = {"before": args.before.resolve(), "after": args.after.resolve()}
for name in workloads:
    source = Path(__file__).resolve().parent / f"{name}.ms"
    for label, cli in clis.items():
        subprocess.run([str(cli), "build", str(source), "--build-type", "Release", "-o", str(output / f"{name}-{label}")], check=True)
        subprocess.run([str(cli), "emit", str(source), "-o", str(output / f"{name}-{label}.go")], check=True)
if args.cpu is not None:
    os.sched_setaffinity(0, {args.cpu})
results = {}
for name in workloads:
    samples = {label: [] for label in clis}
    # One correctness/warm-up execution per binary, excluded from measurements.
    for label in clis:
        subprocess.run([str(output / f"{name}-{label}")], check=True)
    for iteration in range(args.runs):
        # Alternate first runner to reduce order-dependent host noise.
        order = ("before", "after") if iteration % 2 == 0 else ("after", "before")
        for label in order:
            start = time.perf_counter()
            subprocess.run([str(output / f"{name}-{label}")], check=True)
            elapsed = time.perf_counter() - start
            samples[label].append(elapsed)
            print(f"{name} {label} run {iteration + 1}: {elapsed:.6f}s", flush=True)
    medians = {label: statistics.median(values) for label, values in samples.items()}
    results[name] = {"seconds": samples, "median_seconds": medians, "speedup": medians["before"] / medians["after"]}
report = {"platform": platform.platform(), "build_type": "Release", "runs": args.runs, "cpu_affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None, "clis": {k: str(v) for k, v in clis.items()}, "results": results}
(output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
