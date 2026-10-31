#!/usr/bin/env python3
"""Report every ordered-inventory comparison without pooling measurement phases."""
import argparse
import csv
import hashlib
import io
import itertools
import json
from pathlib import Path
import statistics


def comparisons(matrix, identities):
    record = json.loads((matrix / "record.json").read_text())
    if record.get("complete") is not True:
        raise ValueError("incomplete measurement phase")
    labels = list(record["programs"])
    rounds = range(len(record["orders"]))
    expected = json.loads(identities.read_text())
    if not expected or record["cases"] != len(expected) or not rounds:
        raise ValueError("invalid case/round inventory")
    values = {}
    for row in csv.DictReader(io.StringIO((matrix / "samples.csv").read_text())):
        case, label, pair = row["case"], row["variant"], int(row["pair"])
        key = (case, label, pair)
        if key in values or case not in expected or label not in labels or pair not in rounds:
            raise ValueError(f"duplicate or unexpected sample: {key}")
        identity = [int(row[field]) for field in ("input_bytes", "iterations", "checksum")]
        if identity != expected[case] or identity[1] <= 0 or int(row["elapsed_ns"]) <= 0:
            raise ValueError(f"changed identity or invalid time: {key}")
        values[key] = int(row["elapsed_ns"]) / identity[1]
    if len(values) != len(expected) * len(labels) * len(rounds):
        raise ValueError("missing samples")
    output = []
    for before, after in itertools.combinations(labels, 2):
        for case in expected:
            a = [values[case, before, pair] for pair in rounds]
            b = [values[case, after, pair] for pair in rounds]
            differences = [y - x for x, y in zip(a, b)]
            output.append({
                "case": case, "before": before, "after": after, "rounds": len(rounds),
                "before_median_ns": statistics.median(a), "before_min_ns": min(a),
                "before_max_ns": max(a), "after_median_ns": statistics.median(b),
                "after_min_ns": min(b), "after_max_ns": max(b),
                "median_change_pct": 100 * (statistics.median(b) / statistics.median(a) - 1),
                "paired_median_delta_ns": statistics.median(differences),
                "paired_min_delta_ns": min(differences), "paired_max_delta_ns": max(differences),
                "slower_pairs": sum(delta > 0 for delta in differences),
            })
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("matrix", type=Path)
    parser.add_argument("identities", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    rows = comparisons(args.matrix, args.identities)
    with args.output.open("x", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    provenance = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in
                  [args.matrix / "record.json", args.matrix / "samples.csv", args.identities,
                   Path(__file__), args.output]}
    args.output.with_suffix(".provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")


if __name__ == "__main__":
    main()
