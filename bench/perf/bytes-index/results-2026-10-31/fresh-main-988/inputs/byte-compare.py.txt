#!/usr/bin/env python3
"""Validate and compare already-built byte-search programs in balanced order."""
import argparse
import csv
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import statistics
import sys

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("paired", HERE.parent / "string-lines/compare.py")
PAIRED = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PAIRED)
SIZES = [0, 1, 7, 15, 31, 32, 64, 256, 4096, 1048576]
KINDS = ["miss", "first", "middle", "last", "negative", "past", "equal", "offset",
         "near1", "near7", "near8", "near9", "near15", "near16", "near17", "near18", "near23", "near24",
         "near25", "near31", "near32", "near33"]


def identities():
    """Use Python bytearray.find as the independent result oracle."""
    rows = {}
    for size in SIZES:
        for kind in KINDS:
            position, start = -1, 0
            if kind in ["first", "negative", "past"]:
                position = 0
            if kind.startswith("near"):
                position = min(int(kind[4:]), size - 1)
            if kind == "middle":
                position = size // 2
            if kind in ["last", "offset"]:
                position = size - 1
            if kind == "negative":
                start = -1
            if kind == "past":
                start = size + 1
            if kind == "equal":
                start = size
            if kind == "offset":
                start = size // 2
            data = bytearray(b"a" * size)
            if 0 <= position < size:
                data[position] = 255
            found = data.find(b"\xff", max(start, 0))
            expected = size if found == -1 else found
            work = size
            if expected < size:
                work = expected + 1 - start
            if start < 0:
                work = expected + 1
            if start >= size:
                work = 1
            iterations = max(256, min(1000000, 67108864 // max(work, 32)))
            rows[f"{kind}_{size}"] = (size, iterations, expected * iterations)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("rust", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cpu", type=int)
    args = parser.parse_args()
    if args.cpu is not None:
        os.sched_setaffinity(0, {args.cpu})
    args.output.mkdir(parents=True, exist_ok=False)
    expected = identities()
    programs = {key: str(getattr(args, key).resolve()) for key in ["before", "after", "rust"]}
    record = {"complete": False, "argv": sys.argv, "host": list(os.uname()),
              "affinity": sorted(os.sched_getaffinity(0)), "expected_cases": len(expected),
              "executables": {key: {"path": path, "sha256": hashlib.sha256(Path(path).read_bytes()).hexdigest()}
                              for key, path in programs.items()}, "validated_producers": []}
    record["inputs"] = {
        str(path.relative_to(HERE)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [HERE / "main.ms", HERE / "rust/src/main.rs", HERE / "rust/Cargo.toml",
                     HERE / "rust/Cargo.lock", HERE / "identities.json", HERE / "compare.py"]
    }
    record["validator_sha256"] = hashlib.sha256(Path(SPEC.origin).read_bytes()).hexdigest()
    orders = list(itertools.permutations(programs))
    record["orders"] = orders
    samples = []
    try:
        for variant, executable in programs.items():
            PAIRED.sample(executable, expected)
            record["validated_producers"].append(["warmup", variant])
        for pair, order in enumerate(orders):
            for variant in order:
                rows = PAIRED.sample(programs[variant], expected)
                samples.extend({"pair": pair, "variant": variant, **row} for row in rows.values())
                record["validated_producers"].append([pair, variant])
        record["complete"] = True
    finally:
        (args.output / "record.json").write_text(json.dumps(record, indent=2) + "\n")
        if samples:
            with (args.output / "samples.csv").open("w", newline="") as output:
                writer = csv.DictWriter(output, fieldnames=list(samples[0]))
                writer.writeheader()
                writer.writerows(samples)
    statistics_rows = []
    for name in expected:
        row = {"case": name}
        series = {}
        for variant in programs:
            series[variant] = [int(sample["elapsed_ns"]) / int(sample["iterations"])
                               for sample in samples if sample["case"] == name and sample["variant"] == variant]
            for label, operation in [("median", statistics.median), ("min", min), ("max", max)]:
                row[f"{variant}_{label}_ns"] = operation(series[variant])
        deltas = [after - before for before, after in zip(series["before"], series["after"])]
        row["paired_delta_median_ns"] = statistics.median(deltas)
        row["pairs_slower"] = sum(delta > 0 for delta in deltas)
        statistics_rows.append(row)
    with (args.output / "summary.csv").open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(statistics_rows[0]))
        writer.writeheader()
        writer.writerows(statistics_rows)


if __name__ == "__main__":
    main()
