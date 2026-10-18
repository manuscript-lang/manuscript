#!/usr/bin/env python3
"""Compare retained List payload memory in fresh before/after runtime processes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--before", required=True, type=Path)
parser.add_argument("--after", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--runs", default=3, type=int)
parser.add_argument("--cpu", default=0, type=int)
args = parser.parse_args()
if args.runs < 1:
    parser.error("runs must be positive")
os.sched_setaffinity(0, {args.cpu})
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
binaries = {"before": args.before.resolve(), "after": args.after.resolve()}
env = dict(os.environ, GOMAXPROCS="1", GOGC="100")
env.pop("GOMEMLIMIT", None)
rng = random.Random(142)
results = {}
for mode in ("clear", "prefix", "remove", "overwrite", "release"):
    samples = {label: [] for label in binaries}
    for trial in range(args.runs):
        order = list(binaries)
        rng.shuffle(order)
        for label in order:
            log = output / f"{mode}-{trial+1}-{label}.txt"
            with log.open("w") as stream:
                proc = subprocess.Popen([str(binaries[label]), "-mode", mode], env=env, stdout=stream, stderr=subprocess.STDOUT)
                _, status, usage = os.wait4(proc.pid, 0)
                proc.returncode = os.waitstatus_to_exitcode(status)
            if proc.returncode:
                raise RuntimeError(log.read_text())
            sample = json.loads(log.read_text())
            sample["peak_rss_kib"] = usage.ru_maxrss
            samples[label].append(sample)
    results[mode] = {
        "samples": samples,
        "medians": {label: {key: statistics.median(s[key] for s in values) for key in values[0] if key != "mode"} for label, values in samples.items()},
    }
report = {"cpu": args.cpu, "GOMAXPROCS": 1, "GOGC": 100, "GOMEMLIMIT": "unset", "binary_sha256": {k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in binaries.items()}, "results": results}
(output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps({mode: data["medians"] for mode, data in results.items()}, indent=2))
