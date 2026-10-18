"""Pinned, randomized paired runtime samples from already-built benchmark binaries.

Example: --binary baseline=/path/before.test --binary copy=/path/after.test
Run compilation and profiling separately. Confidence intervals describe this
host/workload; they do not establish cross-machine or application-wide effects.
"""

import argparse
import json
import math
import os
from pathlib import Path
import random
import re
import statistics
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", action="append", required=True)
    parser.add_argument("--output", default=".artifacts/flat-literals/runtime-pairs.jsonl")
    parser.add_argument("--cpu", default="0")
    parser.add_argument("--gomaxprocs", default="1")
    parser.add_argument("--gc", default="100,50,off")
    parser.add_argument("--count", type=int, default=12)
    parser.add_argument("--benchtime", default="400ms")
    args = parser.parse_args()
    binaries = dict(item.split("=", 1) for item in args.binary)
    if "baseline" not in binaries:
        parser.error("a baseline binary is required")
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    rng = random.Random(147)
    rows = []
    with output.open("w") as log:
        for gc in args.gc.split(","):
            for rep in range(args.count):
                names = list(binaries)
                rng.shuffle(names)
                for name in names:
                    env = os.environ.copy()
                    env.update(GOMAXPROCS=args.gomaxprocs, GOGC=gc)
                    time = "200x" if gc == "off" else args.benchtime
                    result = subprocess.run(
                        ["taskset", "-c", args.cpu, binaries[name],
                         "-test.run=^TestResult$", "-test.bench=^BenchmarkLiteral$",
                         "-test.benchmem", "-test.benchtime=" + time],
                        env=env, capture_output=True, text=True, check=True,
                    )
                    match = re.search(r"BenchmarkLiteral(?:-\d+)?\s+\d+\s+(\d+) ns/op\s+(\d+) B/op\s+(\d+) allocs/op", result.stdout)
                    if match is None:
                        raise ValueError(result.stdout + result.stderr)
                    row = dict(gc=gc, rep=rep, variant=name, ns=int(match[1]),
                               bytes=int(match[2]), allocs=int(match[3]))
                    rows.append(row)
                    log.write(json.dumps(row) + "\n")
                    log.flush()
    for gc in args.gc.split(","):
        baseline = {r["rep"]: r["ns"] for r in rows if r["gc"] == gc and r["variant"] == "baseline"}
        for variant in sorted(set(binaries) - {"baseline"}):
            values = [math.log(r["ns"] / baseline[r["rep"]]) for r in rows
                      if r["gc"] == gc and r["variant"] == variant]
            bootstrap = sorted(math.exp(statistics.mean(rng.choices(values, k=len(values))))
                               for _ in range(10000))
            print(json.dumps(dict(gc=gc, variant=variant, pairs=len(values),
                                  ratio=math.exp(statistics.mean(values)),
                                  lower95=bootstrap[250], upper95=bootstrap[9749],
                                  all_slower=all(v > 0 for v in values))))


if __name__ == "__main__":
    main()
