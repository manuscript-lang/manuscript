#!/usr/bin/env python3
"""Strict paired release-generated BigInt parsing workloads."""

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

BASES = (2, 4, 8, 16, 32, 3, 10, 36)
OPERATIONS = ("tiny", "dense", "leading-zero", "zero")
CASES = [(operation, radix) for radix in BASES for operation in OPERATIONS]
ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"


def canonical(text):
    negative = text.startswith("-")
    digits = text.lstrip("+-").lower().lstrip("0") or "0"
    return ("-" if negative and digits != "0" else "") + digits


@functools.cache
def inputs_for(operation, radix):
    digit = ALPHABET[radix - 1]
    if operation == "tiny":
        inputs = ("0", "-0", "+" + digit * 3, "-" + digit.upper() * 3)
    elif operation == "dense":
        digits = digit * 4096
        inputs = (digits, "+" + digits.upper(), "-" + digits, "-" + digits.upper())
    elif operation == "leading-zero":
        digits = "0" * 4032 + digit * 64
        inputs = (digits, "+" + digits.upper(), "-" + digits, "-" + digits.upper())
    elif operation == "zero":
        digits = "0" * 4096
        inputs = (digits, "+" + digits, "-" + digits, digits)
    else:
        raise ValueError(operation)
    return inputs


def expected(operation, radix, count):
    inputs = inputs_for(operation, radix)
    canonical_values = tuple(map(canonical, inputs))
    weighted_signs = [(0 if s == "0" else -1 if s.startswith("-") else 1) * (i + 1)
                      for i, s in enumerate(canonical_values)]
    whole, rest = divmod(count, 4)
    checksum = whole * sum(weighted_signs) + sum(weighted_signs[:rest])
    return inputs, canonical_values, checksum, canonical_values[(count - 1) % 4]


def batch_count(operation):
    return 200000 if operation == "tiny" else 4096


def run(binary, operation, radix, count):
    inputs, references, checksum, last = expected(operation, radix, count)
    usage_before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.perf_counter_ns()
    result = subprocess.run([binary, operation, str(radix), str(count), str(checksum),
                             *inputs, *references],
                            check=True, text=True, capture_output=True, timeout=60)
    wall_ns = time.perf_counter_ns() - start
    usage_after = resource.getrusage(resource.RUSAGE_CHILDREN)
    match = re.fullmatch(r"operation=([\w-]+) radix=(\d+) count=(\d+) ns=(\d+) checksum=(-?\d+) last=(\S+)\n",
                         result.stdout)
    if not match or result.stderr or match.group(1, 2, 3, 5, 6) != (
            operation, str(radix), str(count), str(checksum), last):
        raise RuntimeError(f"wrong producer output: {result!r}")
    elapsed = int(match[4])
    if elapsed > wall_ns:
        raise RuntimeError("internal duration exceeds process wall time")
    cpu_ns = round(1e9 * (usage_after.ru_utime + usage_after.ru_stime
                         - usage_before.ru_utime - usage_before.ru_stime))
    return dict(ns_op=elapsed / count, wall_ns=wall_ns, cpu_ns=cpu_ns,
                checksum=checksum, last_length=len(last),
                last_sha256=hashlib.sha256(last.encode()).hexdigest(),
                inputs_sha256=hashlib.sha256("\0".join(inputs).encode()).hexdigest())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("--repeats", type=int, default=8)
    parser.add_argument("--cpu", type=int, default=0)
    args = parser.parse_args()
    if args.repeats < 1:
        raise ValueError("positive repeats required")
    os.sched_setaffinity(0, {args.cpu})
    cases = [(op, radix, count) for op, radix in CASES
             for count in (1, batch_count(op))]
    print(json.dumps(dict(configuration=True, repeats=args.repeats, cases=cases,
                          affinity=sorted(os.sched_getaffinity(0)))))
    for label, binary in (("before", args.before), ("after", args.after)):
        with open(binary, "rb") as stream:
            print(json.dumps(dict(binary=label, sha256=hashlib.file_digest(stream, "sha256").hexdigest())))
    rows = []
    for operation, radix, count in cases:
        for phase in range(-1, args.repeats):
            order = [("before", args.before), ("after", args.after)]
            if phase % 2:
                order.reverse()
            for label, binary in order:
                row = run(binary, operation, radix, count)
                row.update(binary=label, operation=operation, radix=radix,
                           count=count, phase=phase)
                print(json.dumps(row), flush=True)
                if phase >= 0:
                    rows.append(row)
    for operation, radix, count in cases:
        summary = dict(summary=True, operation=operation, radix=radix, count=count)
        for label in ("before", "after"):
            values = [r["ns_op"] for r in rows if
                      (r["operation"], r["radix"], r["count"], r["binary"]) ==
                      (operation, radix, count, label)]
            if len(values) != args.repeats:
                raise RuntimeError("missing rows")
            summary[label] = dict(median=statistics.median(values),
                                  minimum=min(values), maximum=max(values))
        print(json.dumps(summary))


if __name__ == "__main__":
    main()
