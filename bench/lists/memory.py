#!/usr/bin/env python3
"""Measure fresh-process List construction RSS and Go allocation statistics."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--binary", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--runs", default=3, type=int)
parser.add_argument("--cpu", type=int)
args = parser.parse_args()
if args.runs < 1:
    parser.error("runs must be positive")
binary = args.binary.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
if args.cpu is not None:
    os.sched_setaffinity(0, {args.cpu})
results = []
for n in (1000000, 4000000):
    samples = {"generated": [], "boxed": [], "prototype": []}
    for iteration in range(args.runs):
        order = ("generated", "boxed", "prototype") if iteration % 2 == 0 else ("prototype", "boxed", "generated")
        for mode in order:
            label = f"{mode}-{n}-{iteration + 1}"
            timing = output / f"{label}.time"
            env = dict(os.environ, MS_LIST_MEMORY=mode, MS_LIST_COUNT=str(n))
            log = output / f"{label}.log"
            with log.open("w") as stream:
                start = time.perf_counter()
                process = subprocess.Popen(
                    [str(binary), "-test.run=^TestListMemory$", "-test.v"],
                    stdout=stream, stderr=subprocess.STDOUT, env=env,
                )
                _, status, usage = os.wait4(process.pid, 0)
                seconds = time.perf_counter() - start
                process.returncode = os.waitstatus_to_exitcode(status)
                if process.returncode != 0:
                    raise RuntimeError(f"memory worker failed: {log.read_text()}")
            stdout = log.read_text()
            match = re.search(r'\{"allocated_bytes".*\}', stdout)
            if not match:
                raise RuntimeError(f"missing memory statistics: {stdout}")
            sample = json.loads(match.group())
            sample.update(seconds=seconds, peak_rss_kib=usage.ru_maxrss)
            timing.write_text(json.dumps({"seconds": seconds, "peak_rss_kib": usage.ru_maxrss}) + "\n")
            samples[mode].append(sample)
            print(label, json.dumps(sample), flush=True)
    for mode, values in samples.items():
        results.append({"mode": mode, "elements": n, "samples": values, "medians": {
            key: statistics.median(v[key] for v in values)
            for key in ("seconds", "peak_rss_kib", "allocated_bytes", "allocations", "retained_heap_bytes", "heap_sys_bytes")
        }})
report = {
    "platform": platform.platform(),
    "cpu": next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), "unknown"),
    "affinity": sorted(os.sched_getaffinity(0)),
    "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "dirty": subprocess.check_output(["git", "status", "--porcelain"], text=True),
    "go": subprocess.check_output(["toolchain/go/bin/go", "version"], text=True).strip(),
    "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
    "environment": {key: os.environ.get(key, "default") for key in ("GOMAXPROCS", "GOGC", "GOMEMLIMIT")},
    "results": results,
}
(output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
