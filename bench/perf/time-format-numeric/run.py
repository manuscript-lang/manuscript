"""Compare separately built baseline/candidate native programs and an owned-output C control."""
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
env = dict(os.environ, MS_CPU_LEVEL="baseline", LC_ALL="C", TZ="UTC")
rows = []


def run(side, pattern, zone, count, seconds, nanos):
    if side == "c-utc":
        assert zone == "UTC"
        args = [pattern, str(seconds), str(count), "0", str(nanos)]
    else:
        args = [pattern, zone, str(count), str(seconds), str(nanos)]
    result = subprocess.run(
        [str(root / side), *args], capture_output=True, check=True, env=env
    )
    elapsed, checksum = map(int, result.stdout.split())
    assert result.stderr.endswith(b"\n")
    assert checksum == len(result.stderr[:-1]) * count
    return elapsed, result.stderr


def compare(name, pattern, zone, sides=("base", "new"), seconds=1709251199,
            nanos=123456789, count=500000):
    samples = []
    for repetition in range(28):
        pair = {}
        outputs = []
        order = [0, 1] if repetition % 2 == 0 else [1, 0]
        for position in order:
            elapsed, output = run(sides[position], pattern, zone, count, seconds, nanos)
            pair[position] = elapsed
            outputs.append(output)
        assert outputs[0] == outputs[1]
        samples.append({"rep": repetition, "left_ns": pair[0], "right_ns": pair[1]})
    measured = samples[3:]
    ratios = sorted(p["right_ns"] / p["left_ns"] for p in measured)
    row = {
        "name": name, "pattern": pattern, "zone": zone, "sides": sides,
        "seconds": seconds, "nanos": nanos, "iterations": count,
        "samples": samples, "warmup_pairs": 3,
        "left_ns_per_call": statistics.median(p["left_ns"] for p in measured) / count,
        "right_ns_per_call": statistics.median(p["right_ns"] for p in measured) / count,
        "median_right_over_left": statistics.median(ratios),
        "p10_p90": [ratios[2], ratios[22]],
    }
    rows.append(row)
    print(name, zone, sides, round(row["left_ns_per_call"], 2),
          round(row["right_ns_per_call"], 2), round(row["median_right_over_left"], 3),
          [round(x, 3) for x in row["p10_p90"]], flush=True)
    (root / "samples.json").write_text(json.dumps(rows, indent=2) + "\n")


patterns = [
    ("empty", ""), ("literal", "hello"), ("year", "YYYY"),
    ("date", "YYYY-MM-DD"), ("full", "YYYY-MM-DD HH:mm:ss.SSS ZZ zone"),
    ("unicode", "日付 YYYY年MM月DD日 🙂"),
    ("long", "YYYY-MM-DD🙂 " * 128),
]
for zone in ["UTC", "America/New_York", "+05:30"]:
    for name, pattern in patterns:
        count = 10000 if name == "long" else 1000000 if name == "empty" else 500000
        compare(name, pattern, zone, count=count)
for name, seconds, nanos, zone, pattern in [
    ("negative-year", -62198755200, 123456789, "UTC", "YYYY-MM-DD HH:mm:ss.SSS ZZ"),
    ("extended-year", 253402300799, 999999999, "+23:59", "YYYY-MM-DD HH:mm:ss.SSS ZZ"),
    ("wide-raw-nanos", 0, -9223372036854775808, "UTC", "SSS"),
]:
    compare(name, pattern, zone, seconds=seconds, nanos=nanos)
for name, pattern in [patterns[0], patterns[2], patterns[3]]:
    compare("AA-" + name, pattern, "UTC", sides=("base", "base"), count=1000000)
for name, pattern in patterns:
    count = 10000 if name == "long" else 1000000
    compare("C-" + name, pattern, "UTC", sides=("c-utc", "new"), count=count)
metadata = {
    "executables": {side: hashlib.sha256((root / side).read_bytes()).hexdigest()
                    for side in ["base", "new", "c-utc"]},
    "environment": {key: env[key] for key in ["MS_CPU_LEVEL", "LC_ALL", "TZ"]},
    "affinity": sorted(os.sched_getaffinity(0)),
}
(root / "run-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
