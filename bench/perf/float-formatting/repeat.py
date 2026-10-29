#!/usr/bin/env python3
"""Strict paired timings of standalone float formatting programs."""

import hashlib
import argparse
import json
import os
import re
import resource
import statistics
import subprocess
import sys
import time


def eighth(n):
    integer, fraction = divmod(n, 8)
    return str(integer) + ("." + f"{fraction * 125:03}".rstrip("0") if fraction else "")


PLAIN = [eighth(n) for n in range(1000)]
INTEGRAL = [str(n) for n in range(1000)]
SPECIAL = ["Infinity", "NaN"]
CYCLES = {
    "plain64": PLAIN,
    "integral64": INTEGRAL,
    "scientific64": ["1.5e-7", "-1.5e-7"],
    "wide64": ["1.7976931348623157e+308", "5e-324"],
    "special64": SPECIAL,
    "report64": [f"value={value}; item={n}" for n, value in enumerate(PLAIN)],
}


def expected(operation, count):
    values = CYCLES[operation]
    whole, rest = divmod(count, len(values))
    checksum = whole * sum(map(len, values)) + sum(map(len, values[:rest]))
    return checksum, values[(count - 1) % len(values)]


def run(binary, operation, count):
    checksum, last = expected(operation, count)
    usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    begin = time.perf_counter_ns()
    result = subprocess.run(
        [binary, operation, str(count), str(checksum), last],
        check=True, capture_output=True, text=True, timeout=30,
    )
    wall = time.perf_counter_ns() - begin
    usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    match = re.fullmatch(
        r"operation=(\w+) count=(\d+) ns=(\d+) checksum=(\d+) last=(.+)\n",
        result.stdout,
    )
    if not match or result.stderr or match.group(1, 2, 4, 5) != (
        operation, str(count), str(checksum), last
    ):
        raise RuntimeError(f"invalid producer output: {result!r}")
    if int(match[3]) > wall:
        raise RuntimeError("internal duration exceeds process duration")
    cpu_ns = round(1e9 * (usage_after.ru_utime + usage_after.ru_stime - usage_before.ru_utime - usage_before.ru_stime))
    return dict(ns_op=int(match[3]) / count, wall_ns=wall, cpu_ns=cpu_ns,
                involuntary_switches=usage_after.ru_nivcsw - usage_before.ru_nivcsw,
                checksum=checksum, last=last)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("repeats", type=int, nargs="?", default=8)
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--batch-count", type=int, default=200000)
    args = parser.parse_args()
    before, after, repeats = args.before, args.after, args.repeats
    if repeats < 1 or args.batch_count < 1:
        raise ValueError("repeats and batch count must be positive")
    if args.cpu is not None:
        os.sched_setaffinity(0, {args.cpu})
    print(json.dumps(dict(configuration=True, repeats=repeats,
                          batch_count=args.batch_count,
                          affinity=sorted(os.sched_getaffinity(0)))))
    for label, binary in (("before", before), ("after", after)):
        with open(binary, "rb") as stream:
            print(json.dumps(dict(binary=label, sha256=hashlib.file_digest(stream, "sha256").hexdigest())))
    cases = [(op, count) for op in CYCLES for count in (1, args.batch_count)]
    cases += [(op, 1000) for op in ("plain64", "report64")]
    rows = []
    for operation, count in cases:
        for phase in range(-1, repeats):
            order = [("before", before), ("after", after)]
            if phase % 2:
                order.reverse()
            for label, binary in order:
                row = run(binary, operation, count)
                row.update(binary=label, operation=operation, count=count, phase=phase)
                print(json.dumps(row), flush=True)
                if phase >= 0:
                    rows.append(row)
    for operation, count in cases:
        summary = dict(summary=True, operation=operation, count=count)
        for label in ("before", "after"):
            values = [r["ns_op"] for r in rows if (r["operation"], r["count"], r["binary"]) == (operation, count, label)]
            if len(values) != repeats:
                raise RuntimeError(f"missing rows for {operation} {count} {label}")
            summary[label] = dict(median=statistics.median(values), minimum=min(values), maximum=max(values))
        print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    main()
