import argparse
import hashlib
import json
import math
import os
import re
import resource
import statistics
import subprocess
import time

CASES = [
    ("exponential", "plain", 0), ("exponential", "plain", 2),
    ("exponential", "plain", 100), ("exponential", "wide", 6),
    ("exponential", "wide", 100), ("exponential", "zero", 2),
    ("precision", "plain", 6), ("precision", "plain", 100),
    ("precision", "wide", 6), ("fixed", "plain", 2),
    ("shortest", "plain", 0),
]
CASES += [("parse", dataset, radix) for dataset in ("plain", "wide", "negative") for radix in (2, 10, 16, 36)]
CASES += [("parse_error", dataset, radix) for dataset in ("overflow-short", "overflow-long", "early", "late") for radix in (10, 36)]
CASES += [("parse_zero", "leading", radix) for radix in (10, 36)]

def expected_text(operation, value, digits):
    if operation == "fixed":
        return format(value, f".{digits}f")
    if operation == "shortest":
        return str(int(value)) if value.is_integer() else str(value)
    precision = digits - 1 if operation == "precision" else digits
    mantissa, exponent = format(value, f".{precision}e").split("e")
    exponent = int(exponent)
    if operation == "precision" and -6 <= exponent < digits:
        negative = mantissa.startswith("-")
        numbers = mantissa.lstrip("-").replace(".", "")
        point = exponent + 1
        if point <= 0:
            out = "0." + "0" * -point + numbers
        elif point < len(numbers):
            out = numbers[:point] + "." + numbers[point:]
        else:
            out = numbers + "0" * (point - len(numbers))
        return ("-" if negative else "") + out
    return f"{mantissa}e{exponent:+}"

def expected(case, count):
    operation, dataset, digits = case
    if operation == "parse_zero":
        return count, "1"
    if operation == "parse_error":
        last = "number: invalid data" if dataset in ("early", "late") else "number: value out of range"
        return len(last) * count, last
    if operation == "parse":
        base = {"plain": 0, "wide": 9223372036800000000, "negative": -(1 << 63)}[dataset]
        values = [base + i for i in range(1000)]
        checksums = [(abs(value) % 997) * (-1 if value < 0 else 1) for value in values]
        whole, rest = divmod(count, 1000)
        return whole * sum(checksums) + sum(checksums[:rest]), str(values[(count - 1) % 1000])
    values = [i / 8.0 for i in range(1000)]
    if dataset == "wide":
        values = [float.fromhex("0x1.fffffffffffffp+1023"), float.fromhex("0x0.0000000000001p-1022")]
    elif dataset == "zero":
        values = [0.0, -0.0]
    cycle = [expected_text(operation, value, digits) for value in values]
    whole, rest = divmod(count, len(cycle))
    return whole * sum(map(len, cycle)) + sum(map(len, cycle[:rest])), cycle[(count - 1) % len(cycle)]

def run(binary, case, count):
    checksum, last = expected(case, count)
    previous = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.perf_counter_ns()
    result = subprocess.run([binary, case[0], case[1], str(case[2]), str(count), str(checksum), last],
                            capture_output=True, text=True, timeout=60, check=True)
    wall = time.perf_counter_ns() - started
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    match = re.fullmatch(r"ns=(\d+) checksum=(-?\d+) last=(.+)\n", result.stdout)
    if result.stderr or not match or (int(match[2]), match[3]) != (checksum, last):
        raise RuntimeError(f"invalid producer {result!r}")
    internal = int(match[1])
    if not 0 <= internal <= wall:
        raise RuntimeError("invalid timing")
    cpu = round(1e9 * (usage.ru_utime + usage.ru_stime - previous.ru_utime - previous.ru_stime))
    return dict(ns_op=internal / count, wall_ns=wall, cpu_ns=cpu, checksum=checksum, last=last)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binaries", nargs="+")
    parser.add_argument("--repeats", type=int, default=8)
    parser.add_argument("--count", type=int, default=1000000)
    args = parser.parse_args()
    if args.count <= 0 or args.repeats <= 0:
        raise ValueError("positive counts required")
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    print(json.dumps(dict(config=True, cpu=cpu, count=args.count, repeats=args.repeats,
                         cases=CASES, binaries={b: hashlib.sha256(open(b, "rb").read()).hexdigest() for b in args.binaries})), flush=True)
    # Validate tiny and full-cycle outputs before taking any timing samples.
    for case in CASES:
        for count in [1, 2, 1000]:
            for binary in args.binaries:
                print(json.dumps(dict(control=True, binary=binary, case=case, count=count, **run(binary, case, count))), flush=True)
    rows = []
    for phase in range(-1, args.repeats):
        cases = CASES[phase % len(CASES):] + CASES[:phase % len(CASES)]
        for case in cases:
            cycle = phase % (2 * len(args.binaries))
            shift = cycle % len(args.binaries)
            order = args.binaries[shift:] + args.binaries[:shift]
            if cycle >= len(args.binaries):
                order = list(reversed(order))
            for binary in order:
                count = args.count
                if (case[0] == "parse_float" and case[1] == "long") or (case[0] == "float_error" and case[1] in ("late", "range-long")):
                    count = max(1, args.count // 128)
                elif case[0] == "parse_zero" or (case[0] == "parse_error" and case[1] in ("overflow-long", "late")):
                    count = max(1, args.count // 64)
                row = dict(binary=binary, case=case, count=count, phase=phase, **run(binary, case, count))
                print(json.dumps(row), flush=True)
                if phase >= 0:
                    rows.append(row)
    for case in CASES:
        for binary in args.binaries:
            values = [r["ns_op"] for r in rows if r["case"] == case and r["binary"] == binary]
            if len(values) != args.repeats:
                raise RuntimeError("missing or duplicate samples")
            print(json.dumps(dict(summary=True, case=case, binary=binary, median=statistics.median(values),
                                  minimum=min(values), maximum=max(values))), flush=True)

if __name__ == "__main__":
    main()
