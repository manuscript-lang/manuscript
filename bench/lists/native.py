#!/usr/bin/env python3
"""Build Release Manuscript reproductions and measure native wall time/peak RSS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cli", required=True, type=Path)
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--runs", default=3, type=int)
parser.add_argument("--cpu", type=int)
args = parser.parse_args()
if args.runs < 1:
    parser.error("runs must be positive")
cli = args.cli.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
if args.cpu is not None:
    os.sched_setaffinity(0, {args.cpu})
source = (Path(__file__).resolve().parent / "program.ms").read_text()
results = []
for name, n in (("append", 1000000), ("append", 4000000), ("sort", 200000)):
    last = (n - 1) * 7919 % 100003
    body = f"""export fn main() Int:
    let values = build({n})
    if values.length() != {n}: return 1
    if values.first().get() != 0: return 2
    if values.last().get() != {last}: return 3
"""
    if name == "sort":
        body += f"""    let result = sorted(values)
    if result.length() != {n}: return 4
    if result.first().get() != 0: return 5
    if result.last().get() != 100002: return 6
    if values.last().get() != {last}: return 7
"""
    body += "    return 0\n"
    label = f"{name}-{n}"
    program = output / f"{label}.ms"
    program.write_text(source.replace("export fn main() Int: return 0\n", body))
    binary = output / label
    subprocess.run([str(cli), "build", str(program), "--build-type", "Release", "-o", str(binary)], check=True)
    subprocess.run([str(cli), "emit", str(program), "-o", str(output / f"{label}.go")], check=True)
    subprocess.run([str(binary)], check=True)  # correctness/warm-up, excluded
    samples = []
    for i in range(args.runs):
        log = output / f"{label}-{i+1}.log"
        with log.open("w") as stream:
            start = time.perf_counter()
            process = subprocess.Popen([str(binary)], stdout=stream, stderr=subprocess.STDOUT)
            _, status, usage = os.wait4(process.pid, 0)
            seconds = time.perf_counter() - start
            process.returncode = os.waitstatus_to_exitcode(status)
            if process.returncode != 0:
                raise RuntimeError(f"workload failed: {log.read_text()}")
        samples.append({"seconds": seconds, "peak_rss_kib": usage.ru_maxrss})
        print(label, samples[-1], flush=True)
    results.append({"name": name, "elements": n, "samples": samples, "median_seconds": statistics.median(x["seconds"] for x in samples), "median_peak_rss_kib": statistics.median(x["peak_rss_kib"] for x in samples), "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()})
(output / "results.json").write_text(json.dumps({"cli": str(cli), "cli_sha256": hashlib.sha256(cli.read_bytes()).hexdigest(), "affinity": sorted(os.sched_getaffinity(0)), "build_type": "Release", "results": results}, indent=2) + "\n")
