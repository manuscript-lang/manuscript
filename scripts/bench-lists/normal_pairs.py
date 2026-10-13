#!/usr/bin/env python3
"""Paired normal-GC source-runtime comparison of List traversal changes."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import statistics
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--before", required=True, type=Path)
parser.add_argument("--after", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--count", default=12, type=int)
parser.add_argument("--cpu", default=0, type=int)
parser.add_argument("--benchtime", default="200ms")
args = parser.parse_args()
if args.count < 2:
    parser.error("count must be at least two")
os.sched_setaffinity(0, {args.cpu})
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
binaries = {"before": args.before.resolve(), "after": args.after.resolve()}
env = dict(os.environ, GOMAXPROCS="1", GOGC="100")
env.pop("GOMEMLIMIT", None)
pattern = re.compile(r"BenchmarkNarrowSnapshots/(\w+)(?:-\d+)?\s+\d+\s+([\d.]+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op")
rng = random.Random(20261013)
pairs = []
for i in range(args.count):
    order = ["before", "after"]
    rng.shuffle(order)
    pair = {}
    for label in order:
        result = subprocess.run([str(binaries[label]), "-test.run=^Test(ListGeneratedParity|NarrowSnapshotParity)$", "-test.bench=^BenchmarkNarrowSnapshots$", "-test.benchmem", "-test.benchtime=" + args.benchtime], env=env, check=True, capture_output=True, text=True)
        (output / f"pair-{i+1}-{label}.txt").write_text(result.stdout + result.stderr)
        pair[label] = {name: {"ns": float(ns), "bytes": int(byte_count), "allocations": int(allocs)} for name, ns, byte_count, allocs in pattern.findall(result.stdout)}
        if set(pair[label]) != {"ReadOnly", "WriteInCallback", "WriteAfterCallback"}:
            raise RuntimeError(f"missing benchmark cases: {result.stdout}")
    pairs.append(pair)
    print(i + 1, {name: pair["after"][name]["ns"] / pair["before"][name]["ns"] for name in pair["before"]}, flush=True)
summary = {}
bootstrap = random.Random(142)
for name in pairs[0]["before"]:
    logs = [math.log(p["after"][name]["ns"] / p["before"][name]["ns"]) for p in pairs]
    resamples = sorted(math.exp(statistics.mean(bootstrap.choices(logs, k=len(logs)))) for _ in range(10000))
    summary[name] = {
        "geomean_after_before": math.exp(statistics.mean(logs)),
        "paired_95_percent_interval": [resamples[250], resamples[9749]],
        "after_faster_pairs": sum(x < 0 for x in logs),
        "median_before_ns": statistics.median(p["before"][name]["ns"] for p in pairs),
        "median_after_ns": statistics.median(p["after"][name]["ns"] for p in pairs),
        "median_before_bytes": statistics.median(p["before"][name]["bytes"] for p in pairs),
        "median_after_bytes": statistics.median(p["after"][name]["bytes"] for p in pairs),
        "median_before_allocations": statistics.median(p["before"][name]["allocations"] for p in pairs),
        "median_after_allocations": statistics.median(p["after"][name]["allocations"] for p in pairs),
    }
report = {"platform": platform.platform(), "cpu_affinity": sorted(os.sched_getaffinity(0)), "GOMAXPROCS": 1, "GOGC": 100, "GOMEMLIMIT": "unset", "pairs": pairs, "summary": summary, "binary_sha256": {k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in binaries.items()}, "benchtime": args.benchtime, "seed": 20261013}
(output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(summary, indent=2))
