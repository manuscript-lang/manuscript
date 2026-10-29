#!/usr/bin/env python3
"""Pair existing generated executables; only their internal decode timer is measured."""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess

p = argparse.ArgumentParser(__doc__)
p.add_argument("before", type=Path)
p.add_argument("after", type=Path)
p.add_argument("output", type=Path)
p.add_argument("--pairs", type=int, default=9)
a = p.parse_args()
if a.pairs < 2:
    p.error("at least two pairs required")
programs = {name: path.resolve() for name, path in [("before", a.before), ("after", a.after)]}
cases = [(0, 1000, 500), (1, 1000, 500), (3, 1000, 500), (32, 1000, 300),
         (1024, 100, 50), (65536, 1, 100), (3, 1, 100000)]
a.output.mkdir(parents=True, exist_ok=False)
identities = {name: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
              for name, path in programs.items()}
(a.output / "binaries.json").write_text(json.dumps(identities, indent=2) + "\n")
with (a.output / "samples.jsonl").open("w") as output:
    samples = {}
    for size, count, rounds in cases:
        key = f"{size}/{count}/{rounds}"
        samples[key] = {name: [] for name in programs}
        for pair in range(-1, a.pairs):
            for name in (["before", "after"] if pair % 2 == 0 else ["after", "before"]):
                result = subprocess.run([str(programs[name]), str(size), str(count), str(rounds)],
                                        text=True, capture_output=True, check=True)
                parts = result.stdout.split()
                if len(parts) != 5:
                    raise RuntimeError(f"invalid output {name}: {result.stdout!r}")
                observed = list(map(int, parts))
                if observed[:4] != [size, count, rounds, size * count * rounds] or observed[4] <= 0:
                    raise RuntimeError(f"wrong identity/checksum/timer: {observed}")
                elapsed = observed[4] / rounds
                output.write(json.dumps({"case": key, "pair": pair, "label": name,
                                         "checksum": observed[3], "ns_per_parse": elapsed}) + "\n")
                output.flush()
                if pair >= 0:
                    samples[key][name].append(elapsed)
        b, c = samples[key]["before"], samples[key]["after"]
        print(key, "before", min(b), statistics.median(b), max(b),
              "after", min(c), statistics.median(c), max(c),
              "ratio", statistics.median(c) / statistics.median(b), flush=True)
