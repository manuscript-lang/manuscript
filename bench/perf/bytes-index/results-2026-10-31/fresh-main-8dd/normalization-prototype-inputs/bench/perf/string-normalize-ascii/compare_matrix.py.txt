#!/usr/bin/env python3
"""Validate fixed programs, then measure balanced rotations and their reversals."""
import argparse
import csv
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import statistics
import sys

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("paired", HERE.parent / "string-lines/compare.py")
PAIRED = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PAIRED)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("programs", type=Path, help="JSON object of label: executable")
    parser.add_argument("identities", type=Path, help="JSON case: [bytes, iterations, checksum]")
    parser.add_argument("output", type=Path)
    parser.add_argument("--cpu", type=int, default=0)
    args = parser.parse_args()
    programs = json.loads(args.programs.read_text())
    if not isinstance(programs, dict) or len(programs) < 2:
        parser.error("program inventory must contain at least two variants")
    expected = {key: tuple(value) for key, value in json.loads(args.identities.read_text()).items()}
    if not expected:
        parser.error("identity inventory must not be empty")
    os.sched_setaffinity(0, {args.cpu})
    args.output.mkdir(parents=True, exist_ok=False)
    labels = list(programs)
    forward = [labels[offset:] + labels[:offset] for offset in range(len(labels))]
    orders = forward + [list(reversed(order)) for order in forward]
    record = {"complete": False, "argv": sys.argv, "affinity": sorted(os.sched_getaffinity(0)),
              "orders": orders, "cases": len(expected), "validated_producers": [],
              "programs": {label: {"path": str(Path(path).resolve()), "sha256": digest(path)}
                           for label, path in programs.items()},
              "program_inventory_sha256": digest(args.programs),
              "identities_sha256": digest(args.identities), "runner_sha256": digest(__file__),
              "validator_sha256": digest(SPEC.origin)}
    samples = []
    try:
        for label, executable in programs.items():
            PAIRED.sample(executable, expected)
            record["validated_producers"].append(["warmup", label])
        for pair, order in enumerate(orders):
            for label in order:
                rows = PAIRED.sample(programs[label], expected)
                samples.extend({"pair": pair, "variant": label, **row} for row in rows.values())
                record["validated_producers"].append([pair, label])
            print(f"round {pair + 1}/{len(orders)} complete", flush=True)
        record["complete"] = True
    except Exception as error:
        record["failure"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        (args.output / "record.json").write_text(json.dumps(record, indent=2) + "\n")
        if samples:
            with (args.output / "samples.csv").open("w", newline="") as output:
                writer = csv.DictWriter(output, fieldnames=list(samples[0]), lineterminator="\n")
                writer.writeheader()
                writer.writerows(samples)
    summaries = []
    for name in expected:
        row = {"case": name}
        for label in programs:
            values = [int(sample["elapsed_ns"]) / int(sample["iterations"])
                      for sample in samples if sample["case"] == name and sample["variant"] == label]
            for suffix, operation in [("median_ns", statistics.median), ("min_ns", min), ("max_ns", max)]:
                row[f"{label}_{suffix}"] = operation(values)
        summaries.append(row)
    with (args.output / "summary.csv").open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(summaries[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(summaries)


if __name__ == "__main__":
    main()
