#!/usr/bin/env python3
"""Strict paired measurements of integer radix formatting."""

import argparse
import functools
import hashlib
import json
import os
import re
import resource
import statistics
import subprocess
import time


CASES = [
    ("signed-wide", radix) for radix in (2, 4, 8, 16, 32, 3, 10, 36)
] + [
    ("unsigned-wide", radix) for radix in (2, 16, 10, 36)
] + [("negative-wide", 16), ("signed-small", 16), ("signed-small", 10), ("zero", 16), ("zero", 10), ("decimal-control", 10)]


def formatted(value, radix):
    if value == 0:
        return "0"
    negative = value < 0
    value = abs(value)
    digits = []
    while value:
        value, digit = divmod(value, radix)
        digits.append("0123456789abcdefghijklmnopqrstuvwxyz"[digit])
    return ("-" if negative else "") + "".join(reversed(digits))


@functools.cache
def cycle(operation, radix):
    values = []
    for i in range(1000):
        if operation in ("signed-wide", "decimal-control"):
            value = 9223372036800000000 + i
        elif operation == "negative-wide":
            value = -(1 << 63) + i
        elif operation == "unsigned-wide":
            value = (1 << 64) - 1 - i
        elif operation == "signed-small":
            value = i
        else:
            value = 0
        values.append(formatted(value, radix))
    return values


def expected(operation, radix, count):
    values = cycle(operation, radix)
    whole, rest = divmod(count, len(values))
    return whole * sum(map(len, values)) + sum(map(len, values[:rest])), values[(count - 1) % len(values)]


def run(binary, operation, radix, count):
    checksum, last = expected(operation, radix, count)
    usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.perf_counter_ns()
    result = subprocess.run(
        [binary, operation, str(radix), str(count), str(checksum), last],
        check=True, text=True, capture_output=True, timeout=30,
    )
    wall_ns = time.perf_counter_ns() - start
    usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    match = re.fullmatch(
        r"operation=([\w-]+) radix=(\d+) count=(\d+) ns=(\d+) checksum=(\d+) last=(\S+)\n",
        result.stdout,
    )
    if not match or result.stderr or match.group(1, 2, 3, 5, 6) != (
        operation, str(radix), str(count), str(checksum), last
    ):
        raise RuntimeError(f"wrong producer output: {result!r}")
    if int(match[4]) > wall_ns:
        raise RuntimeError("internal duration exceeds process wall time")
    cpu_ns = round(1e9 * (usage_after.ru_utime + usage_after.ru_stime - usage_before.ru_utime - usage_before.ru_stime))
    return dict(ns_op=int(match[4]) / count, wall_ns=wall_ns, cpu_ns=cpu_ns,
                checksum=checksum, last=last)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("--repeats", type=int, default=8)
    parser.add_argument("--count", type=int, default=1000000)
    parser.add_argument("--cpu", type=int, default=0)
    args = parser.parse_args()
    if args.repeats < 1 or args.count < 2:
        raise ValueError("positive repeats and count of at least two required")
    os.sched_setaffinity(0, {args.cpu})
    print(json.dumps(dict(configuration=True, repeats=args.repeats, count=args.count,
                          affinity=sorted(os.sched_getaffinity(0)))))
    for label, binary in (("before", args.before), ("after", args.after)):
        with open(binary, "rb") as stream:
            print(json.dumps(dict(binary=label, sha256=hashlib.file_digest(stream, "sha256").hexdigest())))
    rows = []
    cases = [(op, radix, count) for op, radix in CASES for count in (1, args.count)]
    for operation, radix, count in cases:
        for phase in range(-1, args.repeats):
            order = [("before", args.before), ("after", args.after)]
            if phase % 2:
                order.reverse()
            for label, binary in order:
                row = run(binary, operation, radix, count)
                row.update(binary=label, operation=operation, radix=radix, count=count, phase=phase)
                print(json.dumps(row), flush=True)
                if phase >= 0:
                    rows.append(row)
    for operation, radix, count in cases:
        summary = dict(summary=True, operation=operation, radix=radix, count=count)
        for label in ("before", "after"):
            values = [r["ns_op"] for r in rows if (r["operation"], r["radix"], r["count"], r["binary"]) == (operation, radix, count, label)]
            if len(values) != args.repeats:
                raise RuntimeError("missing rows")
            summary[label] = dict(median=statistics.median(values), minimum=min(values), maximum=max(values))
        print(json.dumps(summary))


if __name__ == "__main__":
    main()
