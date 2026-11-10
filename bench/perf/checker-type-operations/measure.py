"""Measure complete production checks, preserving every output and resource sample."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import resource
import subprocess
import time


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", action="append", required=True, help="label=path")
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=9)
    parser.add_argument("--filter", default="")
    args = parser.parse_args()
    binaries = [pair.split("=", 1) for pair in args.binary]
    files = sorted(path for path in args.inputs.glob("*.ms") if args.filter in path.stem)
    assert files
    args.output.parent.mkdir(parents=True, exist_ok=True)
    assert not args.output.exists(), "preserve old results"
    cpu = min(os.sched_getaffinity(0))
    result = {
        "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "uname": list(os.uname()),
        "cpuinfo": Path("/proc/cpuinfo").read_text(),
        "cpu": cpu,
        "binaries": {label: {"path": path, "sha256": digest(Path(path).read_bytes())} for label, path in binaries},
        "inputs": {path.name: {"sha256": digest(path.read_bytes()), "source": path.read_text()} for path in files},
        "protocol": "one untimed warmup per binary/input, then seeded shuffled cases; alternating binary order per round; process startup included; CPU pinned",
        "samples": [],
    }
    oracle = b'{\n  "format": 1,\n  "diagnostics": []\n}\n'
    oracles = {path.name: (0, oracle, b"") for path in files}
    for path in files:
        if path.stem.startswith("rejected-"):
            run = subprocess.run([binaries[0][1], "check", str(path), "--json"], capture_output=True, timeout=90)
            diagnostics = json.loads(run.stdout)["diagnostics"]
            assert run.returncode == 1 and run.stderr == b"" and len(diagnostics) == 1
            assert diagnostics[0]["message"].startswith("expected Int, found String")
            oracles[path.name] = (run.returncode, run.stdout, run.stderr)
    rng = random.Random(38671)
    for round_number in range(-1, args.samples):
        order = files.copy()
        rng.shuffle(order)
        for path in order:
            for label, binary in (binaries if round_number % 2 == 0 else list(reversed(binaries))):
                command = ["taskset", "-c", str(cpu), binary, "check", str(path), "--json"]
                before = resource.getrusage(resource.RUSAGE_CHILDREN)
                start = time.perf_counter_ns()
                run = subprocess.run(command, capture_output=True, timeout=90)
                elapsed = time.perf_counter_ns() - start
                after = resource.getrusage(resource.RUSAGE_CHILDREN)
                sample = {
                    "round": round_number, "label": label, "case": path.stem,
                    "command": command, "wall_ns": elapsed,
                    "user_seconds": after.ru_utime - before.ru_utime,
                    "system_seconds": after.ru_stime - before.ru_stime,
                    "minor_faults": after.ru_minflt - before.ru_minflt,
                    "major_faults": after.ru_majflt - before.ru_majflt,
                    "exit": run.returncode,
                    "stdout": run.stdout.decode(), "stderr": run.stderr.decode(),
                }
                result["samples"].append(sample)
                args.output.write_text(json.dumps(result, indent=2))
                assert (run.returncode, run.stdout, run.stderr) == oracles[path.name], sample
        print(f"round {round_number}: {len(order)} cases verified", flush=True)


if __name__ == "__main__":
    main()
