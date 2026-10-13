#!/usr/bin/env python3
"""Alternate pinned-Go task benchmarks in prepared revision snapshots."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--go", required=True, type=Path, help="repository-pinned Go binary")
parser.add_argument("--variant", required=True, action="append", help="name=checkout path; baseline must exclude ancestor overlap")
parser.add_argument("--output", required=True, type=Path)
parser.add_argument("--runs", default=5, type=int)
parser.add_argument("--benchtime", default="500ms")
parser.add_argument("--cores", default="1,4,16", help="GOMAXPROCS values, not a claim of available physical cores")
args = parser.parse_args()
if args.runs < 1:
    parser.error("--runs must be positive")
variants = {}
for entry in args.variant:
    name, path = entry.split("=", 1)
    if name in variants:
        parser.error("variant names must be unique")
    variants[name] = Path(path).resolve()
cores = [int(value) for value in args.cores.split(",")]
if any(value < 1 for value in cores):
    parser.error("--cores values must be positive")
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
go = args.go.resolve()
env = dict(os.environ)
env.setdefault("GOCACHE", str(output / "go-cache"))
env.setdefault("GOPATH", str(output / "go-path"))
env["GOFLAGS"] = (env.get("GOFLAGS", "") + " -buildvcs=false").strip()
pattern = re.compile(r"^(Benchmark\S+)\s+\d+\s+([\d.]+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op")
samples = []

def measure(label, core_count, iteration, benchmark, benchtime, log):
    env["GOMAXPROCS"] = str(core_count)
    command = [str(go), "test", "./pkg/runtime", "-run", "^$", "-bench", benchmark,
               "-count=1", "-benchtime=" + benchtime, "-timeout=2m"]
    log.write(f"VARIANT {label} GOMAXPROCS {core_count} ROUND {iteration + 1}\n")
    log.flush()
    result = subprocess.run(command, cwd=variants[label], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=150)
    log.write(result.stdout)
    log.flush()
    if result.returncode:
        raise SystemExit(result.returncode)
    for line in result.stdout.splitlines():
        match = pattern.match(line)
        if match:
            samples.append({"variant": label, "gomaxprocs": core_count, "round": iteration + 1,
                            "benchmark": match[1], "ns": float(match[2]),
                            "bytes": int(match[3]), "allocations": int(match[4])})
    print(f"{label}: GOMAXPROCS={core_count}, round={iteration + 1}, {benchmark}", flush=True)

names = list(variants)
common = "^BenchmarkIssue148(Uncontended|TaskGroup|TaskGroupFanout|IndependentTaskThroughput|TaskArithmetic1000|TaskSHA25664KiB)$"
overlap = [name for name in names if name != "baseline"]
with (output / "samples.txt").open("w") as log:
    for core_count in cores:
        for iteration in range(args.runs):
            for label in (names if iteration % 2 == 0 else names[::-1]):
                measure(label, core_count, iteration, common, args.benchtime, log)
    for iteration in range(args.runs):
        for label in (overlap if iteration % 2 == 0 else overlap[::-1]):
            measure(label, 1, iteration, "^BenchmarkIssue148Contended(Lock|Task)$", args.benchtime, log)
            measure(label, 1, iteration, "^BenchmarkIssue148OriginalContention$", "5x", log)

metadata = {"go": subprocess.check_output([str(go), "version"], env=env, text=True).strip(),
            "runs": args.runs, "benchtime": args.benchtime, "gomaxprocs": cores,
            "cpu_affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
            "cpu_quota": Path("/sys/fs/cgroup/cpu.max").read_text().strip() if Path("/sys/fs/cgroup/cpu.max").exists() else None,
            "variants": {}, "samples": samples}
for label, path in variants.items():
    files = sorted((path / "pkg/runtime").glob("*.go"))
    metadata["variants"][label] = {"path": str(path), "runtime_source_sha256": {
        file.name: hashlib.sha256(file.read_bytes()).hexdigest() for file in files}}
(output / "results.json").write_text(json.dumps(metadata, indent=2) + "\n")
