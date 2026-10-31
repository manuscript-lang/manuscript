#!/usr/bin/env python3
"""Balanced Decimal truncation comparison, with exact integer output validation."""
import argparse
from decimal import Decimal
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import subprocess
import time

INPUTS = json.loads(Path(__file__).with_name("inputs.json").read_text())


def verify_sources():
    root = Path(__file__).parent
    ms = (root / "main.ms").read_text()
    rust = (root / "rust/src/main.rs").read_text()
    for name, spellings in INPUTS.items():
        m = re.search(r'name == "' + name + r'":\s*values = \[(.*?)\]', ms, re.S)
        if not m or [x.strip().removesuffix("d") for x in m[1].split(",") if x.strip()] != spellings:
            raise RuntimeError(f"Manuscript input drift: {name}")
        m = re.search(r'"' + name + r'" => &\[(.*?)\]', rust, re.S)
        if not m or json.loads("[" + m[1].rstrip().rstrip(",") + "]") != spellings:
            raise RuntimeError(f"Rust input drift: {name}")


def expected(name, count):
    values = []
    for spelling in INPUTS[name]:
        value = int(Decimal(spelling))
        value = value if -(1 << 63) <= value < (1 << 63) else 97
        values.append((abs(value) % 1000003) * (-1 if value < 0 else 1))
    period = math.lcm(len(values), 7)
    terms = [values[i % len(values)] * (i % 7 + 1) for i in range(period)]
    cycles, tail = divmod(count, period)
    return sum(terms) * cycles + sum(terms[:tail])


def run(binary, name, count):
    started = time.time_ns()
    result = subprocess.run([binary, name, str(count)], capture_output=True, text=True,
                            check=True, timeout=60)
    ended = time.time_ns()
    row = re.fullmatch(r"case=([a-z]+) count=([0-9]+) ns=([0-9]+) checksum=(-?[0-9]+)\n",
                       result.stdout)
    if result.stderr or not row or (row[1], int(row[2])) != (name, count):
        raise RuntimeError(f"malformed producer: {result!r}")
    checksum = int(row[4])
    if checksum != expected(name, count):
        raise RuntimeError(f"wrong work: {name}/{count}: {checksum}")
    elapsed = int(row[3])
    if elapsed < 0 or elapsed > ended - started:
        raise RuntimeError("invalid internal timing")
    return dict(ns_op=elapsed / count, checksum=checksum,
                start_unix_ns=started, end_unix_ns=ended)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("rust")
    parser.add_argument("--repeats", type=int, default=8)
    args = parser.parse_args()
    if args.repeats < 8 or args.repeats % 8:
        parser.error("a positive multiple of eight balanced samples required")
    verify_sources()
    binaries = [("before", args.before), ("after", args.after),
                ("rust", args.rust), ("aa", args.before)]
    for label, binary in binaries:
        print(json.dumps(dict(artifact=label, path=binary,
              sha256=hashlib.sha256(Path(binary).read_bytes()).hexdigest())), flush=True)
    rows = []
    for case in INPUTS:
        for count in [1, 8, 1000000]:
            for phase in range(-1, args.repeats):
                offset = phase % len(binaries)
                order = binaries[offset:] + binaries[:offset]
                if (phase // len(binaries)) % 2:
                    order = list(reversed(order))
                for label, binary in order:
                    row = run(binary, case, count)
                    row.update(binary=label, case=case, count=count, phase=phase)
                    rows.append(row)
                    print(json.dumps(row), flush=True)
    # Report only after every producer succeeds, with all identities/counts validated.
    for case in INPUTS:
        for count in [1, 8, 1000000]:
            summary = dict(summary=True, case=case, count=count)
            for label, _ in binaries:
                values = [r["ns_op"] for r in rows if
                          (r["case"], r["count"], r["binary"]) == (case, count, label)
                          and r["phase"] >= 0]
                if len(values) != args.repeats:
                    raise RuntimeError("incomplete comparison")
                summary[label] = dict(median=statistics.median(values),
                                      minimum=min(values), maximum=max(values))
            print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    main()
