#!/usr/bin/env python3
"""Predeclared long controls with interleaved identical-baseline pairs."""

import argparse
import hashlib
import json
import os

from repeat import run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after")
    parser.add_argument("--cpu", type=int, default=0)
    args = parser.parse_args()
    os.sched_setaffinity(0, {args.cpu})
    cases = [("special64", 10000000), ("integral64", 10000000), ("wide64", 1000000)]
    print(json.dumps(dict(configuration=True, phases=12, cases=cases,
                          affinity=sorted(os.sched_getaffinity(0)),
                          aa_uses_identical_before_binary=True)), flush=True)
    for label, binary in (("before", args.before), ("after", args.after)):
        with open(binary, "rb") as stream:
            print(json.dumps(dict(binary=label, sha256=hashlib.file_digest(stream, "sha256").hexdigest())), flush=True)
    for phase in range(-1, 12):
        offset = max(phase, 0) % len(cases)
        order = cases[offset:] + cases[:offset]
        comparisons = ["aa", "candidate"]
        labels = ["before", "after"]
        if phase % 2:
            comparisons.reverse()
            labels.reverse()
        for operation, count in order:
            for comparison in comparisons:
                for label in labels:
                    binary = args.before
                    if comparison == "candidate" and label == "after":
                        binary = args.after
                    row = run(binary, operation, count)
                    row.update(comparison=comparison, binary=label, operation=operation, count=count, phase=phase)
                    print(json.dumps(row), flush=True)


if __name__ == "__main__":
    main()
