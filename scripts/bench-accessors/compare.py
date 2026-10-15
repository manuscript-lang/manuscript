#!/usr/bin/env python3
"""Compare retained native samples using medians and an exact permutation test.

The two-sided test compares log-time means under all assignments for groups of
at most six samples. It is exploratory (no multiple-comparison correction), so
report emitted code, controls and allocation evidence alongside timings.
"""
import argparse
from itertools import combinations
import json
import math
from pathlib import Path
import re
import statistics

PATTERN = re.compile(r"^BenchmarkAccessor/(\S+)\s+\d+\s+([\d.]+)\s+ns/op\s+(\d+)\s+B/op\s+(\d+)\s+allocs/op$", re.MULTILINE)


def samples(file):
    cases = {}
    for name, ns, memory, allocations in PATTERN.findall(file.read_text()):
        cases.setdefault(name, []).append((float(ns), int(memory), int(allocations)))
    if not cases:
        raise ValueError(f"no native samples in {file}")
    return cases


def permutation_p(left, right):
    if len(left) < 2 or len(right) < 2 or max(len(left), len(right)) > 6:
        return None
    combined = [math.log(value) for value in left + right]
    count = len(left)
    observed = abs(statistics.mean(combined[:count]) - statistics.mean(combined[count:]))
    extreme = total = 0
    for selected in combinations(range(len(combined)), count):
        selected = set(selected)
        first = [value for index, value in enumerate(combined) if index in selected]
        second = [value for index, value in enumerate(combined) if index not in selected]
        statistic = abs(statistics.mean(first) - statistics.mean(second))
        total += 1
        extreme += statistic >= observed - 1e-12
    return extreme / total


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("current", type=Path)
    parser.add_argument("--output", type=Path, default=Path(".artifacts/accessor-comparison.json"))
    args = parser.parse_args()
    before, after = samples(args.baseline), samples(args.current)
    if before.keys() != after.keys():
        raise ValueError(f"workload sets differ: {before.keys() ^ after.keys()}")
    report = []
    for name in before:
        old, new = before[name], after[name]
        baseline = statistics.median(row[0] for row in old)
        current = statistics.median(row[0] for row in new)
        report.append({
            "case": name,
            "baseline_samples": len(old), "current_samples": len(new),
            "baseline_median_ns_per_1024_reads": baseline,
            "current_median_ns_per_1024_reads": current,
            "current_over_baseline": current / baseline,
            "two_sided_exact_log_time_permutation_p": permutation_p([row[0] for row in old], [row[0] for row in new]),
            "baseline_median_bytes": statistics.median(row[1] for row in old),
            "current_median_bytes": statistics.median(row[1] for row in new),
            "baseline_median_allocations": statistics.median(row[2] for row in old),
            "current_median_allocations": statistics.median(row[2] for row in new),
        })
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    for row in report:
        print(f"{row['case']}: ratio={row['current_over_baseline']:.3f}, allocations={row['baseline_median_allocations']} -> {row['current_median_allocations']}, p={row['two_sided_exact_log_time_permutation_p']}")


if __name__ == "__main__":
    main()
