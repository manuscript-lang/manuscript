#!/usr/bin/env python3
"""Fixed common-path and long-path controls with interleaved A/A pairs."""

import argparse
import hashlib
import json
import os
from repeat import batch_count, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("--cpu", type=int, default=0)
    args = parser.parse_args()
    os.sched_setaffinity(0, {args.cpu})
    identities = [("tiny", base) for base in (3, 10, 36, 16)] + [
        ("dense", 16), ("leading-zero", 8), ("zero", 32), ("dense", 36)]
    cases = [(op, radix, batch_count(op)) for op, radix in identities]
    print(json.dumps(dict(configuration=True, phases=8, cases=cases,
                          affinity=sorted(os.sched_getaffinity(0)),
                          aa_uses_identical_before_binary=True)), flush=True)
    for label, binary in (("before", args.before), ("after", args.after)):
        with open(binary, "rb") as stream:
            print(json.dumps(dict(binary=label, sha256=hashlib.file_digest(stream, "sha256").hexdigest())), flush=True)
    for phase in range(-1, 8):
        offset = max(phase, 0) % len(cases)
        order = cases[offset:] + cases[:offset]
        comparisons = ["aa", "candidate"]
        labels = ["before", "after"]
        if phase % 2:
            comparisons.reverse()
            labels.reverse()
        for operation, radix, count in order:
            for comparison in comparisons:
                for label in labels:
                    binary = args.before
                    if comparison == "candidate" and label == "after":
                        binary = args.after
                    row = run(binary, operation, radix, count)
                    row.update(comparison=comparison, binary=label,
                               operation=operation, radix=radix, count=count, phase=phase)
                    print(json.dumps(row), flush=True)


if __name__ == "__main__":
    main()
