"""Paired process trials of the actual release substitution operation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("before")
parser.add_argument("after")
parser.add_argument("output", type=Path)
parser.add_argument("--samples", type=int, default=9)
args = parser.parse_args()
assert not args.output.exists()
cpu = min(os.sched_getaffinity(0))
cases = [f"{kind}-{n}" for kind in ("concrete", "distinct", "changed", "unbound") for n in (1, 4, 16, 64)]
cases += [f"unique-{n}" for n in (4, 16, 63, 64, 65, 128, 256)]
cases += [f"shared-{n}" for n in (16, 20, 24)]
cases += [f"fibonacci-{n}" for n in (4, 12, 16)]
binaries = [("base", args.before), ("candidate", args.after)]
result = {"cpu": cpu, "protocol": "10 internal warmups per process; seven or nine alternating paired rounds; seeded shuffled case order; input setup and correctness checks outside timing", "binaries": {label: {"path": path, "sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest()} for label, path in binaries}, "samples": []}
rng = random.Random(23871)
for trial in range(args.samples):
    rng.shuffle(cases)
    for case in cases:
        for label, path in (binaries if trial % 2 == 0 else list(reversed(binaries))):
            command = ["taskset", "-c", str(cpu), path, case]
            run = subprocess.run(command, capture_output=True, text=True, timeout=90)
            sample = {"round": trial, "label": label, "command": command, "exit": run.returncode, "stdout": run.stdout, "stderr": run.stderr}
            result["samples"].append(sample)
            args.output.write_text(json.dumps(result, indent=2))
            assert run.returncode == 0 and run.stderr == "", sample
            sample["measurement"] = json.loads(run.stdout)
            assert sample["measurement"]["case"] == case
    print(f"round {trial} complete", flush=True)
args.output.write_text(json.dumps(result, indent=2))
