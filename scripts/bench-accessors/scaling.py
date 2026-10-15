#!/usr/bin/env python3
"""Retain accessor-heavy inputs and time check/emit/build at N, 2N and 4N.

Run after correctness verification is quiet; this measures whole CLI phases,
including startup, separately from the native read-loop benchmarks.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time


def source(count, legacy):
    member = "length()" if legacy else "length"
    reads = "".join(f"    total = total + values.{member}\n" for _ in range(count))
    return (
        "fn observe(values: List[Int]) -> Int:\n    var total = 0\n"
        + reads
        + "    return total\n\nexport fn main() -> Int:\n"
        + f"    if observe([1, 2, 3]) != {3 * count}: return 1\n    return 0\n"
    )


def checked_run(command):
    started = time.perf_counter()
    result = subprocess.run(command, text=True, capture_output=True, timeout=180)
    duration = time.perf_counter() - started
    if result.returncode:
        raise RuntimeError(f"{command}: {result.stdout}\n{result.stderr}")
    return duration


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current", required=True, type=Path)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path(".artifacts/accessor-scaling"))
    parser.add_argument("--base-size", type=int, default=64)
    parser.add_argument("--count", type=int, default=3)
    parser.add_argument("--generate-only", action="store_true")
    args = parser.parse_args()
    if args.base_size < 1 or args.count < 1:
        parser.error("base-size and count must be positive")
    directory = args.output.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    report = {
        "platform": platform.platform(),
        "environment": {key: os.environ.get(key, "default") for key in ("GOMAXPROCS", "GOGC", "GOMEMLIMIT", "GOCACHE", "XDG_CACHE_HOME")},
        "samples": [],
    }
    for revision, cli, legacy in (("baseline", args.baseline.resolve(), True), ("current", args.current.resolve(), False)):
        for count in (args.base_size, 2 * args.base_size, 4 * args.base_size):
            file = directory / f"{revision}-{count}.ms"
            file.write_text(source(count, legacy))
            if args.generate_only:
                continue
            commands = {
                "check": [str(cli), "check", str(file)],
                "emit": [str(cli), "emit", str(file), "-o", str(file.with_suffix(".go"))],
                "build": [str(cli), "build", str(file), "-o", str(file.with_suffix(".bin"))],
            }
            for phase, command in commands.items():
                checked_run(command)  # warm native workspace and packages separately
                samples = [checked_run(command) for _ in range(args.count)]
                entry = {"revision": revision, "reads": count, "phase": phase, "seconds": samples, "median_seconds": statistics.median(samples)}
                report["samples"].append(entry)
                print(json.dumps(entry), flush=True)
            checked_run([str(file.with_suffix(".bin"))])
    (directory / "samples.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
