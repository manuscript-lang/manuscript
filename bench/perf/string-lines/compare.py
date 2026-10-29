#!/usr/bin/env python3
"""Run already-built programs in alternating pairs, rejecting failed or incomplete samples."""

import argparse
import csv
import io
import statistics
import subprocess


def expected_rows():
    rows = {"empty": (0, 1000000, 0), "tiny": (4, 1000000, 36000000),
            "short_unterminated": (5, 1000000, 22000000),
            "empty_lines": (4, 1000000, 68000000)}
    for width in [7, 8, 15, 16, 31, 32, 128, 1024, 8192, 65536]:
        count = 1048576 // (width + 1)
        rows[f"lf_{width}"] = ((width + 1) * count, 64, (width + 17) * count * 64)
    rows["unicode_crlf"] = (9002 * 128, 64, 9017 * 128 * 64)
    rows["no_newline"] = (1048576, 64, (1048576 + 17) * 64)
    return rows


def sample(executable):
    result = subprocess.run([executable], check=True, text=True, capture_output=True)
    reader = csv.DictReader(io.StringIO(result.stdout))
    if reader.fieldnames != ["case", "input_bytes", "iterations", "elapsed_ns", "checksum"]:
        raise ValueError(f"invalid header from {executable}: {reader.fieldnames}")
    rows = {}
    expected = expected_rows()
    for row in reader:
        if set(row) != set(reader.fieldnames) or any(value is None for value in row.values()):
            raise ValueError(f"malformed row: {row}")
        name = row["case"]
        if name in rows or name not in expected:
            raise ValueError(f"duplicate or unknown case: {name}")
        identity = tuple(int(row[key]) for key in ["input_bytes", "iterations", "checksum"])
        if identity != expected[name] or int(row["elapsed_ns"]) <= 0:
            raise ValueError(f"invalid sample: {row}")
        rows[name] = row
    if rows.keys() != expected.keys():
        raise ValueError(f"missing cases: {expected.keys() - rows.keys()}")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("output")
    parser.add_argument("--pairs", type=int, default=7)
    args = parser.parse_args()
    if args.pairs < 1:
        parser.error("--pairs must be positive")
    programs = {"before": args.before, "after": args.after}
    for executable in programs.values():
        sample(executable)
    samples = []
    for pair in range(args.pairs):
        for variant in (["before", "after"] if pair % 2 == 0 else ["after", "before"]):
            for row in sample(programs[variant]).values():
                samples.append({"pair": pair, "variant": variant, **row})
    with open(args.output, "w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=list(samples[0]))
        writer.writeheader()
        writer.writerows(samples)
    print("case,before_median_ns,after_median_ns,before_min_ns,before_max_ns,after_min_ns,after_max_ns,speedup")
    for name in expected_rows():
        values = {
            variant: [int(row["elapsed_ns"]) / int(row["iterations"]) for row in samples
                      if row["case"] == name and row["variant"] == variant]
            for variant in programs
        }
        before, after = values["before"], values["after"]
        print(f"{name},{statistics.median(before):.1f},{statistics.median(after):.1f},"
              f"{min(before):.1f},{max(before):.1f},{min(after):.1f},{max(after):.1f},"
              f"{statistics.median(before) / statistics.median(after):.3f}")


if __name__ == "__main__":
    main()
