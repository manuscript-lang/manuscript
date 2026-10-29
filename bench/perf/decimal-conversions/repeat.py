#!/usr/bin/env python3
"""Paired standalone Decimal conversion measurements; fail on missing/wrong work."""

import hashlib
import json
import re
import statistics
import subprocess
import sys
import time
from decimal import Decimal


def run(binary, operation, count, seed):
    begin = time.perf_counter_ns()
    result = subprocess.run(
        [binary, operation, str(count), str(seed)],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    wall = time.perf_counter_ns() - begin
    match = re.fullmatch(
        r"operation=(\w+) count=(\d+) seed=(-?\d+) ns=(\d+) result=(\S+)\n",
        result.stdout,
    )
    if not match or result.stderr or match.group(1, 2, 3) != (
        operation, str(count), str(seed)
    ):
        raise RuntimeError(f"invalid producer output: {result!r}")
    last = (count - 1) % 10000
    if operation == "int":
        expected = Decimal(seed + last)
    elif operation == "uint":
        expected = Decimal((seed or (1 << 64) - 1) - last)
    elif operation == "stream":
        complete, remainder = divmod(count, 10000)
        expected = Decimal(complete * 49995000 + remainder * (remainder - 1) // 2)
    else:
        expected = Decimal(seed) / 100 * (-1 if count % 2 else 1)
    if Decimal(match[5]) != expected:
        raise RuntimeError(f"wrong result: {match[5]}, expected {expected}")
    return dict(ns_op=int(match[4]) / count, wall_ns=wall, result=match[5])


def main():
    before, after = sys.argv[1:3]
    repeats = int(sys.argv[3]) if len(sys.argv) > 3 else 7
    if repeats < 1:
        raise ValueError("repeats must be positive")
    for label, binary in (("before", before), ("after", after)):
        with open(binary, "rb") as stream:
            print(json.dumps(dict(binary=label, sha256=hashlib.file_digest(stream, "sha256").hexdigest())))
    cases = [
        ("int", 1, 0),
        ("int", 10000, 0),
        ("int", 1000000, 0),
        ("int", 1000000, -1000000000),
        ("int", 1000000, 9223372036800000000),
        ("uint", 1000000, 0),
        ("uint", 1000001, 1000000000000000000),
        ("stream", 1000000, 0),
        ("negate", 1, 0),
        ("negate", 10000, 12345),
        ("negate", 1000000, 12345),
        ("negate", 1000001, -9223372036854775808),
    ]
    rows = []
    for case in cases:
        expected = None
        for phase in range(-1, repeats):
            order = [("before", before), ("after", after)]
            if phase % 2:
                order.reverse()
            for label, binary in order:
                row = run(binary, *case)
                if expected is None:
                    expected = row["result"]
                if row["result"] != expected:
                    raise RuntimeError(f"checksum changed for {case}: {row}")
                row.update(binary=label, operation=case[0], count=case[1], seed=case[2], phase=phase)
                print(json.dumps(row), flush=True)
                if phase >= 0:
                    rows.append(row)
    for case in cases:
        summary = dict(summary=True, operation=case[0], count=case[1], seed=case[2])
        for label in ("before", "after"):
            values = [r["ns_op"] for r in rows if (r["operation"], r["count"], r["seed"]) == case and r["binary"] == label]
            if len(values) != repeats:
                raise RuntimeError(f"missing rows for {case} {label}")
            summary[label] = dict(median=statistics.median(values), minimum=min(values), maximum=max(values))
        print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    main()
