#!/usr/bin/env python3
"""Interleave two already-built LSP harnesses; reject mismatched output/work."""
import argparse
import csv
import math
import statistics
import subprocess
from pathlib import Path


def run(binary, mode, count, shape, rounds, cpu=None):
    command = [str(binary), mode, str(count), str(rounds), shape]
    if cpu is not None:
        command = ["taskset", "--cpu-list", str(cpu), *command]
    fields = subprocess.check_output(
        command, text=True
    ).strip().split(",")
    assert len(fields) == 8, fields
    assert fields[:4] == [mode, str(count), str(rounds), shape], fields
    elapsed, checksum, size, rss = map(int, fields[4:])
    return elapsed, checksum, size, rss


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=10)
    parser.add_argument("--cpu", type=int)
    args = parser.parse_args()
    assert args.samples >= 5
    binaries = {"before": args.before.resolve(), "after": args.after.resolve()}
    cases = []
    for count in (1, 8, 32, 128, 512, 2048, 8192):
        for shape in ("list-flat", "list-lines"):
            cases.append(("semantic", count, shape))
    for count in (1, 128, 2048):
        for shape in ("list-unicode", "list-crlf", "list-unicode-crlf"):
            cases.append(("semantic", count, shape))
    for count in (1, 100, 1000):
        cases.append(("semantic", count, "ascii"))
    for count in (1, 1000):
        for shape in ("unicode", "crlf", "unfinished", "unfinished-crlf"):
            cases.append(("semantic", count, shape))
    cases.extend((("semantic", 1000, "long"), ("semantic", 1, "tail")))
    for mode in ("hover", "hover-name", "hover-blank", "index", "symbols", "references", "completion", "format"):
        for count in (1, 100, 1000):
            cases.append((mode, count, "ascii"))
    for count in (1, 32, 512, 8192):
        for shape in ("list-flat", "list-lines"):
            cases.append(("format", count, shape))
    with args.out.open("w") as stream:
        writer = csv.writer(stream)
        writer.writerow(("mode", "count", "shape", "sample", "binary", "rounds",
                         "elapsed_ns", "checksum_per_query", "source_bytes", "peak_rss_kib", "cpu"))
        for mode, count, shape in cases:
            rounds = {}
            expected = None
            observations = {"before": [], "after": []}
            for name, binary in binaries.items():
                elapsed, checksum, size, _ = run(binary, mode, count, shape, 1, args.cpu)
                if expected is None:
                    expected = (checksum, size)
                assert (checksum, size) == expected
                rounds[name] = min(100_000, max(1, math.ceil(30_000_000 / elapsed)))
            for sample in range(args.samples):
                order = ("before", "after") if sample % 2 == 0 else ("after", "before")
                for name in order:
                    elapsed, checksum, size, rss = run(
                        binaries[name], mode, count, shape, rounds[name], args.cpu
                    )
                    assert (checksum, size) == expected
                    observations[name].append(elapsed / rounds[name])
                    writer.writerow((mode, count, shape, sample, name, rounds[name],
                                     elapsed, checksum, size, rss, args.cpu))
                    stream.flush()
            old, new = (statistics.median(observations[key]) for key in ("before", "after"))
            print(f"{mode},{count},{shape},before={old:.0f}ns,after={new:.0f}ns,ratio={new / old:.3f}",
                  flush=True)


if __name__ == "__main__":
    main()
