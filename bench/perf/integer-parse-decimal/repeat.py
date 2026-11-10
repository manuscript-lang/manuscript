"""Balanced native decimal Optional parsing controls; build producers first."""
import argparse
import hashlib
import json
import os
import re
import resource
import subprocess

CASES = [
    ("format", 0, 2_000_000),
    ("plain", 0, 2_000_000),
    ("max", 0, 2_000_000),
    ("min", 0, 2_000_000),
    ("overflow19", 0, 2_000_000),
    ("invalid19", 0, 2_000_000),
    ("zero", 19, 2_000_000),
    ("zero", 4096, 10_000),
    ("late", 4096, 10_000),
]
CASES += [(kind, length, 2_000_000 if length == 1 else 5000) for kind in ("early", "overflow")
          for length in (1, 1000, 100_000, 1_000_000)]


def run(binary, case):
    kind, length, count = case
    values = {"plain": 12345678, "max": 2**63 - 1, "min": -(2**63), "zero": 1}
    value = values.get(kind, 0)
    residue = abs(value) % 997 * (-1 if value < 0 else 1)
    expected = (17 if kind == "format" else residue) * count
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    result = subprocess.run([binary, kind, str(length), str(count)],
                            capture_output=True, text=True, check=True, timeout=60)
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    match = re.fullmatch(r"ns=(\d+) checksum=(-?\d+)\n", result.stdout)
    if result.stderr or not match or int(match[2]) != expected:
        raise RuntimeError(f"invalid producer result: {result!r}")
    return dict(ns_op=int(match[1]) / count,
                minor_faults=after.ru_minflt - before.ru_minflt,
                major_faults=after.ru_majflt - before.ru_majflt)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("binaries", nargs="+")
    parser.add_argument("--repeats", type=int, default=12)
    args = parser.parse_args()
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    hashes = {}
    for binary in args.binaries:
        with open(binary, "rb") as file:
            hashes[binary] = hashlib.sha256(file.read()).hexdigest()
    print(json.dumps(dict(config=True, cpu=cpu, repeats=args.repeats,
                         binaries=hashes)), flush=True)
    for case in CASES:
        for binary in args.binaries:
            run(binary, (case[0], case[1], 1))
            run(binary, case)
    for phase in range(args.repeats):
        cases = CASES[phase % len(CASES):] + CASES[:phase % len(CASES)]
        offset = (phase // 2) % len(args.binaries)
        binaries = args.binaries[offset:] + args.binaries[:offset]
        if phase % 2:
            cases = list(reversed(cases))
            binaries = list(reversed(binaries))
        for case in cases:
            for binary in binaries:
                print(json.dumps(dict(phase=phase, binary=binary, kind=case[0],
                                      length=case[1], count=case[2], **run(binary, case))), flush=True)


if __name__ == "__main__":
    main()
