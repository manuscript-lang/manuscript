#!/usr/bin/env python3
"""Run paired generated-program samples; compilation and setup are untimed."""

import argparse
import hashlib
import json
import pathlib
import platform
import statistics
import subprocess


CASES = [
    ("int", 0, 1, 20000000),
    ("int", 8, 8, 500000),
    ("int", 16, 16, 150000),
    ("int", 17, 17, 150000),
    ("int", 1024, 1024, 3000),
    ("int", 10000, 10000, 300),
    ("int", 100000, 100000, 30),
    ("int", 100000, 32, 100),
    ("int", 100000, 1, 100),
    ("string", 8, 8, 150000),
    ("string", 17, 17, 50000),
    ("string", 1024, 1024, 1000),
    ("string", 10000, 10000, 100),
    ("string", 100000, 100000, 10),
    ("string", 100000, 32, 100),
    ("intersection", 8, 0, 200000),
    ("intersection", 1024, 0, 3000),
    ("intersection", 100000, 0, 30),
    ("difference", 8, 8, 200000),
    ("difference", 1024, 1024, 3000),
    ("difference", 100000, 100000, 30),
    ("symmetric_difference", 8, 8, 100000),
    ("symmetric_difference", 1024, 1024, 1500),
    ("symmetric_difference", 100000, 100000, 15),
    ("union", 8, 0, 200000),
    ("union", 1024, 0, 3000),
    ("union", 1024, 1024, 1500),
    ("union", 100000, 0, 30),
    ("union", 100000, 100000, 15),
    ("int_set", 100000, 100000, 30),
    ("int_set", 100000, 1, 100),
    ("string_set", 100000, 100000, 10),
    ("string_set", 100000, 32, 100),
]


def validate_output(result, case):
    if result.returncode != 0:
        raise ValueError(f"producer failed with exit status {result.returncode}")
    kind, size, unique, repeats = case
    fields = result.stdout.split()
    if result.stderr or len(fields) != 2:
        raise ValueError(f"unexpected output: {result.stdout!r} {result.stderr!r}")
    elapsed, checksum = map(int, fields)
    count = min(size, unique)
    if kind in ("intersection", "difference"):
        count = size
    if kind == "symmetric_difference":
        count = size * 2
    if kind == "union":
        count = size + min(size, unique)
    expected = count
    if kind not in ("string", "string_set"):
        expected += sum(range(count))
    else:
        expected += sum(len(f"key-{i}-long-enough-to-be-heap-backed") for i in range(count))
    if checksum != expected * repeats or elapsed <= 0:
        raise ValueError(f"bad result for {case}: {elapsed}, {checksum}")
    return {"nanoseconds": elapsed, "checksum": checksum, "exit_status": result.returncode}


def sample(binary, case):
    result = subprocess.run(
        [str(binary), *map(str, case)], capture_output=True, text=True, check=True
    )
    return validate_output(result, case)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=pathlib.Path)
    parser.add_argument("after", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--samples", type=int, default=7)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("--samples must be positive")
    if len(set(CASES)) != len(CASES):
        raise ValueError("duplicate workload identities")
    # Never overwrite evidence from an older invocation. Any failure below leaves a
    # new, explicitly incomplete report, including a failed first warmup or sample.
    with args.output.open("x") as output:
        output.write('{"complete": false}\n')
    binaries = {name: getattr(args, name).resolve() for name in ("before", "after")}
    report = {
        "complete": False,
        "platform": platform.platform(),
        "samples": args.samples,
        "source_sha256": hashlib.sha256(pathlib.Path(__file__).with_name("main.ms").read_bytes()).hexdigest(),
        "harness_sha256": hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
        "expected_cases": CASES,
        "binaries": {},
        "cases": [],
    }
    for name, binary in binaries.items():
        report["binaries"][name] = {
            "path": str(binary), "sha256": hashlib.sha256(binary.read_bytes()).hexdigest()
        }
    for case in CASES:
        row = {"case": case, "before": [], "after": []}
        for binary in binaries.values():
            sample(binary, case)  # warmup excluded
        for trial in range(args.samples):
            order = ("before", "after") if trial % 2 == 0 else ("after", "before")
            for name in order:
                row[name].append(sample(binaries[name], case))
        medians = {
            name: statistics.median(x["nanoseconds"] for x in row[name])
            for name in binaries
        }
        row["median_ratio_after_before"] = medians["after"] / medians["before"]
        row["median_paired_ratio"] = statistics.median(
            after["nanoseconds"] / before["nanoseconds"]
            for after, before in zip(row["after"], row["before"])
        )
        report["cases"].append(row)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(case, medians, f'{row["median_ratio_after_before"]:.3f}', flush=True)
    if len(report["cases"]) != len(CASES):
        raise ValueError("incomplete result set")
    report["complete"] = True
    args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
